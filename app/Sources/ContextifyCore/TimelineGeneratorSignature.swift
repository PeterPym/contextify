//
//  TimelineGeneratorSignature.swift
//  ContextifyCore
//
//  Centralized generator signature for timeline cache versioning
//

import Foundation

/// Generates a versioned signature for timeline cache entries
/// Format: model@modelVersion::prompt@promptVersion
///
/// This signature is used to:
/// - Version cached timeline summaries
/// - Invalidate cache when model or prompt changes
/// - Ensure UI and background generator use same versioning
public struct TimelineGeneratorSignature: Sendable {
    public let model: String
    public let modelVersion: String
    public let prompt: String
    public let promptVersion: String

    /// Current production signature (bump versions when changing model or prompt)
    public static let current = TimelineGeneratorSignature(
        model: "gpt-4o",
        modelVersion: "2025-09",
        prompt: "timeline",
        promptVersion: "5"  // Bumped: disposition override for detected directives
    )

    public init(model: String, modelVersion: String, prompt: String, promptVersion: String) {
        self.model = model
        self.modelVersion = modelVersion
        self.prompt = prompt
        self.promptVersion = promptVersion
    }

    /// Returns formatted signature string
    public var string: String {
        "\(model)@\(modelVersion)::\(prompt)@\(promptVersion)"
    }
}

/// Public convenience function for getting current signature string
public func timelineGeneratorSignature() -> String {
    TimelineGeneratorSignature.current.string
}
