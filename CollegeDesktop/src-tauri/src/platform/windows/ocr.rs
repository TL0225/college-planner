//! OCR for scanned PDFs via pdftoppm + Windows.Media.Ocr, or Windows.Data.Pdf render.

use anyhow::{anyhow, Context, Result};
use std::path::{Path, PathBuf};
use std::process::Command;
use windows::Graphics::Imaging::{BitmapDecoder, SoftwareBitmap};
use windows::Media::Ocr::OcrEngine;
use windows::Storage::Streams::{DataWriter, InMemoryRandomAccessStream};
use windows::Win32::System::Com::{CoInitializeEx, COINIT_APARTMENTTHREADED};

fn command_on_path(name: &str) -> bool {
    let checker = if cfg!(windows) { "where" } else { "which" };
    Command::new(checker)
        .arg(name)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn ensure_com() -> Result<()> {
    unsafe {
        CoInitializeEx(None, COINIT_APARTMENTTHREADED)
            .ok()
            .context("CoInitializeEx")?;
    }
    Ok(())
}

fn bytes_to_stream(data: &[u8]) -> Result<InMemoryRandomAccessStream> {
    let stream = InMemoryRandomAccessStream::new()?;
    let writer = DataWriter::CreateDataWriter(&stream)?;
    writer.WriteBytes(data)?;
    writer.StoreAsync()?.get()?;
    writer.FlushAsync()?.get()?;
    writer.DetachStream()?;
    stream.Seek(0)?;
    Ok(stream)
}

fn ocr_bitmap(bitmap: &SoftwareBitmap) -> Result<String> {
    let engine = OcrEngine::TryCreateFromUserProfileLanguages()?;
    let result = engine.RecognizeAsync(bitmap)?.get()?;
    Ok(result.Text()?.to_string())
}

fn ocr_image_bytes(png_bytes: &[u8]) -> Result<String> {
    ensure_com()?;
    let stream = bytes_to_stream(png_bytes)?;
    let decoder = BitmapDecoder::CreateAsync(&stream)?.get()?;
    let bitmap = decoder.GetSoftwareBitmapAsync()?.get()?;
    ocr_bitmap(&bitmap)
}

const OCR_MAX_PAGES: u32 = 15;

fn run_pdftoppm(pdf_path: &Path, out_dir: &Path) -> Result<Vec<PathBuf>> {
    let prefix = out_dir.join("page");
    let status = Command::new("pdftoppm")
        .args([
            "-png",
            "-f",
            "1",
            "-l",
            &OCR_MAX_PAGES.to_string(),
            pdf_path.to_str().unwrap_or("input.pdf"),
            prefix.to_str().unwrap_or("page"),
        ])
        .status()
        .context("pdftoppm spawn")?;
    if !status.success() {
        return Err(anyhow!("pdftoppm exited with {status}"));
    }

    let mut pages: Vec<PathBuf> = std::fs::read_dir(out_dir)?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.extension()
                .and_then(|e| e.to_str())
                .map(|e| e.eq_ignore_ascii_case("png"))
                .unwrap_or(false)
        })
        .collect();
    pages.sort();
    if pages.is_empty() {
        return Err(anyhow!("pdftoppm produced no PNG pages"));
    }
    Ok(pages)
}

fn render_pdf_page_bitmap(pdf_bytes: &[u8], page_index: u32) -> Result<SoftwareBitmap> {
    use windows::Data::Pdf::PdfDocument;

    ensure_com()?;
    let stream = bytes_to_stream(pdf_bytes)?;
    let doc = PdfDocument::LoadFromStreamAsync(&stream)?.get()?;
    let page = doc.GetPage(page_index)?;
    let render_stream = InMemoryRandomAccessStream::new()?;
    page.RenderToStreamAsync(&render_stream)?.get()?;
    render_stream.Seek(0)?;
    let decoder = BitmapDecoder::CreateAsync(&render_stream)?.get()?;
    decoder.GetSoftwareBitmapAsync()?.get().map_err(Into::into)
}

fn ocr_pdf_pages_via_winrt(pdf_bytes: &[u8]) -> Result<String> {
    use windows::Data::Pdf::PdfDocument;

    ensure_com()?;
    let stream = bytes_to_stream(pdf_bytes)?;
    let doc = PdfDocument::LoadFromStreamAsync(&stream)?.get()?;
    let count = doc.PageCount()?.min(OCR_MAX_PAGES);
    let mut combined = String::new();

    for i in 0..count {
        let bitmap = render_pdf_page_bitmap(pdf_bytes, i)?;
        let text = ocr_bitmap(&bitmap)?;
        if !text.trim().is_empty() {
            if !combined.is_empty() {
                combined.push('\n');
            }
            combined.push_str(text.trim());
        }
    }

    if combined.trim().is_empty() {
        Err(anyhow!("Windows OCR returned no text"))
    } else {
        Ok(combined)
    }
}

/// Extract text from a scanned PDF using platform OCR.
pub fn ocr_pdf(path: &str, pdf_bytes: &[u8]) -> Result<String> {
    let pdf_path = Path::new(path);
    let temp_dir = std::env::temp_dir().join(format!(
        "college-ocr-{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0)
    ));
    std::fs::create_dir_all(&temp_dir)?;

    let result = (|| {
        if command_on_path("pdftoppm") {
            let work_pdf = if pdf_path.is_file() {
                pdf_path.to_path_buf()
            } else {
                let p = temp_dir.join("input.pdf");
                std::fs::write(&p, pdf_bytes)?;
                p
            };
            let pages = run_pdftoppm(&work_pdf, &temp_dir)?;
            let mut combined = String::new();
            for page in pages {
                let bytes = std::fs::read(&page)?;
                let text = ocr_image_bytes(&bytes)?;
                if !text.trim().is_empty() {
                    if !combined.is_empty() {
                        combined.push('\n');
                    }
                    combined.push_str(text.trim());
                }
            }
            if combined.trim().is_empty() {
                Err(anyhow!("OCR produced no text from pdftoppm pages"))
            } else {
                Ok(combined)
            }
        } else {
            ocr_pdf_pages_via_winrt(pdf_bytes)
        }
    })();

    let _ = std::fs::remove_dir_all(&temp_dir);
    result
}
