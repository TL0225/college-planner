// MLXTokenizerBridge.swift
// Feature: SyllabusAI
// Purpose: SyllabusAI module — Adapted.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import MLXLMCommon
import Tokenizers

/// Bridges `Tokenizers` types to `MLXLMCommon.Tokenizer` without requiring the `MLXHuggingFace` macro target.
enum MLXTokenizerBridge {
    struct Adapted: MLXLMCommon.Tokenizer {
        private let upstream: any Tokenizers.Tokenizer

        init(_ upstream: any Tokenizers.Tokenizer) {
            self.upstream = upstream
        }

        func encode(text: String, addSpecialTokens: Bool) -> [Int] {
            upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
        }

        func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
            upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
        }

        func convertTokenToId(_ token: String) -> Int? {
            upstream.convertTokenToId(token)
        }

        func convertIdToToken(_ id: Int) -> String? {
            upstream.convertIdToToken(id)
        }

        var bosToken: String? { upstream.bosToken }
        var eosToken: String? { upstream.eosToken }
        var unknownToken: String? { upstream.unknownToken }

        func applyChatTemplate(
            messages: [[String: any Sendable]],
            tools: [[String: any Sendable]]?,
            additionalContext: [String: any Sendable]?
        ) throws -> [Int] {
            do {
                return try upstream.applyChatTemplate(
                    messages: messages,
                    tools: tools,
                    additionalContext: additionalContext
                )
            } catch Tokenizers.TokenizerError.missingChatTemplate {
                throw MLXLMCommon.TokenizerError.missingChatTemplate
            }
        }
    }

    struct LocalDirectoryLoader: TokenizerLoader {
        func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
            let upstream = try await AutoTokenizer.from(modelFolder: directory)
            return Adapted(upstream)
        }
    }

    static let localDirectoryLoader = LocalDirectoryLoader()
}
