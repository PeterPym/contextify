import Foundation
import OSLog
import CryptoKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// LLM client for generating transcript metadata
actor TranscriptMetadataLLM {
  static let shared = TranscriptMetadataLLM()

  private let log = Logger(subsystem: "dev.contextify.metadata", category: "TranscriptMetadataLLM")
  let modelSignature = "SystemLanguageModel@local"

  private init() {}

  enum LLMError: Error {
    case unavailable
    case unexpectedEnvironment
    case decodingFailure(String)
    case contextWindowExceeded(tokens: Int, limit: Int)
    case guardrailViolation(String)
  }

  // MARK: - Session & single-flight
  // Store as Any? to avoid availability issues with stored properties
  private var _sharedSessionStorage: Any?
  private var initializing = false
  private var inFlight = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  // Overhead calibration cache
  private var calibratedOverhead: Int?
  private var calibrating = false
  private let promptVersion = 2  // Increment when instructions change

  // Token estimation auto-tuning
  private var observedRatios: [Double] = []  // Rolling window of chars/token ratios
  private let maxObservations = 20

  #if canImport(FoundationModels)
  @available(macOS 26, *)
  private var sharedSession: LanguageModelSession? {
    get { _sharedSessionStorage as? LanguageModelSession }
    set { _sharedSessionStorage = newValue }
  }

  @available(macOS 26, *)
  private func acquire() async {
    if !inFlight {
      inFlight = true
      return
    }
    await withCheckedContinuation { (cc: CheckedContinuation<Void, Never>) in
      waiters.append(cc)
    }
    inFlight = true
  }

  @available(macOS 26, *)
  private func release() {
    inFlight = false
    if !waiters.isEmpty {
      let cc = waiters.removeFirst()
      cc.resume()
    }
  }

  @available(macOS 26, *)
  private func getOrCreateSession() async throws -> LanguageModelSession {
    if let s = sharedSession { return s }
    if initializing {
      try await Task.sleep(nanoseconds: 100_000_000) // 100ms
      return try await getOrCreateSession()
    }
    initializing = true
    defer { initializing = false }

    // static instructions → safe to reuse session
    let s = LanguageModelSession(instructions: Prompts.sharedInstructions())
    sharedSession = s
    log.info("Created shared TranscriptMetadata LanguageModelSession")
    return s
  }
  #endif

  // MARK: - Pre-flight Context Validation

  #if canImport(FoundationModels)
  @available(macOS 26, *)
  private func ensureContextFits(
    context: String,
    sampledCount: Int,
    totalCount: Int,
    session: LanguageModelSession,
    maxAttempts: Int = 5
  ) async throws -> String {
    var currentContext = context
    var currentSampledCount = sampledCount
    var attempt = 0

    while attempt < maxAttempts {
      let contextWithInfo = """
      CONTEXT: This excerpt shows \(currentSampledCount) of \(totalCount) messages. First 10 and last 10 are always included; the middle is selected for importance.

      \(currentContext)
      """

      // Pre-flight with minimal output tokens
      let preflightOptions = GenerationOptions(
        sampling: .greedy,
        temperature: 0,
        maximumResponseTokens: 1
      )

      do {
        // Cheap pre-flight check
        _ = try await session.respond(
          to: contextWithInfo,
          generating: GuidedTranscriptMetadata.self,
          includeSchemaInPrompt: true,
          options: preflightOptions
        )
        // Success! Context fits
        log.debug("Pre-flight passed with \(currentContext.count) chars, \(currentSampledCount) messages")
        return currentContext
      } catch let error as LanguageModelSession.GenerationError {
        guard case .exceededContextWindowSize(let errorContext) = error else {
          throw error // Other errors should propagate
        }

        // Extract token count from error
        let desc = errorContext.debugDescription
        let tokens = Self.parseTokenCount(from: desc) ?? 0

        // Record token usage for auto-tuning
        if tokens > 0 {
          recordTokenUsage(chars: currentContext.count, tokens: tokens)
        }

        attempt += 1
        log.warning("Pre-flight exceeded context: \(tokens)/4096 tokens (attempt \(attempt)/\(maxAttempts))")

        if attempt >= maxAttempts {
          throw LLMError.contextWindowExceeded(tokens: tokens, limit: 4096)
        }

        // Apply adaptive compression after 2 failed attempts
        if attempt >= 2 {
          let compressionLevel = attempt - 1  // Level 1 at attempt 2, level 2 at attempt 3, etc.
          log.debug("Applying adaptive compression (level \(compressionLevel))")
          currentContext = applyAdaptiveCompression(currentContext, level: compressionLevel)
        } else {
          // First 2 attempts: binary shrink by removing middle lines
          let shrinkResult = shrinkContextByHalf(currentContext)
          currentContext = shrinkResult.context
          currentSampledCount = shrinkResult.estimatedCount
        }

        log.debug("Shrunk context to \(currentContext.count) chars, ~\(currentSampledCount) messages")
      }
    }

    throw LLMError.contextWindowExceeded(tokens: 0, limit: 4096)
  }

  private func shrinkContextByHalf(_ context: String) -> (context: String, estimatedCount: Int) {
    let lines = context.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count > 20 else {
      return (context, lines.count)
    }

    // Keep first 10 and last 10 lines, remove middle
    let head = lines.prefix(10)
    let tail = lines.suffix(10)
    let shrunk = (head + tail).joined(separator: "\n")

    return (shrunk, 20)
  }

  /// Adaptive compressor: aggressive compression techniques after basic shrinking fails
  private func applyAdaptiveCompression(_ context: String, level: Int) -> String {
    var compressed = context

    // Level 1: Strip timestamps ("+5m23s" → "")
    if level >= 1 {
      compressed = stripTimestamps(compressed)
    }

    // Level 2: Collapse repeated adjacent lines
    if level >= 2 {
      compressed = collapseRepeatedLines(compressed)
    }

    // Level 3: Drop assistant lines in middle, keep user lines
    if level >= 3 {
      compressed = preferUserLines(compressed)
    }

    return compressed
  }

  private func stripTimestamps(_ context: String) -> String {
    // Remove time deltas like "+5m23s: " or "+2h: "
    let pattern = #"\+[\dhms]+:\s"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      return context
    }
    let range = NSRange(context.startIndex..., in: context)
    return regex.stringByReplacingMatches(in: context, options: [], range: range, withTemplate: "")
  }

  private func collapseRepeatedLines(_ context: String) -> String {
    let lines = context.split(separator: "\n", omittingEmptySubsequences: false)
    var result: [String] = []
    var lastLine: String?

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed != lastLine {
        result.append(String(line))
        lastLine = trimmed
      }
      // Skip repeated lines
    }

    return result.joined(separator: "\n")
  }

  private func preferUserLines(_ context: String) -> String {
    let lines = context.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count > 20 else { return context }

    // Keep first 10, last 10, and user lines from middle
    let head = lines.prefix(10)
    let tail = lines.suffix(10)
    let middle = lines.dropFirst(10).dropLast(10)

    let userMiddle = middle.filter { $0.starts(with: "U ") || $0.starts(with: "U+") }

    return (head + userMiddle + tail).joined(separator: "\n")
  }
  #endif

  // MARK: - Token Budget Calculation & Calibration

  #if canImport(FoundationModels)
  @available(macOS 26, *)
  func calibrateOverheadIfNeeded() async throws {
    guard calibratedOverhead == nil, !calibrating else { return }
    calibrating = true
    defer { calibrating = false }

    log.info("Calibrating prompt overhead for v\(self.promptVersion)...")

    let session = try await getOrCreateSession()

    // Binary search to find max filler tokens before exceeding context
    var low = 0
    var high = 4096 - MetadataBudgets.outputTokens // Max possible
    var maxFits = 0

    while low <= high {
      let mid = (low + high) / 2
      let filler = String(repeating: "x ", count: mid)  // ~2 chars per token

      let options = GenerationOptions(
        sampling: .greedy,
        temperature: 0,
        maximumResponseTokens: 1
      )

      do {
        _ = try await session.respond(
          to: filler,
          generating: GuidedTranscriptMetadata.self,
          includeSchemaInPrompt: true,
          options: options
        )
        // Fits! Try more
        maxFits = mid
        low = mid + 1
      } catch let error as LanguageModelSession.GenerationError {
        if case .exceededContextWindowSize = error {
          // Too much, try less
          high = mid - 1
        } else {
          // Other error (e.g., decoding failure with dummy data), ignore
          break
        }
      }
    }

    // Overhead = total - output - what fit
    let overhead = 4096 - MetadataBudgets.outputTokens - maxFits
    calibratedOverhead = overhead

    log.info("Calibration complete: overhead=\(overhead) tokens (max content tokens: \(maxFits))")
  }

  func getOverhead() -> Int {
    return calibratedOverhead ?? MetadataBudgets.promptOverhead
  }

  /// Records observed token usage for auto-tuning the estimator
  func recordTokenUsage(chars: Int, tokens: Int) {
    guard tokens > 0, chars > 0 else { return }

    let ratio = Double(chars) / Double(tokens)
    observedRatios.append(ratio)

    // Keep only last N observations
    if observedRatios.count > maxObservations {
      observedRatios.removeFirst()
    }

    // Update global estimator every 5 observations
    if observedRatios.count % 5 == 0 {
      let avgRatio = observedRatios.reduce(0, +) / Double(observedRatios.count)
      let tuned = max(2.0, min(4.0, avgRatio))
      MetadataBudgets.charsPerToken = tuned
      log.debug("Token estimator stats: avg ratio=\(String(format: "%.2f", avgRatio)) chars/token (\(self.observedRatios.count) samples), tuned to \(String(format: "%.2f", tuned))")
    }
  }

  /// Gets the auto-tuned chars/token ratio, defaults to 2.5
  func getTunedCharsPerToken() -> Double {
    guard observedRatios.count >= 3 else {
      return 2.5  // Default until we have enough data
    }

    let avgRatio = observedRatios.reduce(0, +) / Double(observedRatios.count)
    // Clamp to reasonable range [2.0, 4.0]
    return max(2.0, min(4.0, avgRatio))
  }
  #endif

