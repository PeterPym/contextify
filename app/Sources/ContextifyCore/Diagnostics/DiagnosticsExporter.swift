import Foundation
import OSLog

/// File-based API for external diagnostic access
/// Monitors trigger file and exports diagnostics on request
public actor DiagnosticsExporter {
    private let log = Logger(subsystem: "dev.contextify", category: "DiagnosticsExporter")
    private let triggerPath = "/tmp/contextify-diag-request"
    private let responsePath = "/tmp/contextify-diag-response.json"
    private let statePath = "/tmp/contextify-state.json"

    private var monitorTask: Task<Void, Never>?
    private var periodicExportTask: Task<Void, Never>?
    private var captureHandler: (() async -> TimelineDiagnosticsSnapshot?)?

    public init() {}

    /// Start monitoring for diagnostic requests
    /// - Parameter captureHandler: Async closure that captures diagnostics
    public func startMonitoring(captureHandler: @escaping () async -> TimelineDiagnosticsSnapshot?) {
        self.captureHandler = captureHandler

        // Task 1: Monitor trigger file for on-demand requests
        monitorTask = Task {
            log.info("📡 Diagnostics API: monitoring trigger file")

            while !Task.isCancelled {
                do {
                    // Check for trigger file every 2 seconds
                    try await Task.sleep(for: .seconds(2))

                    if FileManager.default.fileExists(atPath: triggerPath) {
                        log.info("📡 Diagnostics request received")
                        await handleDiagnosticRequest()
                    }
                } catch is CancellationError {
                    break
                } catch {
                    log.error("Diagnostics monitor error: \(error.localizedDescription)")
                }
            }

            log.info("📡 Diagnostics API: monitoring stopped")
        }

        // Task 2: Periodic state export (every 10s)
        periodicExportTask = Task {
            log.info("📡 Diagnostics API: periodic export started")

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(10))

                    guard !Task.isCancelled else { break }
                    await exportState()
                } catch is CancellationError {
                    break
                } catch {
                    log.error("Periodic export error: \(error.localizedDescription)")
                }
            }

            log.info("📡 Diagnostics API: periodic export stopped")
        }
    }

    /// Stop monitoring
    public func stopMonitoring() {
        monitorTask?.cancel()
        periodicExportTask?.cancel()
        monitorTask = nil
        periodicExportTask = nil

        // Clean up temp files
        try? FileManager.default.removeItem(atPath: triggerPath)
        try? FileManager.default.removeItem(atPath: responsePath)
        try? FileManager.default.removeItem(atPath: statePath)
    }

    /// Handle diagnostic request from trigger file
    private func handleDiagnosticRequest() async {
        guard let handler = captureHandler else {
            log.error("No capture handler configured")
            return
        }

        // Capture diagnostics
        guard let snapshot = await handler() else {
            log.error("Failed to capture diagnostics")
            try? FileManager.default.removeItem(atPath: triggerPath)
            return
        }

        // Export as JSON
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let data = try encoder.encode(snapshot)
            try data.write(to: URL(fileURLWithPath: responsePath), options: .atomic)

            log.info("📡 Diagnostics exported to \(self.responsePath)")

            // Also write human-readable report
            let reportPath = "/tmp/contextify-diag-report.txt"
            try snapshot.report().write(to: URL(fileURLWithPath: reportPath), atomically: true, encoding: .utf8)

            log.info("📡 Report exported to \(reportPath)")
        } catch {
            log.error("Failed to export diagnostics: \(error.localizedDescription)")
        }

        // Remove trigger file
        try? FileManager.default.removeItem(atPath: triggerPath)
    }

    /// Export current state periodically
    private func exportState() async {
        guard let handler = captureHandler else { return }

        guard let snapshot = await handler() else { return }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let data = try encoder.encode(snapshot)
            try data.write(to: URL(fileURLWithPath: statePath), options: .atomic)

            log.debug("📡 State exported to \(self.statePath)")
        } catch {
            log.error("Failed to export state: \(error.localizedDescription)")
        }
    }
}

/// Convenience wrapper for reading diagnostics from external process
public struct DiagnosticsClient {
    private static let triggerPath = "/tmp/contextify-diag-request"
    private static let responsePath = "/tmp/contextify-diag-response.json"
    private static let statePath = "/tmp/contextify-state.json"

    /// Request fresh diagnostics (waits for response)
    /// - Parameter timeout: Max time to wait for response (default 5s)
    /// - Returns: Diagnostic snapshot or nil if timeout
    public static func requestDiagnostics(timeout: TimeInterval = 5.0) async throws -> TimelineDiagnosticsSnapshot? {
        // Create trigger file
        try "request".write(to: URL(fileURLWithPath: triggerPath), atomically: true, encoding: .utf8)

        // Wait for response
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: responsePath) {
                let data = try Data(contentsOf: URL(fileURLWithPath: responsePath))
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let snapshot = try decoder.decode(TimelineDiagnosticsSnapshot.self, from: data)

                // Clean up response file
                try? FileManager.default.removeItem(atPath: responsePath)

                return snapshot
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        // Timeout - clean up trigger
        try? FileManager.default.removeItem(atPath: triggerPath)
        return nil
    }

    /// Read most recent periodic state export (non-blocking)
    /// - Returns: Diagnostic snapshot or nil if not available
    public static func readState() throws -> TimelineDiagnosticsSnapshot? {
        guard FileManager.default.fileExists(atPath: statePath) else {
            return nil
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: statePath))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TimelineDiagnosticsSnapshot.self, from: data)
    }
}
