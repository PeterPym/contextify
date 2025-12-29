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

public extension DiscoveredProject.Provider {
  /// Tolerant initializer that handles historical raw values stored in the database.
  init?(dbRaw: String) {
    switch dbRaw.lowercased() {
    case "codex.cli", "codexcli", "codex":
      self = .codexCLI
    case "claude.code", "claudecode", "claude", "anthropic.code":
      self = .claudeCode
    default:
      return nil
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
  /// Providers observed in the database for this project (distinct over transcripts.provider)
  public let providers: Set<DiscoveredProject.Provider>

  public init(
    projectId: String,
    transcriptCount: Int,
    entryCount: Int,
    lastActivity: Date?,
    displayOrder: Int? = nil,
    providers: Set<DiscoveredProject.Provider> = []
  ) {
    self.projectId = projectId
    self.transcriptCount = transcriptCount
    self.entryCount = entryCount
    self.lastActivity = lastActivity
    self.displayOrder = displayOrder
    self.providers = providers
  }
}

/// Progress updates during project discovery
public struct DiscoveryProgress: Sendable {
  public let phase: Phase
  public let currentProject: String?
  public let projectsCompleted: Int
  public let projectsTotal: Int
  public let message: String

  // Transcript-level progress (for granular feedback during ingestion)
  public let currentTranscript: String?
  public let transcriptsCompleted: Int
  public let transcriptsTotal: Int

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
    message: String,
    currentTranscript: String? = nil,
    transcriptsCompleted: Int = 0,
    transcriptsTotal: Int = 0
  ) {
    self.phase = phase
    self.currentProject = currentProject
    self.projectsCompleted = projectsCompleted
    self.projectsTotal = projectsTotal
    self.message = message
    self.currentTranscript = currentTranscript
    self.transcriptsCompleted = transcriptsCompleted
    self.transcriptsTotal = transcriptsTotal
  }
}

// MARK: - Codex Indexing

/// Indexed view of Codex sessions grouped by normalized project path
public struct CodexIndex: Sendable {
  public struct FileRecord: Sendable {
    public let relativePath: String  // Path relative to ~/.codex/sessions
    public let sessionId: String
    public let mtime: Date

    public init(relativePath: String, sessionId: String, mtime: Date) {
      self.relativePath = relativePath
      self.sessionId = sessionId
      self.mtime = mtime
    }
  }

  public struct ProjectEntry: Sendable {
    public var files: [FileRecord]
    public var latestMtime: Date?

    public init(files: [FileRecord] = [], latestMtime: Date? = nil) {
      self.files = files
      self.latestMtime = latestMtime
    }
  }

  public let projects: [String: ProjectEntry]  // normalized project path → entry
  public let totalFiles: Int
  public let errorCount: Int
  public let duration: TimeInterval

  public init(
    projects: [String: ProjectEntry],
    totalFiles: Int,
    errorCount: Int,
    duration: TimeInterval
  ) {
    self.projects = projects
    self.totalFiles = totalFiles
    self.errorCount = errorCount
    self.duration = duration
  }
}

// MARK: - Lightweight Project (Cross-Platform)

/// Lightweight project metadata (no DB required)
/// Used by LightweightDiscoveryService for fast filesystem scanning
public struct LightweightProject: Sendable, Identifiable, Hashable {
  public let id: String
  public let path: URL
  public let displayName: String  // Friendly name derived during discovery
  public let transcriptCount: Int
  public let lastActivity: Date
  public let provider: String
  public let cwd: String?  // Real project path (for Codex) or decoded path (for Claude)
  public let transcriptFiles: [URL]  // File paths discovered during scan (for JIT ingestion)

  public init(id: String, path: URL, displayName: String, transcriptCount: Int, lastActivity: Date, provider: String, cwd: String? = nil, transcriptFiles: [URL] = []) {
    self.id = id
    self.path = path
    self.displayName = displayName
    self.transcriptCount = transcriptCount
    self.lastActivity = lastActivity
    self.provider = provider
    self.cwd = cwd
    self.transcriptFiles = transcriptFiles
  }

  /// Canonical root path used for database identity (defaults to filesystem path if decoding fails).
  public var canonicalRootPath: String {
    PathUtils.canonicalizePath(cwd ?? path.path)
  }
}
