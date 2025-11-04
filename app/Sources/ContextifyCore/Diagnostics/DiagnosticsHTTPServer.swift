import Foundation
import Network
import OSLog

/// Localhost HTTP server for external diagnostic access
/// App Store safe: binds to 127.0.0.1 only, high port number
public actor DiagnosticsHTTPServer {
    private let log = Logger(subsystem: "dev.contextify", category: "DiagnosticsHTTPServer")
    private let port: UInt16 = 17329  // High port, unlikely to conflict

    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]

    // Handlers for dynamic data
    private var diagnosticsHandler: (() async -> TimelineDiagnosticsSnapshot?)?
    private var recentEntriesHandler: ((Int) async -> [TimelineEntrySnapshot])?

    public init() {}

    /// Start HTTP server on localhost:17329
    /// - Parameters:
    ///   - diagnosticsHandler: Closure to capture diagnostic snapshot
    ///   - recentEntriesHandler: Closure to get recent timeline entries
    public func start(
        diagnosticsHandler: @escaping @Sendable () async -> TimelineDiagnosticsSnapshot?,
        recentEntriesHandler: @escaping @Sendable (Int) async -> [TimelineEntrySnapshot]
    ) throws {
        self.diagnosticsHandler = diagnosticsHandler
        self.recentEntriesHandler = recentEntriesHandler

        // Create listener bound to localhost only (App Store safe)
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.acceptLocalOnly = true  // Critical: localhost only

        guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port)) else {
            log.error("Failed to create HTTP listener on port \(self.port)")
            throw DiagnosticsHTTPError.failedToCreateListener
        }

        self.listener = listener

        // Handle new connections
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleConnection(connection) }
        }

        // State change handler
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Task { await self.log.info("📡 Diagnostics HTTP API listening on http://127.0.0.1:\(self.port)") }
            case .failed(let error):
                Task { await self.log.error("HTTP listener failed: \(error.localizedDescription)") }
            case .cancelled:
                Task { await self.log.info("📡 Diagnostics HTTP API stopped") }
            default:
                break
            }
        }

        listener.start(queue: .global(qos: .utility))
        log.info("📡 Starting diagnostics HTTP server on port \(self.port)")
    }

    /// Stop HTTP server
    public func stop() {
        // Close all active connections
        for (_, connection) in connections {
            connection.cancel()
        }
        connections.removeAll()

        listener?.cancel()
        listener = nil

        log.info("📡 Diagnostics HTTP server stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        let id = UUID()
        connections[id] = connection

        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                Task { await self?.receiveRequest(connection, id: id) }
            } else if case .failed = state, case .cancelled = state {
                Task { await self?.removeConnection(id) }
            }
        }

        connection.start(queue: .global(qos: .utility))
    }

    private func removeConnection(_ id: UUID) {
        connections.removeValue(forKey: id)
    }

    private func receiveRequest(_ connection: NWConnection, id: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, isComplete, error in
            guard let self, let data = data, !data.isEmpty else {
                if isComplete {
                    Task { await self?.removeConnection(id) }
                }
                return
            }

            Task {
                await self.processRequest(data, connection: connection, id: id)

                if isComplete {
                    await self.removeConnection(id)
                }
            }
        }
    }

    private func processRequest(_ data: Data, connection: NWConnection, id: UUID) async {
        guard let requestString = String(data: data, encoding: .utf8) else {
            await sendResponse(connection, status: 400, body: "Bad Request")
            return
        }

        // Parse simple HTTP GET request
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            await sendResponse(connection, status: 400, body: "Bad Request")
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            await sendResponse(connection, status: 405, body: "Method Not Allowed")
            return
        }

        let path = parts[1]
        await handleRequest(path: path, connection: connection)
    }

    // MARK: - Request Routing

    private func handleRequest(path: String, connection: NWConnection) async {
        log.debug("📡 HTTP request: \(path)")

        switch path {
        case "/health":
            await handleHealth(connection)

        case "/diagnostics":
            await handleDiagnostics(connection)

        case let p where p.hasPrefix("/timeline/recent"):
            let count = parseQueryParam(path: p, param: "count").flatMap(Int.init) ?? 10
            await handleRecentEntries(connection, count: count)

        case "/timeline/latest":
            await handleLatestEntry(connection)

        default:
            await sendResponse(connection, status: 404, body: "Not Found")
        }
    }

    // MARK: - Endpoint Handlers

    private func handleHealth(_ connection: NWConnection) async {
        let response = [
            "status": "ok",
            "port": port,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ] as [String: Any]

        await sendJSON(connection, data: response)
    }

    private func handleDiagnostics(_ connection: NWConnection) async {
        guard let handler = diagnosticsHandler else {
            await sendResponse(connection, status: 503, body: "Diagnostics handler not configured")
            return
        }

        guard let snapshot = await handler() else {
            await sendResponse(connection, status: 500, body: "Failed to capture diagnostics")
            return
        }

        await sendJSON(connection, encodable: snapshot)
    }

    private func handleRecentEntries(_ connection: NWConnection, count: Int) async {
        guard let handler = recentEntriesHandler else {
            await sendResponse(connection, status: 503, body: "Timeline handler not configured")
            return
        }

        let entries = await handler(count)
        let response: [String: Any] = [
            "entries": entries.map { $0.toDictionary() },
            "count": entries.count,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        await sendJSON(connection, data: response)
    }

    private func handleLatestEntry(_ connection: NWConnection) async {
        guard let handler = recentEntriesHandler else {
            await sendResponse(connection, status: 503, body: "Timeline handler not configured")
            return
        }

        let entries = await handler(1)
        guard let latest = entries.first else {
            await sendResponse(connection, status: 404, body: "No entries found")
            return
        }

        let response: [String: Any] = [
            "entry": latest.toDictionary(),
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        await sendJSON(connection, data: response)
    }

    // MARK: - Response Helpers

    private func sendJSON(_ connection: NWConnection, encodable: some Encodable) async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(encodable),
              let json = String(data: data, encoding: .utf8) else {
            await sendResponse(connection, status: 500, body: "JSON encoding failed")
            return
        }

        await sendResponse(connection, status: 200, body: json, contentType: "application/json")
    }

    private func sendJSON(_ connection: NWConnection, data: [String: Any]) async {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: jsonData, encoding: .utf8) else {
            await sendResponse(connection, status: 500, body: "JSON encoding failed")
            return
        }

        await sendResponse(connection, status: 200, body: json, contentType: "application/json")
    }

    private func sendResponse(_ connection: NWConnection, status: Int, body: String, contentType: String = "text/plain") async {
        let statusText = HTTPStatus.text(for: status)
        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: \(contentType); charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        guard let data = response.data(using: .utf8) else { return }

        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Helpers

    private func parseQueryParam(path: String, param: String) -> String? {
        guard let url = URLComponents(string: path),
              let queryItems = url.queryItems else {
            return nil
        }

        return queryItems.first(where: { $0.name == param })?.value
    }
}