#if canImport(FoundationModels)
  @available(macOS 26, *)
  func calculateAvailableContextTokens(sampledCount: Int, totalCount: Int) async -> Int {
    // Use unified budget calculation with calibrated overhead
    let overhead = getOverhead()
    let availableForContext = MetadataBudgets.calculateBudget(overhead: overhead)

    log.debug("Token budget: overhead=\(overhead), output=\(MetadataBudgets.outputTokens), safety=\(MetadataBudgets.safetyMargin), available=\(availableForContext)")

    return max(0, availableForContext)
  }
#endif

  // MARK: - Single Pass Generation
  #if canImport(FoundationModels)
  @available(macOS 26, *)
  func singlePass(
    context: String,
    sampledCount: Int,
    totalCount: Int,
    strategy: String = "unknown"
  ) async throws -> GuidedTranscriptMetadata {
    let correlationId = UUID().uuidString.prefix(8)
    let availability = SystemLanguageModel.default.availability
    guard case .available = availability else {
      log.warning("SystemLanguageModel unavailable")
      throw LLMError.unavailable
    }

    let session = try await getOrCreateSession()

    // Pre-flight check and shrink if needed
    let fittedContext = try await ensureContextFits(
      context: context,
      sampledCount: sampledCount,
      totalCount: totalCount,
      session: session
    )

    // sampled/total move into input (not instructions)
    let contextWithInfo = """
    CONTEXT: This excerpt shows \(sampledCount) of \(totalCount) messages. First 10 and last 10 are always included; the middle is selected for importance.

    \(fittedContext)
    """

    // Compute prompt SHA256 for observability
    let promptData = Data(contextWithInfo.utf8)
    let promptHash = SHA256.hash(data: promptData)
    let promptSHA = promptHash.compactMap { String(format: "%02x", $0) }.joined().prefix(16)

    let options = GenerationOptions(
      sampling: .greedy,
      temperature: 0,
      maximumResponseTokens: 150
    )

    log.info("[\(correlationId, privacy: .public)] strategy=\(strategy, privacy: .public) msgs=\(sampledCount)/\(totalCount) chars=\(contextWithInfo.count) promptSHA=\(promptSHA, privacy: .public)")

    // strict single-flight: exactly one respond() in flight
    await acquire()
    defer { release() }

    do {
      let response = try await session.respond(
        to: contextWithInfo,
        generating: GuidedTranscriptMetadata.self,
        includeSchemaInPrompt: true,
        options: options
      )
      log.info("LLM returned metadata - title: '\(response.content.title, privacy: .public)'")
      return response.content
    } catch let error as LanguageModelSession.GenerationError {
      // Map FoundationModels errors to specific LLMError types
      switch error {
      case .exceededContextWindowSize(let context):
        // Parse token counts from error message
        let desc = context.debugDescription
        let tokens = Self.parseTokenCount(from: desc) ?? 0

        // Record for auto-tuning (even on failure, gives us data)
        if tokens > 0 {
          recordTokenUsage(chars: contextWithInfo.count, tokens: tokens)
        }

        log.error("Context window exceeded: \(tokens)/4096 tokens")
        throw LLMError.contextWindowExceeded(tokens: tokens, limit: 4096)

      case .guardrailViolation(let context):
        log.error("Guardrail violation: \(context.debugDescription, privacy: .public)")
        throw LLMError.guardrailViolation(context.debugDescription)

      case .decodingFailure(let context):
        log.error("Decoding failure: \(context.debugDescription, privacy: .public)")
        throw LLMError.decodingFailure(context.debugDescription)

      case .assetsUnavailable(let context):
        log.error("Assets unavailable: \(context.debugDescription, privacy: .public)")
        throw LLMError.decodingFailure("Assets unavailable: \(context.debugDescription)")

      case .unsupportedGuide(let context):
        log.error("Unsupported guide: \(context.debugDescription, privacy: .public)")
        throw LLMError.decodingFailure("Unsupported guide: \(context.debugDescription)")

      case .unsupportedLanguageOrLocale(let context):
        log.error("Unsupported language/locale: \(context.debugDescription, privacy: .public)")
        throw LLMError.decodingFailure("Unsupported language/locale: \(context.debugDescription)")

      case .rateLimited(let context):
        log.error("Rate limited: \(context.debugDescription, privacy: .public)")
        throw LLMError.decodingFailure("Rate limited: \(context.debugDescription)")

      case .concurrentRequests(let context):
        log.error("Concurrent requests: \(context.debugDescription, privacy: .public)")
        throw LLMError.decodingFailure("Concurrent requests: \(context.debugDescription)")

      case .refusal(_, let reasonCategory):
        log.error("Refusal: \(String(describing: reasonCategory), privacy: .public)")
        throw LLMError.guardrailViolation("Refusal: \(reasonCategory)")

      @unknown default:
        log.error("LLM error: \(String(describing: error), privacy: .public)")
        throw LLMError.decodingFailure(String(describing: error))
      }
    }
  }
  #else
  @available(macOS 26, *)
  func singlePass(
    context: String,
    sampledCount: Int,
    totalCount: Int
  ) async throws -> Never {
    log.error("FoundationModels not available (macOS < 26)")
    throw LLMError.unexpectedEnvironment
  }
  #endif

  // MARK: - Helper Functions

  /// Parses token count from error message like "Content contains 5495 tokens, which exceeds..."
  private static func parseTokenCount(from description: String) -> Int? {
    let pattern = #"Content contains (\d+) tokens"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
          let range = Range(match.range(at: 1), in: description) else {
      return nil
    }
    return Int(description[range])
  }
}

