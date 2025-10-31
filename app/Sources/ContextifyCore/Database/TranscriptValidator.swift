import Foundation
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "TranscriptValidator")

/// Validation error thrown when a transcript fails integrity checks
public enum TranscriptValidationError: Error, CustomStringConvertible {
  case cwdMismatch(expected: String, actual: String, file: String)
  case cannotExtractCwd(file: String)
  case invalidFormat(file: String, reason: String)
  case pathCanonicalizationFailed(path: String)

  public var description: String {
    switch self {
    case .cwdMismatch(let expected, let actual, let file):
      return "CWD mismatch: file=\(file) expected=\(expected) actual=\(actual)"
    case .cannotExtractCwd(let file):
      return "Cannot extract CWD from file: \(file)"
    case .invalidFormat(let file, let reason):
      return "Invalid transcript format: file=\(file) reason=\(reason)"
    case .pathCanonicalizationFailed(let path):
      return "Failed to canonicalize path: \(path)"
    }
  }
}

/// Result of transcript validation
public struct TranscriptValidationResult {
  public let isValid: Bool
  public let errors: [TranscriptValidationError]
  public let warnings: [String]

  public init(isValid: Bool, errors: [TranscriptValidationError] = [], warnings: [String] = []) {
    self.isValid = isValid
    self.errors = errors
    self.warnings = warnings
  }

  public static var valid: TranscriptValidationResult {
    TranscriptValidationResult(isValid: true)
  }

  public static func invalid(_ errors: [TranscriptValidationError]) -> TranscriptValidationResult {
    TranscriptValidationResult(isValid: false, errors: errors)
  }

  public static func invalid(_ error: TranscriptValidationError) -> TranscriptValidationResult {
    TranscriptValidationResult(isValid: false, errors: [error])
  }
}

/// Validates transcript files before hoovering to prevent bad data ingestion
public final class TranscriptValidator {

  public init() {}

  /// Validate a transcript file before hoovering
  /// - Parameters:
  ///   - fileURL: Path to the transcript file
  ///   - projectRootPath: Expected project root path (from database)
  ///   - provider: Provider type (e.g., "claude.code", "codex.cli")
  /// - Returns: Validation result with errors and warnings
  public func validate(
    fileURL: URL,
    projectRootPath: String,
    provider: String
  ) -> TranscriptValidationResult {
    var errors: [TranscriptValidationError] = []
    var warnings: [String] = []

    // Validation #1: CWD must match project root path (provider-specific)
    let cwdResult = validateCwdMatch(fileURL: fileURL, projectRootPath: projectRootPath, provider: provider)
    errors.append(contentsOf: cwdResult.errors)
    warnings.append(contentsOf: cwdResult.warnings)

    // Future validations can be added here:
    // - validateFileFormat() - check JSONL structure
    // - validateRequiredFields() - ensure critical fields present
    // - validateFileSize() - prevent processing huge files
    // - validateTimestamps() - check for reasonable date ranges
    // - validateSessionId() - ensure session ID format is valid

    let isValid = errors.isEmpty

    if !isValid {
      log.warning("❌ Transcript validation failed: \(fileURL.lastPathComponent) - \(errors.count) error(s)")
      for error in errors {
        log.warning("   • \(error.description)")
      }
    }

    if !warnings.isEmpty {
      log.info("⚠️ Transcript validation warnings: \(fileURL.lastPathComponent) - \(warnings.count) warning(s)")
      for warning in warnings {
        log.info("   • \(warning)")
      }
    }

    return TranscriptValidationResult(isValid: isValid, errors: errors, warnings: warnings)
  }

  // MARK: - Validation Rules

  /// Validate that transcript's CWD matches the expected project root path
  private func validateCwdMatch(
    fileURL: URL,
    projectRootPath: String,
    provider: String
  ) -> TranscriptValidationResult {

    // Only validate CWD for Claude Code (Codex uses different metadata structure)
    guard provider == "claude.code" else {
      return .valid
    }

    // Extract CWD from transcript file
    guard let extractedCwd = try? ProjectIdentity.extractCwdFromTranscriptForOrphaned(fileURL) else {
      // Cannot extract CWD - this may be a metadata-only transcript or old format
      // Don't fail validation, but log a warning
      return TranscriptValidationResult(
        isValid: true,
        warnings: ["Cannot extract CWD from transcript (may be metadata-only or old format)"]
      )
    }

    // Canonicalize both paths for comparison (resolve symlinks, normalize)
    guard let canonicalCwd = try? ProjectIdentity.canonicalizePath(extractedCwd) else {
      // CWD path doesn't exist or can't be canonicalized
      // This is expected for orphaned projects - allow but warn
      return TranscriptValidationResult(
        isValid: true,
        warnings: ["CWD path cannot be canonicalized (project may be deleted): \(extractedCwd)"]
      )
    }

    guard let canonicalProjectPath = try? ProjectIdentity.canonicalizePath(projectRootPath) else {
      // Project path doesn't exist - this shouldn't happen since we validated project earlier
      return .invalid(.pathCanonicalizationFailed(path: projectRootPath))
    }

    // Compare canonicalized paths
    if canonicalCwd != canonicalProjectPath {
      return .invalid(.cwdMismatch(
        expected: canonicalProjectPath,
        actual: canonicalCwd,
        file: fileURL.lastPathComponent
      ))
    }

    // CWD matches project - valid
    return .valid
  }

  // MARK: - Future Validation Rules (Placeholders)

  // Example future validators:
  /*
  private func validateFileFormat(fileURL: URL) -> TranscriptValidationResult {
    // Check that file is valid JSONL (each line is valid JSON)
    // Return invalid if malformed
  }

  private func validateRequiredFields(fileURL: URL, provider: String) -> TranscriptValidationResult {
    // Ensure critical fields exist in transcript (timestamp, type, etc.)
    // Provider-specific field requirements
  }

  private func validateFileSize(fileURL: URL, maxSizeBytes: Int64) -> TranscriptValidationResult {
    // Prevent processing extremely large files that could cause memory issues
    // Could be configurable per-project
  }

  private func validateTimestamps(fileURL: URL) -> TranscriptValidationResult {
    // Check that timestamps are in reasonable range (not year 1970 or 2100)
    // Detect timestamp corruption
  }

  private func validateSessionId(sessionId: String?, provider: String) -> TranscriptValidationResult {
    // Ensure session ID format is valid for the provider
    // Claude Code: UUID format
    // Codex: session-YYYYMMDD-HHMMSS format
  }
  */
}
