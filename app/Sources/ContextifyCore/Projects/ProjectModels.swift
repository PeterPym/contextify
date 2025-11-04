import Foundation

/// A discovered project with metadata
public struct DiscoveredProject: Sendable, Identifiable, Equatable {
  public let id: String               // Project path (unique identifier)
  public let name: String              // Display name
  public let path: URL                 // Filesystem path
  public let providers: Set<Provider>  // .claudeCode, .codex, or both
  public let transcriptCount: Int      // Count from database
  public let entryCount: Int           // Total entries from database
  public let lastActivity: Date?       // Most recent transcript timestamp
  public let isCurrent: Bool           // Is this the active project?
  public let ingestionError: String?   // Error message if ingestion failed
  public let displayOrder: Int?        // Display order from database (for tab bar sorting)

  public init(
    id: String,
    name: String,
    path: URL,
    providers: Set<Provider>,
    transcriptCount: Int,
    entryCount: Int,
    lastActivity: Date?,
    isCurrent: Bool,
    ingestionError: String? = nil,
    displayOrder: Int? = nil
  ) {
    self.id = id
    self.name = name
    self.path = path
    self.providers = providers
    self.transcriptCount = transcriptCount
    self.entryCount = entryCount
    self.lastActivity = lastActivity
    self.isCurrent = isCurrent
    self.ingestionError = ingestionError
    self.displayOrder = displayOrder
  }

  public enum Provider: String, Sendable, Hashable, CaseIterable {
    case claudeCode = "claude.code"
    case codexCLI = "codex.cli"
    case other  // T2: Safe fallback for unknown providers

    public var displayName: String {
      switch self {
      case .claudeCode: return "Claude Code"
      case .codexCLI: return "Codex CLI"
      case .other: return "Other"  // T2
      }
    }

    public var icon: String {
      switch self {
      case .claudeCode: return "🔵"
      case .codexCLI: return "🟡"
      case .other: return "🔄"  // T2
      }
    }

    /// Image asset name for provider logomark (matches TimelineModels.Provider.iconImage)
    public var iconImage: String {
      switch self {
      case .claudeCode: return "claude-code-icon"
      case .codexCLI: return "codex-icon"
      case .other: return "sparkles"  // T2: SF Symbol fallback
      }
    }
  }
}

/// Metadata about a project from the database
public struct ProjectMetadata: Sendable {
  public let projectId: String
  public let transcriptCount: Int
  public let entryCount: Int
  public let lastActivity: Date?
  public let displayOrder: Int?

  public init(
    projectId: String,
    transcriptCount: Int,
    entryCount: Int,
    lastActivity: Date?,
    displayOrder: Int? = nil
  ) {
    self.projectId = projectId
    self.transcriptCount = transcriptCount
    self.entryCount = entryCount
    self.lastActivity = lastActivity
    self.displayOrder = displayOrder
  }
}

/// Progress updates during project discovery
public struct DiscoveryProgress: Sendable {
  public let phase: Phase
  public let currentProject: String?
  public let projectsCompleted: Int
  public let projectsTotal: Int
  public let message: String

  public enum Phase: Sendable {
    case scanning      // Finding projects
    case ingesting     // Loading transcripts
    case complete
  }

  public init(
    phase: Phase,
    currentProject: String? = nil,
    projectsCompleted: Int,
    projectsTotal: Int,
    message: String
  ) {
    self.phase = phase
    self.currentProject = currentProject
    self.projectsCompleted = projectsCompleted
    self.projectsTotal = projectsTotal
    self.message = message
  }
}