// MARK: - Guided Schema
#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable(description: "Transcript metadata")
struct GuidedTranscriptMetadata: Sendable {
  @Guide(description: "Title ≤60 chars; imperative or concise noun phrase.")
  var title: String

  @Guide(description: "Description ≤200 chars; 2–3 activities in chronological order; past tense.")
  var description: String

  @Guide(description: "2–5 topics from the fixed list; lowercase hyphenated.")
  var topics: [String]

  @Guide(description: "Confidence 0.0–1.0", .range(0...1))
  var confidence: Double

  @Guide(description: "True if any referenced filename/module/API not in messages.")
  var mayContainHallucinations: Bool
}
#endif

// MARK: - Prompts
enum Prompts: Sendable {
  /// Static instructions so the session can be reused safely
  nonisolated static func sharedInstructions() -> String {
    """
    Analyze developer AI session. Output JSON only:
    • Title ≤60 chars: imperative/noun phrase for main activity
    • Description ≤200 chars: 2-3 key activities, past tense, chronological
    • Topics 2-5: feature-work, bug-fix, refactoring, testing, documentation, code-review, performance, security, architecture, deployment, general
    • Confidence 0.0-1.0: clarity/specificity
    • mayContainHallucinations: true if any file/module/API not in messages
    Use ONLY details explicitly present. Do NOT invent names/tools.
    """
  }
}

