import Foundation
import OSLog
import Darwin

/// Manages the iTerm2 daemon LaunchAgent lifecycle.
/// Copies daemon script and Python venv to Application Support,
/// creates LaunchAgent plist, and bootstraps the agent.
actor LaunchAgentManager {
    static let shared = LaunchAgentManager()
    private let log = Logger(subsystem: "dev.contextify", category: "LaunchAgent")

    private let label = "dev.contextify.iterm2-daemon"

    private var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Contextify", isDirectory: true)
    }

    private var scriptsDir: URL { appSupport.appendingPathComponent("scripts", isDirectory: true) }
    private var venvDir: URL { appSupport.appendingPathComponent("venv", isDirectory: true) }
    private var logsDir: URL { appSupport.appendingPathComponent("logs", isDirectory: true) }
    private var runDir: URL { appSupport.appendingPathComponent("run", isDirectory: true) }
    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// Status of the Python venv health check
    enum VenvStatus: CustomStringConvertible {
        case healthy
        case missing
        case symlinkToSystem  // BROKEN - needs rebuild
        case missingDependencies
        case versionMismatch

        var description: String {
            switch self {
            case .healthy: return "healthy"
            case .missing: return "missing"
            case .symlinkToSystem: return "symlinkToSystem"
            case .missingDependencies: return "missingDependencies"
            case .versionMismatch: return "versionMismatch"
            }
        }
    }

    /// Install LaunchAgent if not already installed.
    /// Validates venv health and rebuilds if needed, copies daemon script, writes plist, bootstraps agent.
    func installIfNeeded() async throws {
        try createDirs()
        rotateLogsIfNeeded()

        // Copy daemon script (always)
        try copyDaemonScript()

        // Check venv health and rebuild if needed
        let status = await validateVenv()
        switch status {
        case .healthy:
            log.info("Venv is healthy, using existing")

        case .missing, .symlinkToSystem, .missingDependencies, .versionMismatch:
            log.info("Venv needs rebuild (status: \(status))")
            try await rebuildVenvFromSystem()
        }

        try writePlist()
        try bootstrapAndEnable()
    }

    /// Kickstart the daemon to ensure it's running.
    func kickstart() async throws {
        try run("/bin/launchctl", ["kickstart", "gui/\(getuid())/\(label)"])
    }

    /// Validate the health of the Python venv.
    /// Checks for symlinks to system Python, missing dependencies, and version mismatches.
    func validateVenv() async -> VenvStatus {
        let pythonBin = venvDir.appendingPathComponent("bin/python3")

        // Check 1: Executable exists
        guard FileManager.default.isExecutableFile(atPath: pythonBin.path) else {
            log.info("Venv validation: python3 executable not found")
            return .missing
        }

        // Check 2: Not a symlink to system Python (CRITICAL CHECK - currently missing)
        do {
            let resolved = try FileManager.default.destinationOfSymbolicLink(atPath: pythonBin.path)
            if resolved.contains("/usr/bin") ||
               resolved.contains("Xcode.app") ||
               resolved.contains("/opt/homebrew") {
                log.warning("Venv validation: python is symlinked to system: \(resolved)")
                return .symlinkToSystem  // BROKEN - will fail when app bundle moves
            }
        } catch {
            // Not a symlink - good (or unreadable - proceed to next check)
        }

        // Check 3: Can import iterm2 with correct version
        let testCmd = "\(pythonBin.path) -c 'import iterm2; print(iterm2.__version__)'"
        do {
            let (exitCode, output) = try run("/bin/sh", ["-c", testCmd])
            guard exitCode == 0 else {
                log.warning("Venv validation: iterm2 module import failed")
                return .missingDependencies
            }

            // Check 4: Version matches expectation
            let expectedVersion = "2.7"  // or read from config
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedOutput.contains(expectedVersion) {
                log.warning("Venv validation: iterm2 version mismatch: got \(trimmedOutput), expected \(expectedVersion)")
                return .versionMismatch
            }
        } catch {
            log.warning("Venv validation: iterm2 check failed: \(error)")
            return .missingDependencies
        }

        log.info("Venv validation: healthy")
        return .healthy
    }

    /// Rebuild the Python venv from system Python.
    /// Creates a fresh venv with --copies to avoid symlinks, then installs iterm2==2.7.
    /// Throws if venv creation or pip install fails.
    func rebuildVenvFromSystem() async throws {
        log.info("Rebuilding venv from system Python")

        // Clean slate
        let fm = FileManager.default
        if fm.fileExists(atPath: self.venvDir.path) {
            log.info("Removing existing venv at \(self.venvDir.path)")
            try fm.removeItem(at: self.venvDir)
        }

        // Create fresh venv with --copies to avoid symlinks
        log.info("Creating venv with --copies flag")
        let (exitCode1, output1) = try run("/usr/bin/python3", [
            "-m", "venv",
            "--copies",  // CRITICAL: Avoid symlinks
            self.venvDir.path
        ])
        guard exitCode1 == 0 else {
            throw NSError(domain: "Contextify", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "venv creation failed: \(output1)"])
        }

        // Install iterm2
        log.info("Installing iterm2==2.7 via pip")
        let pip = self.venvDir.appendingPathComponent("bin/pip3")
        let (exitCode2, output2) = try run(pip.path, [
            "install",
            "--no-cache-dir",  // Fresh download
            "iterm2==2.7"      // Pin version
        ])
        guard exitCode2 == 0 else {
            throw NSError(domain: "Contextify", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "pip install failed: \(output2)"])
        }

        log.info("Venv rebuild complete")
    }

    // MARK: - Private helpers

    private func createDirs() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: scriptsDir, withIntermediateDirectories: true, attributes: nil)
        try fm.createDirectory(at: venvDir, withIntermediateDirectories: true, attributes: nil)
        try fm.createDirectory(at: logsDir, withIntermediateDirectories: true, attributes: nil)
        try fm.createDirectory(at: runDir, withIntermediateDirectories: true,
                                               attributes: [FileAttributeKey.posixPermissions: 0o700])
    }

    private func copyDaemonScript() throws {
        let fm = FileManager.default

        guard let daemonSrc = Bundle.main.url(forResource: "iterm2_daemon", withExtension: "py") else {
            throw NSError(domain: "Contextify", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "daemon script missing in bundle"])
        }
        let daemonDst = scriptsDir.appendingPathComponent("iterm2_daemon.py")
        if fm.fileExists(atPath: daemonDst.path) {
            try? fm.removeItem(at: daemonDst)
        }
        try fm.copyItem(at: daemonSrc, to: daemonDst)
        log.info("Copied daemon script to \(daemonDst.path)")
    }

    private func writePlist() throws {
        let pythonBin = venvDir.appendingPathComponent("bin/python3")
        guard FileManager.default.isExecutableFile(atPath: pythonBin.path) else {
            throw NSError(domain: "Contextify", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "bundled Python venv missing or not executable"])
        }

        let pythonPath = pythonBin.path
        let scriptPath = scriptsDir.appendingPathComponent("iterm2_daemon.py").path
        let stdout = logsDir.appendingPathComponent("daemon.stdout.log").path
        let stderr = logsDir.appendingPathComponent("daemon.stderr.log").path

        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": [pythonPath, "-I", "-s", "-E", scriptPath],
            "RunAtLoad": true,
            "KeepAlive": ["Crashed": true, "SuccessfulExit": false],
            "StandardOutPath": stdout,
            "StandardErrorPath": stderr,
            "ThrottleInterval": 10,
            "LimitLoadToSessionType": "Aqua",
            "Umask": 0o077,
            "ProcessType": "Background"
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: plistURL)
    }

    private func bootstrapAndEnable() throws {
        let uid = getuid()
        let domain = "gui/\(uid)"

        let whoami = try? run("/usr/bin/id", ["-u"]).1.trimmingCharacters(in: .whitespacesAndNewlines)
        guard whoami == "\(uid)" else {
            throw NSError(domain: "Contextify", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "UID mismatch: expected \(uid) got \(whoami ?? "nil")"])
        }

        if (try? run("/bin/launchctl", ["print", "\(domain)/\(label)"]).0) == 0 {
            log.info("LaunchAgent already bootstrapped")
            return
        }

        try run("/bin/launchctl", ["bootstrap", domain, plistURL.path])
        try run("/bin/launchctl", ["enable", "\(domain)/\(label)"])
    }

    @discardableResult
    private func run(_ bin: String, _ args: [String]) throws -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        let out = Pipe(); let err = Pipe()
        p.standardOutput = out; p.standardError = err
        try p.run(); p.waitUntilExit()
        let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            throw NSError(domain: "Contextify", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "launchctl \(args.joined(separator: " ")) failed: \(e)\(o)"])
        }
        return (p.terminationStatus, o)
    }

    private func rotateLogsIfNeeded() {
        let fm = FileManager.default
        let maxBytes: UInt64 = 10 * 1024 * 1024
        for name in ["daemon.stdout.log", "daemon.stderr.log"] {
            let logURL = logsDir.appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: logURL.path),
                  let size = attrs[.size] as? UInt64,
                  size > maxBytes else {
                continue
            }
            let rotated = logsDir.appendingPathComponent("\(name).1")
            try? fm.removeItem(at: rotated)
            try? fm.moveItem(at: logURL, to: rotated)
        }
    }
}
