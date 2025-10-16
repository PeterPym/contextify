import Foundation
import ContextifyCore
import OSLog

/// SQL-backed transcript metadata generator
/// Simple nonisolated implementation for background generation
final class SQLBackedMetadataOrchestrator: Sendable {
    private let orchestrator: TranscriptOrchestrator
    private static let limiter = ConcurrencyLimiter(maxConcurrent: 3)

    init(orchestrator: TranscriptOrchestrator) {
        self.orchestrator = orchestrator
    }

    /// Check if metadata needs generation or regeneration
    nonisolated func needsGeneration(transcript: Transcript, transcriptSHA256: String) throws -> Bool {
        guard let existing = try orchestrator.getMetadata(forTranscript: transcript.id) else {
            return true
        }

        if existing.transcriptSha256 != transcriptSHA256 {
            return true
        }

        if existing.title.isEmpty || existing.description.isEmpty {
            return true
        }

        return false
    }

    /// Generate and save metadata (call from background)
    nonisolated func generateAndSave(transcript: Transcript, transcriptSHA256: String) async throws {
        // Extract values before entering @Sendable closure
        let transcriptId = transcript.id
        let projectId = transcript.projectId
        let filePath = transcript.filePath

        try await Self.limiter.withPermit {
            let log = Logger(subsystem: "dev.contextify", category: "SQLMetadata")

        // 1. Read entries from SQL
        let entries = try orchestrator.getEntries(forTranscript: transcriptId, afterTimestamp: nil)
        guard !entries.isEmpty else { return }

        // 2. Convert to exchanges
        let exchanges = Self.convertEntriesToExchanges(entries)
        guard !exchanges.isEmpty else { return }

        // 3. Build context
        let contextBuilder = ContextBuilder()
        let builtContext = try contextBuilder.build(
            exchanges: exchanges,
            strategy: .adaptive,
            budgetTokens: nil
        )

        let exchangeCount = exchanges.count

        // 4. Generate metadata via LLM
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            log.info("Generating metadata for \(filePath)")
            let started = Date()
            do {
                let llmResult = try await TranscriptMetadataLLM.shared.singlePass(
                    context: builtContext.text,
                    sampledCount: builtContext.sampledCount,
                    totalCount: exchangeCount
                )

                // 5. Save to database
                let now = Int(Date().timeIntervalSince1970)
                let latency = Int(Date().timeIntervalSince(started) * 1000)
                let topicsJSON = try JSONEncoder().encode(llmResult.topics)
                let topicsString = String(data: topicsJSON, encoding: .utf8) ?? "[]"

                let metadata = TranscriptMetadataRecord(
                    transcriptId: transcriptId,
                    projectId: projectId,
                    title: llmResult.title,
                    description: llmResult.description,
                    topics: topicsString,
                    confidence: llmResult.confidence,
                    mayContainHallucinations: llmResult.mayContainHallucinations ? 1 : 0,
                    needsReview: llmResult.confidence < 0.7 ? 1 : 0,
                    generatedAt: now,
                    model: "SystemLanguageModel",
                    promptVersion: 1,
                    generatorVersion: 1,
                    transcriptSha256: transcriptSHA256,
                    messageCount: exchangeCount,
                    strategy: "adaptive",
                    llmCalls: 1,
                    latencyMs: latency,
                    createdAt: now,
                    updatedAt: now
                )

                try orchestrator.saveMetadata(metadata)
                log.info("Saved metadata: \(llmResult.title)")
            } catch {
                log.error("LLM failed; saving heuristic metadata: \(error.localizedDescription, privacy: .public)")
                let heuristic = HeuristicMetadata.generate(exchanges: exchanges)
                let now = Int(Date().timeIntervalSince1970)
                let topicsJSON = try JSONEncoder().encode(heuristic.topics)
                let topicsString = String(data: topicsJSON, encoding: .utf8) ?? "[]"

                let metadata = TranscriptMetadataRecord(
                    transcriptId: transcriptId,
                    projectId: projectId,
                    title: heuristic.title,
                    description: heuristic.description,
                    topics: topicsString,
                    confidence: heuristic.confidence,
                    mayContainHallucinations: heuristic.mayContainHallucinations ? 1 : 0,
                    needsReview: 1,
                    generatedAt: now,
                    model: "heuristic",
                    promptVersion: 0,
                    generatorVersion: heuristic.generatorVersion,
                    transcriptSha256: transcriptSHA256,
                    messageCount: exchangeCount,
                    strategy: heuristic.strategy,
                    llmCalls: 0,
                    latencyMs: 0,
                    createdAt: now,
                    updatedAt: now
                )

                try orchestrator.saveMetadata(metadata)
                log.info("Saved heuristic metadata for \(filePath)")
            }
        }
        #endif
        }
    }

    /// Convert TranscriptEntry[] to Exchange[]
    nonisolated private static func convertEntriesToExchanges(_ entries: [TranscriptEntry]) -> [Exchange] {
        var exchanges: [Exchange] = []

        for entry in entries {
            let role: Exchange.Role
            switch entry.kind {
            case "user":
                role = .user
            case "assistant":
                role = .assistant
            default:
                continue
            }

            guard !entry.content.isEmpty else { continue }

            let timestamp = Date(timeIntervalSince1970: TimeInterval(entry.timestamp))
            exchanges.append(Exchange(
                role: role,
                text: entry.content,
                timestamp: timestamp
            ))
        }

        return exchanges
    }
}

// MARK: - ConcurrencyLimiter
actor ConcurrencyLimiter {
    private let max: Int
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.max = maxConcurrent
    }

    /// Scoped permit acquisition - guarantees release on exit
    func withPermit<T>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await body()
    }

    private func acquire() async {
        if inFlight < max {
            inFlight += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        inFlight += 1
    }

    private func release() {
        inFlight = Swift.max(0, inFlight - 1)
        if !waiters.isEmpty {
            let cc = waiters.removeFirst()
            cc.resume()
        }
    }
}