// MARK: - Heuristics Fallback
enum HeuristicMetadata: Sendable {
  nonisolated static func generate(exchanges: [Exchange]) -> TranscriptMetadata {
    let title = exchanges.count < 3 ? "Brief Session" : "Developer Chat"
    let description = generateDescription(exchanges: exchanges)
    let topics = ["general"]

    return TranscriptMetadata(
      version: 1,
      title: title,
      description: description,
      topics: topics,
      confidence: 0.3,
      mayContainHallucinations: false,
      needsReview: true,
      generatedAt: Date(),
      model: "heuristic",
      promptVersion: 0,
      generatorVersion: 1,
      transcriptSHA256: "",
      messageCount: exchanges.count,
      strategy: "heuristic",
      llmCalls: 0,
      latencyMs: 0
    )
  }

  nonisolated private static func generateDescription(exchanges: [Exchange]) -> String {
    guard !exchanges.isEmpty else {
      return "Empty transcript."
    }

    if exchanges.count < 3 {
      return "Very short conversation."
    }

    // Extract first and last user messages
    let userMessages = exchanges.filter { $0.role == .user }
    let firstUser = userMessages.first?.text.prefix(50) ?? ""
    let lastUser = userMessages.last?.text.prefix(50) ?? ""

    if firstUser.isEmpty && lastUser.isEmpty {
      return "Conversation with \(exchanges.count) messages."
    }

    if !firstUser.isEmpty && !lastUser.isEmpty {
      return "Started with: \(firstUser)... Ended with: \(lastUser)..."
    }

    return "Conversation with \(exchanges.count) messages."
  }
}
