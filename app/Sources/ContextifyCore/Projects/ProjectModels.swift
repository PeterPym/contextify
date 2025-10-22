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

  public init(
    id: String,
    name: String,
    path: URL,
    providers: Set<Provider>,
    transcriptCount: Int,
    entryCount: Int,
    lastActivity: Date?,
    isCurrent: Bool,
    ingestionError: String? = nil
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
  }

  public enum Provider: String, Sendable, Hashable, CaseIterable {
    case claudeCode = "claude.code"
    case codex = "codex"

    public var displayName: String {
      switch self {
      case .claudeCode: return "Claude Code"
      case .codex: return "Codex CLI"
      }
    }

    public var icon: String {
      switch self {
      case .claudeCode: return "🔵"
      case .codex: return "🟡"
      }
    }

    /// Image asset name for provider logomark (matches TimelineModels.Provider.iconImage)
    public var iconImage: String {
      switch self {
      case .claudeCode: return "claude-code-icon"
      case .codex: return "codex-icon"
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

  public init(
    projectId: String,
    transcriptCount: Int,
    entryCount: Int,
    lastActivity: Date?
  ) {
    self.projectId = projectId
    self.transcriptCount = transcriptCount
    self.entryCount = entryCount
    self.lastActivity = lastActivity
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
