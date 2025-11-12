import Foundation
import GRDB
import OSLog

/// Comprehensive diagnostic state capture for timeline debugging
/// Provides introspection without human intervention
public struct TimelineDiagnosticsSnapshot: Codable, Sendable {
    public let timestamp: Date
    public let projectState: ProjectState?
    public let hooverState: HooverState
    public let watcherState: WatcherState
    public let timelineState: TimelineUIState?
    public let fileState: FileState?
    public let issues: [DiagnosticIssue]

    public struct ProjectState: Codable, Sendable {
        public let projectId: String?
        public let projectPath: String?
        public let isMonitoring: Bool
        public let orchestratorExists: Bool
    }

    public struct HooverState: Codable, Sendable {
        public let transcriptId: String?
        public let lastProcessedLine: Int
        public let fileSizeBytes: Int
        public let lastUpdated: Date?
        public let bytesUnprocessed: Int
        public let linesUnprocessed: Int
        public let isStalled: Bool
        public let stallDurationSeconds: TimeInterval?
    }

    public struct WatcherState: Codable, Sendable {
        public let transcriptId: String?
        public let isWatching: Bool
        public let fileExists: Bool
        public let lastModified: Date?
        public let debounceValue: TimeInterval
    }

    public struct TimelineUIState: Codable, Sendable {
        public let entryCount: Int
        public let visibleEntryCount: Int
        public let lastUpdate: Date?
        public let isProcessing: Bool
        public let lastError: String?
        public let cursorExists: Bool
    }

    public struct FileState: Codable, Sendable {
        public let path: String
        public let exists: Bool
        public let sizeBytes: Int
        public let lineCount: Int
        public let lastModified: Date?
        public let lastContentTimestamp: Date?
    }

    public struct DiagnosticIssue: Codable, Sendable {
        public let severity: Severity
        public let category: Category
        public let message: String
        public let recommendation: String?

        public enum Severity: String, Codable, Sendable {
            case critical   // P0 - timeline completely broken
            case high       // P1 - degraded experience
            case medium     // P2 - minor issue
            case info       // Informational
        }

        public enum Category: String, Codable, Sendable {
            case hooverStall
            case watcherMissing
            case fileSystemIssue
            case databaseLag
            case uiState
            case initialization
        }
    }

