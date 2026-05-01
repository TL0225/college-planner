// college-core/src/prereq.rs
//
// Recursive-descent parser for prerequisite strings found in university catalogs.
//
// Grammar (simplified):
//   expr     := and_expr  ("or" and_expr)*
//   and_expr := primary   ("and" primary)*
//   primary  := course_code | "(" expr ")" | credit_clause | other_text
//
// Returns a JSON-encoded PrereqRule tree:
//
//   {"type":"course","code":"CSE 116"}
//   {"type":"and","children":[...]}
//   {"type":"or","children":[...]}
//   {"type":"credits","min":N,"desc":"..."}
//   {"type":"text","value":"..."}
//
// The parser is intentionally permissive — anything it cannot recognize becomes
// a {"type":"text"} leaf so information is never silently dropped.

use std::fmt::Write;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Parse `input` and return a JSON string, or `None` if the input is empty
/// after trimming.
pub fn parse_to_json(input: &str) -> Option<String> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return None;
    }
    let tokens = tokenize(trimmed);
    if tokens.is_empty() {
        return None;
    }
    let mut parser = Parser::new(&tokens);
    let rule = parser.parse_expr();
    Some(rule_to_json(&rule))
}

// ---------------------------------------------------------------------------
// Lexer
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
enum Token {
    /// A course code like "CSE 116" or "MTH 142"
    Course(String),
    /// Keyword "or" (case-insensitive)
    Or,
    /// Keyword "and" (case-insensitive)
    And,
    LParen,
    RParen,
    /// Anything else (credit clauses, free text)
    Text(String),
}

fn tokenize(input: &str) -> Vec<Token> {
    let mut tokens = Vec::new();
    let chars: Vec<char> = input.chars().collect();
    let mut i = 0;

    while i < chars.len() {
        // Skip leading whitespace
        if chars[i].is_whitespace() {
            i += 1;
            continue;
        }

        if chars[i] == '(' {
            tokens.push(Token::LParen);
            i += 1;
            continue;
        }
        if chars[i] == ')' {
            tokens.push(Token::RParen);
            i += 1;
            continue;
        }

        // Try to match a course code: 2–4 uppercase letters followed by optional space
        // and 3–4 digits, e.g. "CSE 116", "MTH142", "BISC 241"
        if chars[i].is_ascii_alphabetic() {
            let start = i;
            // Collect the letter part
            while i < chars.len() && chars[i].is_ascii_alphabetic() {
                i += 1;
            }
            let letter_part: String = chars[start..i].iter().collect();

            // Optional single space
            let had_space = if i < chars.len() && chars[i] == ' ' {
                i += 1;
                true
            } else {
                false
            };

            // Try numeric part (3–4 digits)
            if i < chars.len() && chars[i].is_ascii_digit() {
                let num_start = i;
                while i < chars.len() && chars[i].is_ascii_digit() {
                    i += 1;
                }
                let num_part: String = chars[num_start..i].iter().collect();
                let digit_count = num_part.len();

                if letter_part.len() >= 2
                    && letter_part.len() <= 4
                    && digit_count >= 3
                    && digit_count <= 4
                {
                    // Valid course code
                    let code = if had_space {
                        format!("{} {}", letter_part, num_part)
                    } else {
                        format!("{}{}", letter_part, num_part)
                    };
                    tokens.push(Token::Course(code));
                    continue;
                } else {
                    // Not a course code — rewind and fall through to keyword / text
                    i = start;
                }
            } else {
                // No digits — check for keywords
                let word_upper: String = letter_part.to_uppercase();
                match word_upper.as_str() {
                    "OR" => {
                        if !had_space || i == start + letter_part.len() + 1 {
                            tokens.push(Token::Or);
                            continue;
                        }
                    }
                    "AND" => {
                        tokens.push(Token::And);
                        continue;
                    }
                    _ => {}
                }
                // Fall through: rewind and accumulate as text
                i = start;
            }
        }

        // Accumulate as free text until whitespace / paren
        let start = i;
        while i < chars.len() && chars[i] != '(' && chars[i] != ')' {
            // Stop if we see " or " or " and " boundaries
            if i + 4 <= chars.len() {
                let slice: String = chars[i..i + 4].iter().collect();
                if slice.eq_ignore_ascii_case(" or ") || slice.eq_ignore_ascii_case(" and") {
                    break;
                }
            }
            i += 1;
        }
        let text: String = chars[start..i].iter().collect();
        let trimmed = text.trim();
        if !trimmed.is_empty() {
            tokens.push(Token::Text(trimmed.to_string()));
        }
    }
    tokens
}

