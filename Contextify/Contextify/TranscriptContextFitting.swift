//
//  TranscriptContextFitting.swift
//  Contextify
//
//  Utilities for fitting transcript context within LLM token limits
//  Uses guided pre-flight (includes JSON schema overhead) + adaptive compression
//

import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Utilities for ensuring transcript context fits within token limits
struct TranscriptContextFitting {
    private static let log = Logger(subsystem: "dev.contextify.metadata", category: "ContextFitting")

    /// Ensure context fits via guided pre-flight probes (includes JSON schema overhead)
    /// Uses binary shrink and adaptive compression on overflow
    /// All LLM calls go through FoundationLLM (serialized by SessionController)
    ///
    /// IMPORTANT: Pre-flight uses the SAME generation method (guided with schema) as the actual call
    /// to accurately account for JSON schema token overhead (~150-200 tokens).
    static func ensureFitsViaRawPreflight(
        context: String,
        sampledCount: Int,
        totalCount: Int,
        instructions: String,
        maxAttempts: Int = 5,
        llm: FoundationLLM = .shared
    ) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *) else {
            throw ContextError.unavailable
        }

        var currentContext = context
        var currentCount = sampledCount
        var attempt = 0

        while attempt < maxAttempts {
            // Build probe prompt (matches actual call structure)
            let probe = """
            CONTEXT: This excerpt shows \(currentCount) of \(totalCount) messages. First 10 and last 10 are always included; the middle is selected for importance.

            \(currentContext)
            """

            // Use guided generation with schema to test fit (matches actual call)
            let options = GenerationOptions(
                sampling: .greedy,
                temperature: 0,
                maximumResponseTokens: 1
            )

            do {
                log.debug("Pre-flight attempt \(attempt + 1)/\(maxAttempts): \(currentContext.count) chars, ~\(currentCount) messages")
                // Use generateGuided() instead of rawWithInstructions() to include schema overhead
                let _: GuidedTranscriptMetadata = try await llm.generateGuided(
                    instructions: instructions,
                    prompt: probe,
                    generating: GuidedTranscriptMetadata.self,
                    includeSchema: true,  // CRITICAL: must match actual call to account for schema overhead
                    options: options
                )
                // Success! Context fits
                log.info("Pre-flight passed: \(currentContext.count) chars, \(currentCount) messages")
                return currentContext
            } catch let error as LanguageModelSession.GenerationError {
                guard case .exceededContextWindowSize = error else {
                    // Other errors (decoding, guardrails) treated as "fits"
                    log.debug("Pre-flight non-overflow error, treating as fit: \(String(describing: error))")
                    return currentContext
                }

                // Exceeded window - try compression
                attempt += 1
                if attempt >= maxAttempts {
                    log.error("Pre-flight exhausted \(maxAttempts) attempts")
                    throw ContextError.overflow
                }

                // Strategy: first 2 attempts binary shrink, then adaptive compression
                if attempt >= 2 {
                    let level = attempt - 1
                    log.warning("Applying adaptive compression level \(level)")
                    currentContext = compress(currentContext, level: level)
                } else {
                    log.debug("Shrinking context by half")
                    let result = shrinkOnce(currentContext)
                    currentContext = result.context
                    currentCount = result.estimatedCount
                }
            } catch {
                log.error("Pre-flight unexpected error: \(error.localizedDescription)")
                throw error
            }
        }

        throw ContextError.overflow
        #else
        throw ContextError.unavailable
        #endif
    }

    /// Binary shrink: keep first 10 and last 10 lines, drop middle
    private static func shrinkOnce(_ context: String) -> (context: String, estimatedCount: Int) {
        let lines = context.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 20 else {
            return (context, lines.count)
        }

        let head = lines.prefix(10)
        let tail = lines.suffix(10)
        let shrunk = (head + tail).joined(separator: "\n")

        return (shrunk, 20)
    }

    /// Adaptive compression with progressive levels
    /// Level 1: Strip timestamps
    /// Level 2: Collapse duplicate adjacent lines
    /// Level 3: Prefer user lines in middle section
    static func compress(_ context: String, level: Int) -> String {
        var result = context

        // Level 1: Strip timestamps like "+5m23s: " or "+2h: "
        if level >= 1 {
            result = result.replacing(#/\+(\d+h)?(\d+m)?(\d+s)?:\s/#, with: "")
        }

        // Level 2: Collapse repeated adjacent lines
        if level >= 2 {
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            var compressed = [String]()
            var lastTrimmed: String?

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed != lastTrimmed {
                    compressed.append(String(line))
                    lastTrimmed = trimmed
                }
            }
            result = compressed.joined(separator: "\n")
        }

        // Level 3: In middle section, prefer user lines
        if level >= 3 {
            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            guard lines.count > 20 else { return result }

            let head = lines.prefix(10)
            let tail = lines.suffix(10)
            let middle = lines.dropFirst(10).dropLast(10)

            // Keep only user messages from middle
            let userMiddle = middle.filter { $0.hasPrefix("U ") || $0.hasPrefix("U+") }

            result = (head + userMiddle + tail).joined(separator: "\n")
        }

        return result
    }

    enum ContextError: Error, LocalizedError {
        case overflow
        case unavailable

        var errorDescription: String? {
            switch self {
            case .overflow: return "Context exceeded token limit after all compression attempts"
            case .unavailable: return "FoundationModels not available (requires macOS 26+)"
            }
        }
    }
}