    /// Human-readable diagnostic report
    public func report() -> String {
        var lines: [String] = []
        lines.append("=== TIMELINE DIAGNOSTICS SNAPSHOT ===")
        lines.append("Timestamp: \(timestamp)")
        lines.append("")

        // Project State
        if let proj = projectState {
            lines.append("PROJECT STATE:")
            lines.append("  ID: \(proj.projectId ?? "(none)")")
            lines.append("  Path: \(proj.projectPath ?? "(none)")")
            lines.append("  Monitoring: \(proj.isMonitoring ? "✅" : "❌")")
            lines.append("  Orchestrator: \(proj.orchestratorExists ? "✅" : "❌")")
        } else {
            lines.append("PROJECT STATE: ⚠️ Not available")
        }
        lines.append("")

        // Hoover State
        lines.append("HOOVER STATE:")
        lines.append("  Transcript: \(hooverState.transcriptId ?? "(none)")")
        lines.append("  Last Processed Line: \(hooverState.lastProcessedLine)")
        lines.append("  File Size: \(hooverState.fileSizeBytes) bytes")
        lines.append("  Unprocessed: \(hooverState.bytesUnprocessed) bytes (\(hooverState.linesUnprocessed) lines)")
        lines.append("  Last Updated: \(hooverState.lastUpdated?.description ?? "(never)")")
        lines.append("  Stalled: \(hooverState.isStalled ? "❌ YES" : "✅ No")")
        if let stall = hooverState.stallDurationSeconds {
            lines.append("  Stall Duration: \(Int(stall))s")
        }
        lines.append("")

        // Watcher State
        lines.append("WATCHER STATE:")
        lines.append("  Transcript: \(watcherState.transcriptId ?? "(none)")")
        lines.append("  Watching: \(watcherState.isWatching ? "✅" : "❌")")
        lines.append("  File Exists: \(watcherState.fileExists ? "✅" : "❌")")
        lines.append("  Last Modified: \(watcherState.lastModified?.description ?? "(unknown)")")
        lines.append("  Debounce: \(watcherState.debounceValue)s")
        lines.append("")

        // File State
        if let file = fileState {
            lines.append("FILE STATE:")
            lines.append("  Path: \(file.path)")
            lines.append("  Exists: \(file.exists ? "✅" : "❌")")
            lines.append("  Size: \(file.sizeBytes) bytes (\(file.lineCount) lines)")
            lines.append("  Last Modified: \(file.lastModified?.description ?? "(unknown)")")
            lines.append("  Last Content Timestamp: \(file.lastContentTimestamp?.description ?? "(unknown)")")
        }
        lines.append("")

        // Timeline UI State
        if let ui = timelineState {
            lines.append("TIMELINE UI STATE:")
            lines.append("  Entries: \(ui.entryCount) (visible: \(ui.visibleEntryCount))")
            lines.append("  Last Update: \(ui.lastUpdate?.description ?? "(never)")")
            lines.append("  Processing: \(ui.isProcessing ? "🔄" : "✅")")
            lines.append("  Cursor: \(ui.cursorExists ? "✅" : "❌")")
            if let err = ui.lastError {
                lines.append("  Last Error: ❌ \(err)")
            }
        }
        lines.append("")

        // Issues
        if !issues.isEmpty {
            lines.append("ISSUES DETECTED:")
            for (i, issue) in issues.enumerated() {
                let icon: String
                switch issue.severity {
                case .critical: icon = "🔴"
                case .high: icon = "🟠"
                case .medium: icon = "🟡"
                case .info: icon = "🔵"
                }
                lines.append("  \(i+1). \(icon) [\(issue.severity.rawValue.uppercased())] \(issue.category.rawValue)")
                lines.append("     \(issue.message)")
                if let rec = issue.recommendation {
                    lines.append("     → \(rec)")
                }
            }
        } else {
            lines.append("✅ NO ISSUES DETECTED")
        }
        lines.append("")
        lines.append("=== END DIAGNOSTICS ===")

        return lines.joined(separator: "\n")
    }
}

