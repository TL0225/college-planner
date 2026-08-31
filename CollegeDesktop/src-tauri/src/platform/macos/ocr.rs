//! OCR helpers for scanned PDFs on macOS (pdftotext, optional Vision via swift).

use anyhow::{anyhow, Context, Result};
use std::path::Path;
use std::process::Command;

fn command_on_path(name: &str) -> bool {
    Command::new("which")
        .arg(name)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn try_pdftotext(path: &Path) -> Option<String> {
    if !command_on_path("pdftotext") {
        return None;
    }
    let output = Command::new("pdftotext")
        .args(["-layout", path.to_str()?])
        .arg("-")
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if text.is_empty() {
        None
    } else {
        Some(text)
    }
}

const VISION_SWIFT: &str = r#"
import Foundation
import PDFKit
import Vision

let path = CommandLine.arguments[1]
guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else { exit(2) }
var out = ""
let pages = min(doc.pageCount, 3)
for i in 0..<pages {
    guard let page = doc.page(at: i) else { continue }
    let bounds = page.bounds(for: .mediaBox)
    let scale: CGFloat = 2.0
    let w = Int(bounds.width * scale)
    let h = Int(bounds.height * scale)
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: ctx)
    guard let cg = ctx.makeImage() else { continue }
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    try? handler.perform([req])
    for obs in req.results ?? [] {
        if let t = obs.topCandidates(1).first?.string { out += t + "\n" }
    }
}
print(out.trimmingCharacters(in: .whitespacesAndNewlines))
"#;

fn try_vision_swift(path: &Path) -> Option<String> {
    if !command_on_path("swift") {
        return None;
    }
    let output = Command::new("swift")
        .arg("-e")
        .arg(VISION_SWIFT)
        .arg(path)
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if text.is_empty() {
        None
    } else {
        Some(text)
    }
}

/// Extract text from a scanned PDF using macOS OCR helpers.
pub fn ocr_pdf(path: &str) -> Result<String> {
    let pdf_path = Path::new(path);
    if !pdf_path.is_file() {
        return Err(anyhow!("PDF not found: {path}"));
    }

    if let Some(text) = try_pdftotext(pdf_path) {
        return Ok(text);
    }
    if let Some(text) = try_vision_swift(pdf_path) {
        return Ok(text);
    }

    Err(anyhow!("No OCR tools available (install poppler pdftotext or use Xcode swift)"))
}
