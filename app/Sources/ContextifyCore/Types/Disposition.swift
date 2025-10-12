//
//  Disposition.swift
//  ContextifyCore
//
//  Shared timeline entry disposition type
//

import Foundation

/// Represents the disposition/state of a timeline entry
public enum Disposition: String, Codable, Sendable {
    case active
    case completion
    case directive
    case progress
    case analysis
    case note
    case unknown
}
