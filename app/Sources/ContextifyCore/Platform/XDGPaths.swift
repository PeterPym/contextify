// SPDX-License-Identifier: MIT
// XDGPaths.swift - XDG Base Directory Specification compliance for Linux

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// XDG Base Directory Specification paths for Linux.
/// See: https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
///
/// Precedence for database path (standard Linux convention):
/// 1. `--db` flag - CLI argument (highest priority)
/// 2. `CONTEXTIFY_DB_PATH` - Environment variable
/// 3. Config file `database.path` - User configuration (future)
/// 4. `XDG_DATA_HOME/contextify/contextify.db` - XDG compliant default
/// 5. `~/.local/share/contextify/contextify.db` - Fallback default (Linux)
/// 6. `~/Library/Application Support/Contextify/contextify.db` - Fallback default (macOS)
public struct XDGPaths {

  // MARK: - Path Utilities

  /// Expand tilde (~) in paths. Use this for user-provided paths (--db, env vars).
  /// Returns the original path if no tilde expansion is needed.
  public static func expandTilde(_ path: String) -> String {
    return (path as NSString).expandingTildeInPath
  }

  // MARK: - Path Resolution

  /// Validates XDG path is absolute. Returns fallback with warning if relative.
  private static func validatedXDGPath(_ envVar: String, fallback: URL) -> URL {
    guard let xdg = ProcessInfo.processInfo.environment[envVar] else {
      return fallback
    }
    // XDG spec requires absolute paths
    guard xdg.hasPrefix("/") else {
      writeStderr("Warning: \(envVar)='\(xdg)' is not absolute, using default\n")
      return fallback
    }
    // Avoid double-appending "contextify" if user already included it
    let xdgURL = URL(fileURLWithPath: xdg)
    if xdgURL.lastPathComponent == "contextify" {
      return xdgURL
    }
    return xdgURL.appendingPathComponent("contextify")
  }

  /// XDG_DATA_HOME/contextify/ - where the database lives
  /// Default: ~/.local/share/contextify/ (Linux) or ~/Library/Application Support/Contextify/ (macOS)
  public static var dataHome: URL {
    #if os(macOS)
    // macOS: use standard Application Support location
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Contextify")
    #else
    return validatedXDGPath("XDG_DATA_HOME",
      fallback: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/contextify"))
    #endif
  }

  /// XDG_CONFIG_HOME/contextify/ - where config.toml lives
  /// Default: ~/.config/contextify/
  public static var configHome: URL {
    validatedXDGPath("XDG_CONFIG_HOME",
      fallback: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/contextify"))
  }

  /// Default database path with precedence:
  /// CONTEXTIFY_DB_PATH env var > XDG_DATA_HOME/contextify/contextify.db (or macOS default)
  public static var databasePath: URL {
    // CONTEXTIFY_DB_PATH env var takes precedence (power user override)
    if let dbPath = ProcessInfo.processInfo.environment["CONTEXTIFY_DB_PATH"] {
      // Expand tilde first
      let expanded = expandTilde(dbPath)
      // Must be absolute after expansion
      guard expanded.hasPrefix("/") else {
        writeStderr("Warning: CONTEXTIFY_DB_PATH='\(dbPath)' is not an absolute path, using default\n")
        return dataHome.appendingPathComponent("contextify.db")
      }
      return URL(fileURLWithPath: expanded)
    }
    return dataHome.appendingPathComponent("contextify.db")
  }

  /// Config file path
  public static var configPath: URL {
    configHome.appendingPathComponent("config.toml")
  }

  // MARK: - Legacy Path Detection

  /// Known legacy database locations to check for migration
  public static var legacyDatabasePaths: [URL] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return [
      // Hypothetical old path (if we had one before XDG)
      home.appendingPathComponent(".contextify/contextify.db"),
      // macOS path (if somehow present on Linux)
      home.appendingPathComponent("Library/Application Support/Contextify/contextify.db"),
    ]
  }

  /// Find first existing legacy database
  public static func findLegacyDatabase() -> URL? {
    for path in legacyDatabasePaths {
      if FileManager.default.fileExists(atPath: path.path) {
        return path
      }
    }
    return nil
  }

  // MARK: - Secure Directory/File Management

  /// Ensure directory exists with secure permissions (0700).
  /// Tightens existing insecure perms; warns but continues on chmod failure.
  ///
  /// - Parameter url: Directory to ensure exists
  /// - Returns: true if directory is usable, false if creation failed
  @discardableResult
  public static func ensureSecureDirectory(_ url: URL) -> Bool {
    let fm = FileManager.default
    var isDir: ObjCBool = false

    do {
      if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
        if isDir.boolValue {
          // Check current permissions and tighten if needed
          let attrs = try fm.attributesOfItem(atPath: url.path)
          if let perms = attrs[.posixPermissions] as? Int, perms & 0o077 != 0 {
            // Directory is world/group accessible - try to tighten silently
            do {
              try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
              // Success - no need to warn the user
            } catch {
              // chmod failed (NFS, weird mount, corporate lockdown) - only warn on failure
              writeStderr("Warning: Could not secure permissions on \(url.path): \(error.localizedDescription)\n")
              writeStderr("Warning: Directory may be accessible to other users\n")
              // Continue anyway - don't block the user
            }
          }
          return true
        } else {
          writeStderr("Error: \(url.path) exists but is not a directory\n")
          return false
        }
      } else {
        // Create directory with secure permissions
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        // Try to set secure permissions, but don't block on failure
        do {
          try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
          writeStderr("Warning: Could not set permissions on \(url.path): \(error.localizedDescription)\n")
          writeStderr("Warning: Directory may be accessible to other users\n")
          // Continue anyway - directory was created
        }
        return true
      }
    } catch {
      writeStderr("Error: Could not create \(url.path): \(error.localizedDescription)\n")
      return false
    }
  }

