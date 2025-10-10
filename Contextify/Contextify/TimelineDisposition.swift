//
//  TimelineDisposition.swift
//  Contextify
//
//  Type-safe enums for timeline entry disposition and tense handling.
//

import Foundation

/// Disposition categorizes the nature of a timeline entry (what the assistant is doing)
enum Disposition: String, Codable, Sendable {
  case directive    // User instruction or request
  case proposal     // Claude proposing an action
  case progress     // Claude working on something
  case completion   // Claude finished a task
  case analysis     // Claude analyzing/thinking
  case question     // Claude asking for clarification
  case refusal      // Claude declining to do something
  case note         // Informational note
  case error        // Error state
  case unknown      // Fallback for unrecognized dispositions
}

/// Tense determines which form of a dual-form summary to display
enum Tense: String, Codable, Sendable {
  case presentContinuous  // "Claude is implementing X"
  case pastSimple         // "Claude implemented X"
}