/// Service for capturing timeline diagnostic state
/// Can be called automatically or on-demand for debugging
public actor TimelineDiagnosticsService {
    private let db: DatabasePool
    private let log = Logger(subsystem: "dev.contextify", category: "TimelineDiagnostics")

    public init(db: DatabasePool) {
        self.db = db
    }

    /// Capture full diagnostic snapshot for current project
    /// This can run without human intervention and provides complete state picture
    public func captureSnapshot(
        projectId: String?,
        orchestrator: TranscriptOrchestrator?,
        monitorState: MonitorStateSnapshot?
    ) async -> TimelineDiagnosticsSnapshot {
        let timestamp = Date()
        var issues: [TimelineDiagnosticsSnapshot.DiagnosticIssue] = []

        // 1. Capture project state
        let projectState: TimelineDiagnosticsSnapshot.ProjectState?
        if let pid = projectId {
            let orch = orchestrator != nil
            projectState = .init(
                projectId: pid,
                projectPath: try? orchestrator?.getProject(id: pid)?.rootPath,
                isMonitoring: monitorState?.isMonitoring ?? false,
                orchestratorExists: orch
            )

            if !orch {
                issues.append(.init(
                    severity: .critical,
                    category: .initialization,
                    message: "Orchestrator not initialized",
                    recommendation: "Restart monitoring or check initialization logs"
                ))
            }
        } else {
            projectState = nil
            issues.append(.init(
                severity: .critical,
                category: .initialization,
                message: "No project ID set",
                recommendation: "Check project root configuration"
            ))
        }

        // 2. Find most recent transcript for this project
        let recentTranscript: Transcript? = try? await db.read { (db: Database) -> Transcript? in
            guard let pid = projectId else { return nil }
            return try? Transcript
                .filter(Column("project_id") == pid)
                .order(Column("updated_at").desc)
                .limit(1)
                .fetchOne(db)
        }

        // 3. Capture hoover state from database
        let hooverState: TimelineDiagnosticsSnapshot.HooverState
        if let transcript = recentTranscript {
            let fileURL = URL(fileURLWithPath: transcript.filePath)
            let fileAttrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            let actualFileSize = (fileAttrs?[.size] as? NSNumber)?.intValue ?? 0

            // Read only tail of file for line count (performance optimization)
            let actualLineCount: Int = {
                guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return 0 }
                defer { try? handle.close() }
                let tailSize = 64 * 1024  // 64KB tail
                let fileSize = actualFileSize
                if fileSize > tailSize {
                    try? handle.seek(toOffset: UInt64(fileSize - tailSize))
                }
                guard let data = try? handle.readToEnd() else { return 0 }
                return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).count
            }()

            let bytesUnprocessed = max(0, actualFileSize - (transcript.fileSize ?? 0))
            let linesUnprocessed = max(0, actualLineCount - transcript.lastProcessedLine)

            let lastUpdated = Date(timeIntervalSince1970: TimeInterval(transcript.updatedAt))
            let stallDuration = Date().timeIntervalSince(lastUpdated)
            let isStalled = stallDuration > 60  // No update in 60s = stalled

            hooverState = .init(
                transcriptId: transcript.id,
                lastProcessedLine: transcript.lastProcessedLine,
                fileSizeBytes: transcript.fileSize ?? 0,
                lastUpdated: lastUpdated,
                bytesUnprocessed: bytesUnprocessed,
                linesUnprocessed: linesUnprocessed,
                isStalled: isStalled && bytesUnprocessed > 0,
                stallDurationSeconds: isStalled ? stallDuration : nil
            )

            // Issue detection
            if hooverState.isStalled {
                issues.append(.init(
                    severity: .critical,
                    category: .hooverStall,
                    message: "Hoover stalled for \(Int(stallDuration))s with \(linesUnprocessed) unprocessed lines",
                    recommendation: "Check watcher status and trigger manual hoover if needed"
                ))
            }

            if linesUnprocessed > 10 {
                issues.append(.init(
                    severity: .high,
                    category: .databaseLag,
                    message: "Database is \(linesUnprocessed) lines behind file",
                    recommendation: "Check if watcher is running and hoover engine is healthy"
                ))
            }
        } else {
            hooverState = .init(
                transcriptId: nil,
                lastProcessedLine: 0,
                fileSizeBytes: 0,
                lastUpdated: nil,
                bytesUnprocessed: 0,
                linesUnprocessed: 0,
                isStalled: false,
                stallDurationSeconds: nil
            )

            if projectId != nil {
                issues.append(.init(
                    severity: .high,
                    category: .initialization,
                    message: "No transcripts found for project",
                    recommendation: "Run discovery or check transcript directory"
                ))
            }
        }

        // 4. Capture watcher state
        let watcherState: TimelineDiagnosticsSnapshot.WatcherState
        if let transcript = recentTranscript, let orch = orchestrator {
            let isWatching = orch.isWatchingTranscript(transcriptId: transcript.id)
            let fileURL = URL(fileURLWithPath: transcript.filePath)
            let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
            let fileAttrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            let lastModified = fileAttrs?[.modificationDate] as? Date

            watcherState = .init(
                transcriptId: transcript.id,
                isWatching: isWatching,
                fileExists: fileExists,
                lastModified: lastModified,
                debounceValue: MonitorConfig.fileWatcherDebounce
            )

            // Issue detection
            if !isWatching && fileExists {
                issues.append(.init(
                    severity: .critical,
                    category: .watcherMissing,
                    message: "[TRANSCRIPT-WATCHER] Watcher not running for transcript \(transcript.id) (file exists at \(fileURL.path))",
                    recommendation: "Possible causes: race condition during startup, permission issue, or watcher start failure. Check if timeline updates appear for this transcript."
                ))
            }

            if !fileExists {
                issues.append(.init(
                    severity: .high,
                    category: .fileSystemIssue,
                    message: "Transcript file does not exist: \(fileURL.path)",
                    recommendation: "Check file permissions or path"
                ))
            }
        } else {
            watcherState = .init(
                transcriptId: nil,
                isWatching: false,
                fileExists: false,
                lastModified: nil,
                debounceValue: MonitorConfig.fileWatcherDebounce
            )
        }

        // 5. Capture file state
        let fileState: TimelineDiagnosticsSnapshot.FileState?
        if let transcript = recentTranscript {
            let fileURL = URL(fileURLWithPath: transcript.filePath)
            let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
            let fileAttrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            let sizeBytes = (fileAttrs?[.size] as? NSNumber)?.intValue ?? 0
            let lastModified = fileAttrs?[.modificationDate] as? Date

            let lineCount = (try? String(contentsOf: fileURL, encoding: .utf8)
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
                .count) ?? 0

            // Parse last content timestamp from file
            let lastContentTimestamp = await extractLastTimestamp(from: fileURL)

            fileState = .init(
                path: fileURL.path,
                exists: fileExists,
                sizeBytes: sizeBytes,
                lineCount: lineCount,
                lastModified: lastModified,
                lastContentTimestamp: lastContentTimestamp
            )
        } else {
            fileState = nil
        }

        // 6. Capture timeline UI state
        let timelineState: TimelineDiagnosticsSnapshot.TimelineUIState?
        if let monitor = monitorState {
            timelineState = .init(
                entryCount: monitor.entryCount,
                visibleEntryCount: monitor.visibleEntryCount,
                lastUpdate: monitor.lastUpdate,
                isProcessing: monitor.isProcessing,
                lastError: monitor.lastError,
                cursorExists: monitor.cursorExists
            )

            // Issue detection
            if let lastUpd = monitor.lastUpdate {
                let age = Date().timeIntervalSince(lastUpd)
                if age > 120 {
                    issues.append(.init(
                        severity: .high,
                        category: .uiState,
                        message: "Timeline UI last updated \(Int(age))s ago",
                        recommendation: "Check if incremental updates are working"
                    ))
                }
            }

            if let err = monitor.lastError {
                issues.append(.init(
                    severity: .high,
                    category: .uiState,
                    message: "Timeline error: \(err)",
                    recommendation: "Check logs for stack trace"
                ))
            }
        } else {
            timelineState = nil
        }

        log.info("Captured diagnostic snapshot: \(issues.count) issues detected")

        return TimelineDiagnosticsSnapshot(
            timestamp: timestamp,
            projectState: projectState,
            hooverState: hooverState,
            watcherState: watcherState,
            timelineState: timelineState,
            fileState: fileState,
            issues: issues
        )
    }

    /// Extract last timestamp from transcript file (last line with valid timestamp)
    /// Optimized: reads only last 64KB instead of entire file
    private func extractLastTimestamp(from fileURL: URL) async -> Date? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        let tailSize = 64 * 1024
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue ?? 0

        // Seek to last 64KB if file is larger
        if fileSize > tailSize {
            try? handle.seek(toOffset: UInt64(fileSize - tailSize))
        }

        let data = (try? handle.readToEnd()) ?? Data()
        guard let chunk = String(data: data, encoding: .utf8) else { return nil }
        let lines = chunk.split(separator: "\n").reversed()

        for line in lines {
            guard !line.isEmpty else { continue }
            let data = Data(line.utf8)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let timestamp = json["timestamp"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: timestamp) {
                    return date
                }
            }
        }

        return nil
    }
}

/// Snapshot of ConversationMonitor state (passed from UI layer)
public struct MonitorStateSnapshot: Sendable {
    public let isMonitoring: Bool
    public let entryCount: Int
    public let visibleEntryCount: Int
    public let lastUpdate: Date?
    public let isProcessing: Bool
    public let lastError: String?
    public let cursorExists: Bool

    public init(
        isMonitoring: Bool,
        entryCount: Int,
        visibleEntryCount: Int,
        lastUpdate: Date?,
        isProcessing: Bool,
        lastError: String?,
        cursorExists: Bool
    ) {
        self.isMonitoring = isMonitoring
        self.entryCount = entryCount
        self.visibleEntryCount = visibleEntryCount
        self.lastUpdate = lastUpdate
        self.isProcessing = isProcessing
        self.lastError = lastError
        self.cursorExists = cursorExists
    }
}
