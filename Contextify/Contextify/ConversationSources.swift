import Foundation

struct TranscriptSession: Hashable, Sendable {
    let provider: TimelineSourceContext.Provider
    let identifier: String
    let fileURL: URL
    let lastActivity: Date
    let entryCount: Int  // Number of conversation entries (excludes metadata-only records)
}

// MARK: - DEPRECATED: File-based providers (replaced by database-backed discovery)

// Session discovery now uses the database layer:
// - ConversationMonitor.switchToClaudeCodeSession() discovers files and calls orchestrator.upsertTranscripts()
// - allSessions is populated via orchestrator.getTranscripts(), not these providers
// - File-based providers have been removed as they violated bronze-layer architecture
