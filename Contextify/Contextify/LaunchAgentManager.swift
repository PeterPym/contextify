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

        guard let daemonSrc = Bundle.main.url(forResource: "iterm2_daemon", withExtension: "py") else {
            throw NSError(domain: "Contextify", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "daemon script missing in bundle"])
        }
        let daemonDst = scriptsDir.appendingPathComponent("iterm2_daemon.py")
        if fm.fileExists(atPath: daemonDst.path) {
            try? fm.removeItem(at: daemonDst)
        }
        try fm.copyItem(at: daemonSrc, to: daemonDst)

        guard let venvSrc = Bundle.main.url(forResource: "PythonVenv", withExtension: nil) else {
            throw NSError(domain: "Contextify", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "bundled PythonVenv missing"])
        }
        if fm.fileExists(atPath: venvDir.path) {
            try? fm.removeItem(at: venvDir)
        }
        try fm.copyItem(at: venvSrc, to: venvDir)

        let pythonBin = venvDir.appendingPathComponent("bin/python3")
        guard fm.isExecutableFile(atPath: pythonBin.path) else {
            throw NSError(domain: "Contextify", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "venv python3 not executable at \(pythonBin.path)"])
        }
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
            "WorkingDirectory": appSupport.path
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
}
