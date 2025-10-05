import Foundation
import OSLog
import Darwin

/// Client for communicating with the long-running iTerm2 daemon via Unix socket.
/// Implements length-prefixed JSON protocol with request IDs, retries, and
/// additional socket hardening.
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
            case .daemonError(let error, let details):
                let suffix = details.map { " (\($0))" } ?? ""
                return "daemon error: \(error)\(suffix)"
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
        let protocol_version: Int?
        let truncated: Bool?
    }

    private let log = Logger(subsystem: "dev.contextify", category: "iTerm2Daemon")
    private let discoveryURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Contextify/run/daemon.path")
    private var lastDiscoveryMtime: Date?

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

    /// Request terminal content from the daemon with bounded retries.
    /// - Parameters:
    ///   - maxLines: Maximum number of lines to retrieve (default 100, clamped to 1...10_000)
    ///   - deadlineMs: Timeout in milliseconds (default 500)
    func getContent(maxLines: Int = 100, deadlineMs: Int = 500) async -> Result<String, DaemonError> {
        if disabled() { return .failure(.disabled) }

        let safeDeadline = max(100, min(deadlineMs, 2000))

        func performOnce() async throws -> String {
            let (fd, _) = try openSocket()
            defer { close(fd) }

            let requestID = UUID().uuidString
            let safeLines = max(1, min(maxLines, 10_000))
            let request: [String: Any] = ["id": requestID, "command": "get_content", "max_lines": safeLines]
            let payload = try JSONSerialization.data(withJSONObject: request)

            var length = UInt32(payload.count).bigEndian
            var frame = Data(bytes: &length, count: 4)
            frame.append(payload)

            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))

            let timeoutSec = safeDeadline / 1000
            let timeoutUsec = Int32((safeDeadline % 1000) * 1000)
            var timeout = timeval(tv_sec: timeoutSec, tv_usec: timeoutUsec)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            let flags = fcntl(fd, F_GETFD)
            if flags != -1 { _ = fcntl(fd, F_SETFD, flags | FD_CLOEXEC) }

            let sent = frame.withUnsafeBytes { ptr in
                Darwin.send(fd, ptr.baseAddress!, ptr.count, 0)
            }
            guard sent == frame.count else { throw DaemonError.connectFailed }

            let respData = try await readFramed(fd: fd, deadlineMs: safeDeadline)
            let resp = try JSONDecoder().decode(Response.self, from: respData)

            guard (resp.protocol_version ?? 1) == 1 else { throw DaemonError.invalidResponse }
            guard resp.success, let content = resp.content else {
                throw DaemonError.daemonError(resp.error ?? "unknown", details: resp.details)
            }

            if let latency = resp.latency_ms {
                log.debug("daemon \(latency, privacy: .public) ms source=\(resp.source ?? "n/a") truncated=\(resp.truncated == true)")
            }

            return content
        }

        do {
            return .success(try await performOnce())
        } catch {
            _ = refreshDiscoveryMtime()
            do { return .success(try await performOnce()) }
            catch let err as DaemonError { return .failure(err) }
            catch { return .failure(.invalidResponse) }
        }
    }

    private func refreshDiscoveryMtime() -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: discoveryURL.path),
              let mtime = attrs[.modificationDate] as? Date else {
            return nil
        }
        if let last = lastDiscoveryMtime, mtime > last {
            log.info("Discovery file updated, daemon likely restarted")
        }
        lastDiscoveryMtime = mtime
        return mtime
    }

    /// Open Unix socket connection to daemon.
    private func openSocket() throws -> (Int32, String) {
        guard FileManager.default.fileExists(atPath: discoveryURL.path) else {
            throw DaemonError.discoveryMissing
        }

        var attempts = 0
        var socketPath: String?
        var currentMtime: Date?
        while attempts < 3 {
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: discoveryURL.path)
                currentMtime = attrs[.modificationDate] as? Date
                let content = try String(contentsOf: discoveryURL, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty {
                    socketPath = content
                    break
                }
            } catch {
                // fall through to retry
            }
            attempts += 1
            usleep(10_000)
        }

        guard let path = socketPath else { throw DaemonError.discoveryMissing }
        if let mtime = currentMtime {
            if let last = lastDiscoveryMtime, mtime > last {
                log.info("Discovery file updated, daemon likely restarted")
            }
            lastDiscoveryMtime = mtime
        }

        var sb = stat()
        guard lstat(path, &sb) == 0,
              (sb.st_mode & S_IFMT) == S_IFSOCK,
              sb.st_uid == getuid() else {
            throw DaemonError.socketInvalid
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DaemonError.connectFailed }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLen else {
            close(fd)
            throw DaemonError.connectFailed
        }
        _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            path.withCString { strcpy(ptr, $0) }
        }

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            throw DaemonError.connectFailed
        }

        return (fd, path)
    }

    /// Read length-prefixed JSON response with timeout and partial read handling.
    private func readFramed(fd: Int32, deadlineMs: Int) async throws -> Data {
        let maxResp = 256 * 1024
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                var lenBuf = Data(count: 4)
                var readBytes = 0
                while readBytes < 4 {
                    let r = lenBuf.withUnsafeMutableBytes { ptr in
                        Darwin.recv(fd, ptr.baseAddress!.advanced(by: readBytes), 4 - readBytes, 0)
                    }
                    guard r > 0 else { throw DaemonError.invalidResponse }
                    readBytes += r
                }

                let length = lenBuf.withUnsafeBytes { UInt32(bigEndian: $0.load(as: UInt32.self)) }
                guard length <= maxResp else { throw DaemonError.invalidResponse }

                var body = Data(count: Int(length))
                var got = 0
                while got < Int(length) {
                    let r = body.withUnsafeMutableBytes { ptr in
                        Darwin.recv(fd, ptr.baseAddress!.advanced(by: got), Int(length) - got, 0)
                    }
                    guard r > 0 else { throw DaemonError.invalidResponse }
                    got += r
                }
                return body
            }

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