// ---------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------

#[derive(Debug)]
enum Rule {
    Course(String),
    And(Vec<Rule>),
    Or(Vec<Rule>),
    Text(String),
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

struct Parser<'a> {
    tokens: &'a [Token],
    pos: usize,
}

impl<'a> Parser<'a> {
    fn new(tokens: &'a [Token]) -> Self {
        Parser { tokens, pos: 0 }
    }

    fn peek(&self) -> Option<&Token> {
        self.tokens.get(self.pos)
    }

    fn consume(&mut self) -> Option<&Token> {
        let t = self.tokens.get(self.pos);
        if t.is_some() {
            self.pos += 1;
        }
        t
    }

    /// expr := and_expr ("or" and_expr)*
    fn parse_expr(&mut self) -> Rule {
        let first = self.parse_and();
        let mut children = vec![first];

        while matches!(self.peek(), Some(Token::Or)) {
            self.consume(); // eat "or"
            children.push(self.parse_and());
        }

        if children.len() == 1 {
            children.remove(0)
        } else {
            Rule::Or(children)
        }
    }

    /// and_expr := primary ("and" primary)*
    fn parse_and(&mut self) -> Rule {
        let first = self.parse_primary();
        let mut children = vec![first];

        while matches!(self.peek(), Some(Token::And)) {
            self.consume(); // eat "and"
            children.push(self.parse_primary());
        }

        if children.len() == 1 {
            children.remove(0)
        } else {
            Rule::And(children)
        }
    }

    /// primary := course | "(" expr ")" | text
    fn parse_primary(&mut self) -> Rule {
        match self.peek() {
            Some(Token::Course(_)) => {
                if let Some(Token::Course(code)) = self.consume() {
                    Rule::Course(code.clone())
                } else {
                    unreachable!()
                }
            }
            Some(Token::LParen) => {
                self.consume(); // eat "("
                let inner = self.parse_expr();
                if matches!(self.peek(), Some(Token::RParen)) {
                    self.consume(); // eat ")"
                }
                inner
            }
            Some(Token::Text(_)) => {
                if let Some(Token::Text(t)) = self.consume() {
                    Rule::Text(t.clone())
                } else {
                    unreachable!()
                }
            }
            _ => {
                // Consume one token as unknown text
                if let Some(t) = self.consume() {
                    Rule::Text(format!("{:?}", t))
                } else {
                    Rule::Text(String::new())
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// JSON serialisation
// ---------------------------------------------------------------------------

fn rule_to_json(rule: &Rule) -> String {
    let mut out = String::new();
    write_rule_json(rule, &mut out);
    out
}

fn write_rule_json(rule: &Rule, out: &mut String) {
    match rule {
        Rule::Course(code) => {
            let _ = write!(out, r#"{{"type":"course","code":"{}"}}"#, json_escape(code));
        }
        Rule::And(children) => {
            out.push_str(r#"{"type":"and","children":["#);
            for (i, child) in children.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write_rule_json(child, out);
            }
            out.push_str("]}");
        }
        Rule::Or(children) => {
            out.push_str(r#"{"type":"or","children":["#);
            for (i, child) in children.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write_rule_json(child, out);
            }
            out.push_str("]}");
        }
        Rule::Text(t) => {
            let _ = write!(out, r#"{{"type":"text","value":"{}"}}"#, json_escape(t));
        }
    }
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c => out.push(c),
        }
    }
    out
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_single_course() {
        let json = parse_to_json("CSE 116").unwrap();
        assert_eq!(json, r#"{"type":"course","code":"CSE 116"}"#);
    }

    #[test]
    fn test_or_expression() {
        let json = parse_to_json("CSE 116 or CSE 113").unwrap();
        assert!(json.contains(r#""type":"or""#));
        assert!(json.contains("CSE 116"));
        assert!(json.contains("CSE 113"));
    }

    #[test]
    fn test_and_expression() {
        let json = parse_to_json("CSE 116 and MTH 142").unwrap();
        assert!(json.contains(r#""type":"and""#));
    }

    #[test]
    fn test_nested() {
        let json = parse_to_json("CSE 116 or (CSE 113 and MTH 142)").unwrap();
        assert!(json.contains(r#""type":"or""#));
        assert!(json.contains(r#""type":"and""#));
    }

    #[test]
    fn test_empty_returns_none() {
        assert!(parse_to_json("   ").is_none());
    }
}
