// college-core/src/html_parser.rs — html5ever token-stream HTML utilities.

use html5ever::tokenizer::{
    BufferQueue, Tag, TagKind, Token, TokenSink, TokenSinkResult, Tokenizer,
    TokenizerOpts,
};

// ---------------------------------------------------------------------------
// Link extraction
// ---------------------------------------------------------------------------

pub fn extract_links_containing(html: &str, needle: &str) -> Vec<String> {
    let sink = LinkSink { needle: needle.to_string(), results: Vec::new() };
    let sink = run_tokenizer(html, sink);
    sink.results
}

struct LinkSink { needle: String, results: Vec<String> }
impl TokenSink for LinkSink {
    type Handle = ();
    fn process_token(&mut self, token: Token, _: u64) -> TokenSinkResult<()> {
        if let Token::TagToken(Tag {
            kind: TagKind::StartTag, ref name, ref attrs, ..
        }) = token {
            if &**name == "a" {
                for attr in attrs {
                    if &*attr.name.local == "href" {
                        let href = attr.value.to_string();
                        if href.contains(&*self.needle) { self.results.push(href); }
                    }
                }
            }
        }
        TokenSinkResult::Continue
    }
}

// ---------------------------------------------------------------------------
// Text selection
// ---------------------------------------------------------------------------

pub fn select_text(html: &str, selector: &str) -> Vec<String> {
    let sink = TextSink {
        matcher: SimpleMatcher::from_selector(selector),
        depth: 0, capture_depth: None,
        current_text: String::new(), results: Vec::new(),
    };
    let sink = run_tokenizer(html, sink);
    sink.results
}

enum SimpleMatcher { Tag(String), Class(String), Id(String), Attr(String) }
impl SimpleMatcher {
    fn from_selector(sel: &str) -> Self {
        let sel = sel.trim();
        if let Some(r) = sel.strip_prefix('.') { return Self::Class(r.to_lowercase()); }
        if let Some(r) = sel.strip_prefix('#') { return Self::Id(r.to_string()); }
        if sel.starts_with('[') && sel.ends_with(']') {
            return Self::Attr(sel[1..sel.len()-1].to_string());
        }
        Self::Tag(sel.to_lowercase())
    }
    fn matches(&self, tag: &Tag) -> bool {
        match self {
            Self::Tag(t)   => &*tag.name == t.as_str(),
            Self::Class(c) => tag.attrs.iter().any(|a|
                &*a.name.local == "class" && a.value.split_whitespace().any(|x| x == c.as_str())),
            Self::Id(id)   => tag.attrs.iter().any(|a|
                &*a.name.local == "id" && &*a.value == id.as_str()),
            Self::Attr(at) => tag.attrs.iter().any(|a| &*a.name.local == at.as_str()),
        }
    }
}

struct TextSink {
    matcher: SimpleMatcher, depth: usize, capture_depth: Option<usize>,
    current_text: String, results: Vec<String>,
}
impl TokenSink for TextSink {
    type Handle = ();
    fn process_token(&mut self, token: Token, _: u64) -> TokenSinkResult<()> {
        match token {
            Token::TagToken(ref tag) => match tag.kind {
                TagKind::StartTag => {
                    self.depth += 1;
                    if self.capture_depth.is_none() && self.matcher.matches(tag) {
                        self.capture_depth = Some(self.depth);
                    }
                }
                TagKind::EndTag => {
                    if let Some(cd) = self.capture_depth {
                        if self.depth == cd {
                            let t = collapse_ws(&self.current_text);
                            if !t.is_empty() { self.results.push(t); }
                            self.current_text.clear();
                            self.capture_depth = None;
                        }
                    }
                    if self.depth > 0 { self.depth -= 1; }
                }
            },
            Token::CharacterTokens(s) => {
                if self.capture_depth.is_some() { self.current_text.push_str(&s); }
            }
            _ => {}
        }
        TokenSinkResult::Continue
    }
}

fn collapse_ws(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut prev = true;
    for c in s.chars() {
        if c.is_whitespace() { if !prev { out.push(' '); } prev = true; }
        else { out.push(c); prev = false; }
    }
    if out.ends_with(' ') { out.pop(); }
    out
}

// ---------------------------------------------------------------------------
// Shared runner — sink is moved in and returned after parsing.
// ---------------------------------------------------------------------------

fn run_tokenizer<S: TokenSink>(html: &str, sink: S) -> S {
    let mut queue = BufferQueue::default();
    queue.push_back(html5ever::tendril::StrTendril::from(html));
    let mut tok = Tokenizer::new(sink, TokenizerOpts::default());
    let _ = tok.feed(&mut queue);
    tok.end();
    tok.sink
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn test_links() {
        let html = r#"<a href="/catalog/X">A</a><a href="/other">B</a>"#;
        assert_eq!(extract_links_containing(html, "/catalog/"), vec!["/catalog/X"]);
    }
    #[test]
    fn test_tag() {
        assert_eq!(select_text("<h1>Hello</h1>", "h1"), vec!["Hello"]);
    }
    #[test]
    fn test_class() {
        let html = r#"<div class="ct">CSE 116</div><div>X</div>"#;
        assert_eq!(select_text(html, ".ct"), vec!["CSE 116"]);
    }
}