  /// Set secure file permissions (0600), tightening if needed.
  /// Warns but continues on chmod failure.
  public static func setSecureFilePermissions(_ url: URL) {
    let fm = FileManager.default
    do {
      // Silently secure file permissions - only warn on failure
      try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    } catch {
      writeStderr("Warning: Could not secure permissions on \(url.path): \(error.localizedDescription)\n")
      writeStderr("Warning: File may be accessible to other users\n")
      // Continue - file was written, just not with ideal perms
    }
  }

  /// Set secure permissions on database file and all sidecars (WAL, SHM, journal).
  /// SQLite sidecars can contain sensitive content and may be created with default perms.
  public static func setSecureDatabasePermissions(_ dbURL: URL) {
    let sidecars = ["-wal", "-shm", "-journal"]
    let basePath = dbURL.path

    // Secure the main database file
    if FileManager.default.fileExists(atPath: basePath) {
      setSecureFilePermissions(dbURL)
    }

    // Secure any sidecars that exist
    for suffix in sidecars {
      let sidecarPath = basePath + suffix
      if FileManager.default.fileExists(atPath: sidecarPath) {
        setSecureFilePermissions(URL(fileURLWithPath: sidecarPath))
      }
    }
  }

  // MARK: - TTY Detection

  /// Check if stdin is a TTY (for interactive prompts)
  public static func isStdinTTY() -> Bool {
    return isatty(STDIN_FILENO) != 0
  }

  /// Check if stderr is a TTY (for warnings/prompts that humans should see)
  public static func isStderrTTY() -> Bool {
    return isatty(STDERR_FILENO) != 0
  }

  /// Check if running interactively (both stdin and stderr are TTYs)
  /// Use this for prompts that require user input
  public static func isInteractive() -> Bool {
    return isStdinTTY() && isStderrTTY()
  }

  // MARK: - Process Helpers

  /// Find the path to `env` binary (checks /usr/bin/env, /bin/env for portability)
  /// Returns the first path that exists, or /usr/bin/env as fallback
  public static var envPath: String {
    for path in ["/usr/bin/env", "/bin/env"] {
      if FileManager.default.fileExists(atPath: path) {
        return path
      }
    }
    return "/usr/bin/env"  // Fallback - will fail clearly if missing
  }

  // MARK: - Output Helpers

  /// Write to stderr (for warnings and errors)
  public static func writeStderr(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
  }
}

// MARK: - Exit Codes

/// Standard exit codes for CLI commands
public enum CLIExitCode: Int32 {
  case success = 0   // Operation completed successfully
  case error = 1     // Something failed
  case noop = 2      // Nothing to do (useful for scripts)
}

/// Protocol for commands that want to report structured exit codes
public protocol ExitCodeReporting {
  var exitCode: CLIExitCode { get }
}
