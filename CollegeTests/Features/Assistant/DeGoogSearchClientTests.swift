// DeGoogSearchClientTests.swift
// Layer 3 — DeGoog JSON parsing.

import Foundation
import Testing
@testable import College

@Suite("DeGoog Search Client")
struct DeGoogSearchClientTests {

    @Test("Parses DeGoog /api/search JSON")
    func parseSearchJSON() throws {
        let json = """
        {
          "query": "rust lifetimes",
          "type": "web",
          "resultCount": 2,
          "results": [
            {
              "title": "Rust Lifetimes",
              "url": "https://example.com/lifetimes",
              "snippet": "Ownership and borrowing.",
              "source": "DuckDuckGo"
            },
            {
              "title": "The Rust Book",
              "url": "https://doc.rust-lang.org/book/ch10-00-generics.html",
              "content": "Validating references with lifetimes.",
              "sources": ["Wikipedia"]
            }
          ]
        }
        """.data(using: .utf8)!

        let hits = try DeGoogSearchClient.parseResults(data: json, maxResults: 4)
        #expect(hits.count == 2)
        #expect(hits[0].title == "Rust Lifetimes")
        #expect(hits[0].engine == "DuckDuckGo")
        #expect(hits[1].content.contains("lifetimes"))
        #expect(hits[1].engine == "Wikipedia")
    }
}
