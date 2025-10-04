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

    /// Install LaunchAgent if not already installed.
    /// Copies daemon script and venv, writes plist, bootstraps agent.
    func installIfNeeded() async throws {
        try createDirs()
        try copyDaemonAndVenvIfNeeded()
        try writePlist()
        try bootstrapAndEnable()
    }

    /// Kickstart the daemon to ensure it's running.
    func kickstart() async throws {
        try run("/bin/launchctl", ["kickstart", "gui/\(getuid())/\(label)"])
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

    private func copyDaemonAndVenvIfNeeded() throws {
        let fm = FileManager.default

        // Copy daemon script
        guard let daemonSrc = Bundle.main.url(forResource: "iterm2_daemon", withExtension: "py") else {
            throw NSError(domain: "Contextify", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "daemon script missing in bundle"])
        }
        let daemonDst = scriptsDir.appendingPathComponent("iterm2_daemon.py")
        if fm.fileExists(atPath: daemonDst.path) {
            try? fm.removeItem(at: daemonDst)
        }
        try fm.copyItem(at: daemonSrc, to: daemonDst)

        // Copy Python venv if bundled
        if let venvSrc = Bundle.main.url(forResource: "PythonVenv", withExtension: nil) {
            if fm.fileExists(atPath: venvDir.path) {
                try? fm.removeItem(at: venvDir)
            }
            try fm.copyItem(at: venvSrc, to: venvDir)
        }
    }

    private func writePlist() throws {
        // Determine Python executable path
        let venvPython = venvDir.appendingPathComponent("bin/python3")
        let pythonPath: String
        if FileManager.default.fileExists(atPath: venvPython.path) {
            pythonPath = venvPython.path
        } else {
            // Fallback to system python3
            pythonPath = "/usr/bin/python3"
        }

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
            "ThrottleInterval": 10
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: plistURL)
    }

    private func bootstrapAndEnable() throws {
        // Check if already bootstrapped
        let listResult = try? run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"])
        if listResult?.0 == 0 {
            log.info("LaunchAgent already bootstrapped")
            return
        }

        // Bootstrap and enable
        try run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistURL.path])
        try run("/bin/launchctl", ["enable", "gui/\(getuid())/\(label)"])
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
}
