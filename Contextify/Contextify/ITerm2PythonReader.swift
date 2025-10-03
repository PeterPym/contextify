import Foundation
import OSLog

/// Executes the bundled iTerm2 Python reader script and parses its JSON payload.
struct ITerm2PythonReader {
  private struct PythonResponse: Decodable {
    let success: Bool
    let content: String?
    let error: String?
    let details: String?
    let lineCount: Int?

    enum CodingKeys: String, CodingKey {
      case success
      case content
      case error
      case details
      case lineCount
    }
  }

  enum ReaderError: Error, CustomStringConvertible {
    case scriptNotFound
    case pythonExecutableMissing
    case executionFailed(String)
    case invalidOutput
    case jsonDecodeFailed(String)
    case pythonReported(String, details: String?)

    var description: String {
      switch self {
      case .scriptNotFound:
        return "Python script was not found in bundle or workspace."
      case .pythonExecutableMissing:
        return "Python 3 executable was not found on the system."
      case .executionFailed(let message):
        return "Failed to execute Python script: \(message)"
      case .invalidOutput:
        return "Python script returned data that was not valid UTF-8."
      case .jsonDecodeFailed(let message):
        return "Failed to decode Python JSON output: \(message)"
      case .pythonReported(let error, let details):
        if let details, !details.isEmpty {
          return "Python script reported error: \(error) (details: \(details))"
        }
        return "Python script reported error: \(error)"
      }
    }
  }

  private let log = Logger(subsystem: "dev.contextify", category: "ITerm2PythonReader")

  func readTerminalContent() async -> Result<String, ReaderError> {
    do {
      let scriptURL = try resolveScriptURL()
      let pythonURL = try resolvePythonExecutable()
      let rawOutput = try await runPython(pythonURL: pythonURL, scriptURL: scriptURL)

      guard let data = rawOutput.data(using: .utf8) else {
        return .failure(.invalidOutput)
      }

      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase

      let response: PythonResponse
      do {
        response = try decoder.decode(PythonResponse.self, from: data)
      } catch {
        log.error("Failed to decode JSON: \(error.localizedDescription, privacy: .public)")
        log.error("Payload: \(rawOutput, privacy: .public)")
        return .failure(.jsonDecodeFailed(error.localizedDescription))
      }

      guard response.success, let content = response.content else {
        return .failure(.pythonReported(response.error ?? "unknown_error", details: response.details))
      }

      log.info("Received iTerm2 content via Python API: \(content.count, privacy: .public) chars")
      return .success(content)
    } catch let readerError as ReaderError {
      return .failure(readerError)
    } catch {
      return .failure(.executionFailed(error.localizedDescription))
    }
  }

  // MARK: - Private helpers

  private func resolveScriptURL() throws -> URL {
    // Look for wrapper script first (handles venv activation)
    let candidatePaths: [URL] = {
      var urls: [URL] = []

      // Check bundle resources
      if let bundleURL = Bundle.main.url(forResource: "iterm2_reader_wrapper", withExtension: "sh") {
        urls.append(bundleURL)
      }

      // Check project structure (dev mode)
      let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      urls.append(cwd.appendingPathComponent("scripts/iterm2_reader_wrapper.sh"))

      // Also check for direct Python script
      if let bundleURL = Bundle.main.url(forResource: "iterm2_reader", withExtension: "py") {
        urls.append(bundleURL)
      }
      urls.append(cwd.appendingPathComponent("scripts/iterm2_reader.py"))

      return urls
    }()

    if let url = candidatePaths.first(where: { FileManager.default.isReadableFile(atPath: $0.path) }) {
      NSLog("🔥 Found iTerm2 reader script at: \(url.path)")
      return url
    }

    throw ReaderError.scriptNotFound
  }

  private func resolvePythonExecutable() throws -> URL {
    // For wrapper scripts (.sh), use bash
    // For direct Python scripts (.py), use python3
    return URL(fileURLWithPath: "/bin/bash")
  }

  private func runPython(pythonURL: URL, scriptURL: URL) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      let process = Process()
      process.executableURL = pythonURL
      process.arguments = [scriptURL.path]
      process.standardInput = nil

      let outputPipe = Pipe()
      process.standardOutput = outputPipe
      process.standardError = outputPipe

      do {
        try process.run()
      } catch {
        continuation.resume(throwing: ReaderError.executionFailed(error.localizedDescription))
        return
      }

      process.terminationHandler = { process in
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        outputPipe.fileHandleForReading.closeFile()

        if process.terminationStatus != 0 {
          let message = String(data: data, encoding: .utf8) ?? ""
          continuation.resume(throwing: ReaderError.executionFailed(message.isEmpty ? "Process exited with code \(process.terminationStatus)" : message))
          return
        }

        guard let output = String(data: data, encoding: .utf8) else {
          continuation.resume(throwing: ReaderError.invalidOutput)
          return
        }

        continuation.resume(returning: output)
      }
    }
  }
}
