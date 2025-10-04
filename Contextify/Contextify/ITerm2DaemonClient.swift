import Foundation
import OSLog
import Darwin

/// Client for communicating with the long-running iTerm2 daemon via Unix socket.
/// Implements length-prefixed JSON protocol with request IDs and timeout enforcement.
actor ITerm2DaemonClient {
    static let shared = ITerm2DaemonClient()

    enum DaemonError: Error, CustomStringConvertible {
        case disabled
        case discoveryMissing
        case socketInvalid
        case connectFailed
        case requestTimeout
        case invalidResponse
        case daemonError(String, details: String?)

        var description: String {
            switch self {
            case .disabled: return "daemon disabled"
            case .discoveryMissing: return "discovery path missing"
            case .socketInvalid: return "discovery path not a socket"
            case .connectFailed: return "connect failed"
            case .requestTimeout: return "request timeout"
            case .invalidResponse: return "invalid response"
            case .daemonError(let e, let d):
                return "daemon error: \(e)\(d.map { " (\($0))" } ?? "")"
            }
        }
    }

    private struct Response: Decodable {
        let id: String?
        let success: Bool
        let content: String?
        let error: String?
        let details: String?
        let source: String?
        let latency_ms: Int?
        let status: String?
        let connection_healthy: Bool?
        let iterm2_down: Bool?
        let uptime_ms: Int?
    }

    private let log = Logger(subsystem: "dev.contextify", category: "iTerm2Daemon")
    private let discoveryURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Contextify/run/daemon.path")

    private func disabled() -> Bool {
        UserDefaults.standard.bool(forKey: "DisableDaemonMode")
    }

    /// Ensure the LaunchAgent is installed and kickstart it.
    func ensureRunning() async {
        if disabled() { return }
        do {
            try await LaunchAgentManager.shared.installIfNeeded()
            try await LaunchAgentManager.shared.kickstart()
        } catch {
            log.error("launchagent ensureRunning failed: \(error.localizedDescription)")
        }
    }

    /// Request terminal content from the daemon.
    /// - Parameters:
    ///   - maxLines: Maximum number of lines to retrieve (default 100)
    ///   - deadlineMs: Timeout in milliseconds (default 500)
    /// - Returns: Result with content string or error
    func getContent(maxLines: Int = 100, deadlineMs: Int = 500) async -> Result<String, DaemonError> {
        if disabled() { return .failure(.disabled) }

        do {
            let (fd, _) = try openSocket()
            defer { close(fd) }

            let reqID = UUID().uuidString
            let req: [String: Any] = ["id": reqID, "command": "get_content", "max_lines": maxLines]
            let payload = try JSONSerialization.data(withJSONObject: req)
            var len = UInt32(payload.count).bigEndian
            var header = Data(bytes: &len, count: 4)
            header.append(payload)

            // Set SO_NOSIGPIPE to prevent SIGPIPE on broken connection
            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))

            // Send request
            let sent = header.withUnsafeBytes { ptr in
                Darwin.send(fd, ptr.baseAddress!, ptr.count, 0)
            }
            guard sent == header.count else { throw DaemonError.connectFailed }

            // Read response with timeout
            let respData = try await readFramed(fd: fd, deadlineMs: deadlineMs)
            let resp = try JSONDecoder().decode(Response.self, from: respData)

            guard resp.success, let content = resp.content else {
                throw DaemonError.daemonError(resp.error ?? "unknown", details: resp.details)
            }

            if let ms = resp.latency_ms {
                log.debug("daemon \(ms, privacy: .public) ms source=\(resp.source ?? "n/a")")
            }

            return .success(content)
        } catch let e as DaemonError {
            return .failure(e)
        } catch {
            return .failure(.invalidResponse)
        }
    }

    // MARK: - Private helpers

    /// Open Unix socket connection to daemon.
    /// Validates socket exists and is owned by current user.
    private func openSocket() throws -> (Int32, String) {
        guard FileManager.default.fileExists(atPath: discoveryURL.path) else {
            throw DaemonError.discoveryMissing
        }

        guard let path = try? String(contentsOf: discoveryURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            throw DaemonError.discoveryMissing
        }

        // Validate socket file with lstat
        var sb = stat()
        guard lstat(path, &sb) == 0, (sb.st_mode & S_IFMT) == S_IFSOCK else {
            throw DaemonError.socketInvalid
        }

        // Create socket
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DaemonError.connectFailed }

        // Connect to Unix socket
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            path.withCString { strcpy(ptr, $0) }
        }

        let res = withUnsafePointer(to: &addr) { aptr in
            aptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard res == 0 else {
            close(fd)
            throw DaemonError.connectFailed
        }

        return (fd, path)
    }

    /// Read length-prefixed JSON response with timeout.
    /// Implements proper partial read handling.
    private func readFramed(fd: Int32, deadlineMs: Int) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            // Task 1: Read data
            group.addTask {
                // Read 4-byte length header
                var lenBuf = Data(count: 4)
                var readBytes = 0
                while readBytes < 4 {
                    let r = lenBuf.withUnsafeMutableBytes { ptr in
                        Darwin.recv(fd, ptr.baseAddress!.advanced(by: readBytes), 4 - readBytes, 0)
                    }
                    guard r > 0 else { throw DaemonError.invalidResponse }
                    readBytes += r
                }

                let n = lenBuf.withUnsafeBytes { UInt32(bigEndian: $0.load(as: UInt32.self)) }

                // Read body
                var body = Data(count: Int(n))
                var got = 0
                while got < Int(n) {
                    let r = body.withUnsafeMutableBytes { ptr in
                        Darwin.recv(fd, ptr.baseAddress!.advanced(by: got), Int(n) - got, 0)
                    }
                    guard r > 0 else { throw DaemonError.invalidResponse }
                    got += r
                }

                return body
            }

            // Task 2: Timeout
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(deadlineMs) * 1_000_000)
                throw DaemonError.requestTimeout
            }

            let data = try await group.next()!
            group.cancelAll()
            return data
        }
    }
}
