//
//  LLMSchemas.swift
//  Contextify
//
//  Centralized @Generable schemas for all LLM use cases
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Transcript metadata for developer AI sessions
@available(macOS 26.0, *)
@Generable(description: "Transcript metadata for developer AI sessions")
struct GuidedTranscriptMetadata: Sendable {
    @Guide(description: "Title ≤60 chars; imperative or concise noun phrase.")
    var title: String

    @Guide(description: "Description ≤200 chars; 2–3 activities in chronological order; past tense.")
    var description: String

    @Guide(description: "2–5 topics from allowed set.")
    var topics: [String]

    @Guide(description: "Confidence 0.0–1.0", .range(0...1))
    var confidence: Double

    @Guide(description: "True if any referenced filename/module/API not in messages.")
    var mayContainHallucinations: Bool
}
#endif
