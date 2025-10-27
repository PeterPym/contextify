//
//  QueueStatsProvider.swift
//  Contextify
//
//  Protocol for observing queue state changes from TimelineCacheMissGenerator
//

import Foundation

/// Protocol for observing queue state changes
protocol QueueStatsProvider: Sendable {
    func observeQueue() -> AsyncStream<QueueStats>
}

// MARK: - Conformance

extension TimelineCacheMissGenerator: QueueStatsProvider {}
// Note: TranscriptMetadataOrchestrator conformance is implicit (actor with observeQueue())

// MARK: - Test Mocks

/// Mock provider for testing
struct MockQueueProvider: QueueStatsProvider {
    let statsSequence: [QueueStats]

    func observeQueue() -> AsyncStream<QueueStats> {
        AsyncStream { continuation in
            for stats in statsSequence {
                continuation.yield(stats)
            }
            continuation.finish()
        }
    }
}

/// Empty provider (simulates nil generator)
struct EmptyQueueProvider: QueueStatsProvider {
    func observeQueue() -> AsyncStream<QueueStats> {
        AsyncStream { continuation in
            continuation.finish()  // empty stream; VM will clear state on finish
        }
    }
}
