import Foundation

// Swift 6 concurrency-safe references to standard streams
// These are effectively thread-safe for our purposes (single-threaded CLI output)
private nonisolated(unsafe) let standardOutput = stdout
private nonisolated(unsafe) let standardError = stderr

/// Runtime CLI arguments for benchmark and test modes.
/// These are ephemeral - never persisted to UserDefaults.
/// Thread-safe: immutable after initialization.
public struct LaunchArguments: Sendable {
  public static let shared = LaunchArguments()

  public let databasePath: String?
  public let transcriptPath: String?
  public let noSummaries: Bool
  public let quiet: Bool

  /// True when any benchmark-related flag is present
  public var isBenchmarkMode: Bool {
    databasePath != nil || transcriptPath != nil || noSummaries || quiet
  }

  private init() {
    let args = ProcessInfo.processInfo.arguments

    // Check for --help first
    if args.contains("--help") || args.contains("-h") {
      Self.printUsage()
      exit(0)
    }

    do {
      databasePath = try Self.parseStringArg("--database-path", from: args)
      transcriptPath = try Self.parseStringArg("--transcript-path", from: args)
      noSummaries = args.contains("--no-summaries")
      quiet = args.contains("--quiet")

      // Log benchmark mode activation
      if isBenchmarkMode {
        let log = CrossPlatformLogger(subsystem: "dev.contextify", category: "Benchmark")
        log.info("[BENCH] Benchmark mode active")
        if let dbPath = databasePath {
          log.info("[BENCH] --database-path: \(dbPath)")
        }
        if let txPath = transcriptPath {
          log.info("[BENCH] --transcript-path: \(txPath)")
        }
        if noSummaries {
          log.info("[BENCH] --no-summaries: enabled")
        }
        if quiet {
          log.info("[BENCH] --quiet: enabled")
        }
      }
    } catch let error as ArgumentError {
      fputs("Error: \(error.message)\n", standardError)
      Self.printUsage(to: standardError)
      exit(64)  // EX_USAGE
    } catch {
      fputs("Error: \(error.localizedDescription)\n", standardError)
      exit(1)
    }
  }

  /// For unit testing: parse from explicit arguments
  public init(parsing args: [String]) throws {
    databasePath = try Self.parseStringArg("--database-path", from: args)
    transcriptPath = try Self.parseStringArg("--transcript-path", from: args)
    noSummaries = args.contains("--no-summaries")
    quiet = args.contains("--quiet")
  }

  private static func parseStringArg(_ flag: String, from args: [String]) throws -> String? {
    // Use lastIndex for "last-one-wins" behavior with duplicate flags
    guard let idx = args.lastIndex(of: flag) else {
      return nil
    }

    // Flag present but no value after it
    guard idx + 1 < args.count else {
      throw ArgumentError(message: "\(flag) requires a value")
    }

    let value = args[idx + 1]

    // Value looks like another flag (reject both --flag and -f forms)
    if value.hasPrefix("-") {
      throw ArgumentError(message: "\(flag) requires a value, got '\(value)'")
    }

    // Expand ~ and resolve relative paths using URL-based resolution
    let expanded = (value as NSString).expandingTildeInPath
    let url: URL
    if expanded.hasPrefix("/") {
      url = URL(fileURLWithPath: expanded)
    } else {
      let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      url = cwd.appendingPathComponent(expanded)
    }

    return url.standardizedFileURL.path
  }

  /// Print usage to specified stream (stdout for --help, stderr for errors)
  private static func printUsage(to stream: UnsafeMutablePointer<FILE> = standardOutput) {
    let usage = """
    Contextify Benchmark Mode Options:
      --database-path <path>    Use temporary database (must not exist)
      --transcript-path <path>  Use snapshot transcript directory
      --no-summaries            Disable LLM summary generation
      --quiet                   Run without showing main window
      --help, -h                Show this message

    Examples:
      Contextify --database-path /tmp/bench.db --no-summaries
      Contextify --transcript-path ~/benchmarks/corpus-v1 --quiet

    Note: Duplicate flags use last-one-wins behavior.
    Note: --transcript-path and --database-path are disabled in App Store builds.

    """
    fputs(usage, stream)
  }
}

private struct ArgumentError: Error {
  let message: String
}