// MARK: - Timeline Entry Snapshot

/// Lightweight snapshot of timeline entry for API responses
public struct TimelineEntrySnapshot: Codable, Sendable {
    public let entryId: String
    public let timestamp: Date
    public let disposition: String
    public let role: String?
    public let content: String?
    public let provider: String?
    public let presentSummary: String?
    public let pastSummary: String?
    public let isGenerating: Bool
    public let isNonSummarizable: Bool
    public let isError: Bool

    public init(
        entryId: String,
        timestamp: Date,
        disposition: String,
        role: String?,
        content: String?,
        provider: String?,
        presentSummary: String?,
        pastSummary: String?,
        isGenerating: Bool,
        isNonSummarizable: Bool,
        isError: Bool
    ) {
        self.entryId = entryId
        self.timestamp = timestamp
        self.disposition = disposition
        self.role = role
        self.content = content
        self.provider = provider
        self.presentSummary = presentSummary
        self.pastSummary = pastSummary
        self.isGenerating = isGenerating
        self.isNonSummarizable = isNonSummarizable
        self.isError = isError
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "entry_id": entryId,
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "disposition": disposition,
            "is_generating": isGenerating,
            "is_non_summarizable": isNonSummarizable,
            "is_error": isError
        ]

        if let role = role { dict["role"] = role }
        if let content = content { dict["content"] = content }
        if let provider = provider { dict["provider"] = provider }
        if let presentSummary = presentSummary { dict["present_summary"] = presentSummary }
        if let pastSummary = pastSummary { dict["past_summary"] = pastSummary }

        return dict
    }
}

// MARK: - HTTP Helpers

private enum HTTPStatus {
    static func text(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "Unknown"
        }
    }
}

public enum DiagnosticsHTTPError: Error {
    case failedToCreateListener
}
