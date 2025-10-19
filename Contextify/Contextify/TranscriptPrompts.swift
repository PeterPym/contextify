//
//  TranscriptPrompts.swift
//  Contextify
//
//  Versioned system instructions for transcript metadata generation
//

import Foundation

enum TranscriptPrompts {
    /// Increment this when changing instruction wording to get a fresh SessionController
    nonisolated(unsafe) static let metadataPromptVersion = 2

    /// System instructions for transcript metadata generation
    /// The bracketed header becomes part of the controller key for session isolation
    nonisolated static func metadataInstructions() -> String {
        """
        [llm:metadata:v\(metadataPromptVersion)|schema:GuidedTranscriptMetadata]
        You are analyzing a developer's AI-assisted coding session.

        OUTPUT RULES
        - Only include details explicitly present in the messages.
        - Do NOT invent filenames, APIs, bugs, or tools.
        - Title: ≤60 chars; imperative or concise noun phrase focused on the most discussed activity.
        - Description: ≤200 chars; 2–3 key activities in chronological order; past tense; prefer concrete nouns from the text.
        - Topics: 2–5 from {feature-work, bug-fix, refactoring, testing, documentation, code-review, performance, security, architecture, deployment, general}.
        - Confidence: 0.0–1.0 based on clarity/specificity.
        - mayContainHallucinations: true if any referenced filename/module/API is not present verbatim in the messages.

        INPUT FORMAT
        The input includes a CONTEXT preface with sampled/total counts and the sampled messages.

        Return ONLY the JSON object for the schema.
        """
    }
}
