use std::collections::HashMap;

use chrono::{Datelike, Local};
use typst::diag::FileError;
use typst::foundations::{Bytes, Datetime};
use typst::syntax::{FileId, Source, VirtualPath};
use typst::text::{Font, FontBook};
use typst::utils::LazyHash;
use typst::{Library, World};
use typst_assets::fonts;

/// In-memory Typst world with a virtual file system (VFS) for future `#import` support.
pub struct ResumeWorld {
    library: LazyHash<Library>,
    book: LazyHash<FontBook>,
    fonts: Vec<Font>,
    main_id: FileId,
    sources: HashMap<FileId, Source>,
}

impl ResumeWorld {
    pub fn new(main_source: &str) -> Self {
        let main_path = VirtualPath::new("main.typ");
        let main_id = FileId::new(None, main_path);
        let source = Source::new(main_id, main_source.to_string());

        let mut sources = HashMap::new();
        sources.insert(main_id, source);

        let (book, fonts) = load_embedded_fonts();

        Self {
            library: LazyHash::new(Library::builder().build()),
            book: LazyHash::new(book),
            fonts,
            main_id,
            sources,
        }
    }

    pub fn with_extra_source(mut self, path: &str, content: &str) -> Self {
        let virtual_path = VirtualPath::new(path);
        let id = FileId::new(None, virtual_path);
        self.sources.insert(id, Source::new(id, content.to_string()));
        self
    }
}

impl World for ResumeWorld {
    fn library(&self) -> &LazyHash<Library> {
        &self.library
    }

    fn book(&self) -> &LazyHash<FontBook> {
        &self.book
    }

    fn main(&self) -> FileId {
        self.main_id
    }

    fn source(&self, id: FileId) -> Result<Source, FileError> {
        self.sources
            .get(&id)
            .cloned()
            .ok_or(FileError::NotFound(id.vpath().as_rootless_path().into()))
    }

    fn file(&self, id: FileId) -> Result<Bytes, FileError> {
        Err(FileError::NotFound(
            id.vpath().as_rootless_path().into(),
        ))
    }

    fn font(&self, index: usize) -> Option<Font> {
        self.fonts.get(index).cloned()
    }

    fn today(&self, offset: Option<i64>) -> Option<Datetime> {
        let now = Local::now();
        let mut year = now.year();
        let mut month = now.month() as u8;
        let mut day = now.day() as u8;

        if let Some(offset_days) = offset {
            use chrono::Duration;
            let adjusted = now.date_naive() + Duration::days(offset_days);
            year = adjusted.year();
            month = adjusted.month() as u8;
            day = adjusted.day() as u8;
        }

        Datetime::from_ymd_hms(year, month, day, 0, 0, 0)
    }
}

fn load_embedded_fonts() -> (FontBook, Vec<Font>) {
    let loaded: Vec<Font> = fonts()
        .flat_map(|data| Font::iter(Bytes::new(data)))
        .collect();
    let book = FontBook::from_fonts(&loaded);
    (book, loaded)
}

pub fn compile_to_pdf(source: &str) -> Result<Vec<u8>, String> {
    let world = ResumeWorld::new(source);
    let warned = typst::compile(&world);
    let document = warned
        .output
        .map_err(|errors| format_diagnostics(&errors))?;

    typst_pdf::pdf(&document, &typst_pdf::PdfOptions::default())
        .map_err(|errors| format_diagnostics(&errors))
}

fn format_diagnostics(errors: &[typst::diag::SourceDiagnostic]) -> String {
    errors
        .iter()
        .map(|diag| diag.message.to_string())
        .collect::<Vec<_>>()
        .join("; ")
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_TYP: &str = r#"
#set page(margin: 1in)
#set text(font: "Libertinus Serif", size: 11pt)
= Timothy Leung 梁
#text(size: 9pt)[timothy\@example.com · github.com/timothy]
== Education
*BS Computer Science* \
University at Buffalo · May 2027
"#;

    const CJK_SAMPLE_TYP: &str = r#"
#set page(margin: 1in)
#set text(size: 11pt)
= 김민수
Software Engineer
"#;

    #[test]
    fn compiles_sample_resume_to_pdf() {
        let pdf = compile_to_pdf(SAMPLE_TYP).expect("compile sample resume");
        assert!(pdf.starts_with(b"%PDF"));
        assert!(pdf.len() > 500);
    }

    #[test]
    fn compiles_cjk_name_to_pdf() {
        let pdf = compile_to_pdf(CJK_SAMPLE_TYP).expect("compile CJK resume");
        assert!(pdf.starts_with(b"%PDF"));
    }
}
