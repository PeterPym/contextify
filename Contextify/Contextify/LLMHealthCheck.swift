import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Comprehensive LLM availability checker using "belt and suspenders" approach:
/// - Belt: Official SystemLanguageModel.default.availability API
/// - Suspenders: Actual test LLM call to detect runtime failures
@available(macOS 26, *)
actor LLMHealthCheck {
  static let shared = LLMHealthCheck()

  private let log = Logger(subsystem: "dev.contextify", category: "LLMHealthCheck")

  /// Internal error type for timeout detection
  private struct TimeoutError: Error {}

  enum HealthStatus: Sendable {
    case healthy
    case unavailable(Reason)

    enum Reason: Sendable {
      // Official API reasons
      case appleIntelligenceNotEnabled
      case deviceNotEligible
      case modelNotReady

      // Runtime failure reasons (discovered via test call)
      case guardrailSystemError(details: String)  // Missing metadata.json file issue
      case sessionCreationFailed(details: String)
      case testCallFailed(details: String)
      case overloaded  // LLM is overwhelmed and timing out

      // Environment reasons
      case macOSVersionTooOld
      case foundationModelsNotImported

      var userFacingMessage: String {
        switch self {
        case .appleIntelligenceNotEnabled:
          return "Apple Intelligence is not enabled. Please enable it in System Settings."
        case .deviceNotEligible:
          return "This Mac is not eligible for Apple Intelligence."
        case .modelNotReady:
          return "Language model is not ready. Please wait a few moments and try again."
        case .guardrailSystemError(let details):
          return "Apple Intelligence system error detected. Try: Settings → Apple Intelligence → Toggle off/on, then restart Mac.\n\nDetails: \(details)"
        case .sessionCreationFailed(let details):
          return "Failed to create LLM session: \(details)"
        case .testCallFailed(let details):
          return "LLM test call failed: \(details)"
        case .overloaded:
          return "Apple Intelligence is overloaded and not responding. Summarization queue may be too large. Wait for pending requests to complete."
        case .macOSVersionTooOld:
          return "Requires macOS 26 (Tahoe) or later."
        case .foundationModelsNotImported:
          return "FoundationModels framework not available."
        }
      }
    }
  }

  // Cache status for 30 seconds to avoid hammering the system
  private var cachedStatus: HealthStatus?
  private var previousStatus: HealthStatus?  // Track for change detection
  private var lastCheckTime: Date?
  private let cacheInterval: TimeInterval = 30

  private init() {}

  /// Log status change if it differs from previous status
  private func logStatusChange(_ newStatus: HealthStatus) {
    // Check if status changed
    let changed: Bool
    switch (previousStatus, newStatus) {
    case (.none, .healthy):
      // First check and healthy - don't log (normal startup)
      changed = false
    case (.none, .unavailable):
      // First check and unavailable - log it
      changed = true
    case (.some(.healthy), .healthy):
      // Still healthy - no change
      changed = false
    case (.some(.healthy), .unavailable):
      // Became unavailable - log it
      changed = true
    case (.some(.unavailable), .healthy):
      // Became available again - log it
      changed = true
    case (.some(.unavailable(let oldReason)), .unavailable(let newReason)):
      // Compare reasons - log if reason changed
      changed = String(describing: oldReason) != String(describing: newReason)
    }

    guard changed else {
      // Always update previousStatus even if not logging
      previousStatus = newStatus
      return
    }

    // Log the change
    switch (previousStatus, newStatus) {
    case (_, .healthy):
      // Only log "became available" if was previously unavailable
      if case .some(.unavailable) = previousStatus {
        log.warning("⚠️ Apple Intelligence RECOVERED - Now available")
      }
    case (_, .unavailable(let reason)):
      // Log what specifically is unavailable
      let indicator: String
      switch reason {
      case .appleIntelligenceNotEnabled:
        indicator = "Apple Intelligence not enabled in System Settings"
      case .deviceNotEligible:
        indicator = "Device not eligible for Apple Intelligence"
      case .modelNotReady:
        indicator = "Language model not ready"
      case .guardrailSystemError:
        indicator = "Guardrail system error (metadata.json missing)"
      case .sessionCreationFailed:
        indicator = "Session creation failed"
      case .testCallFailed:
        indicator = "LLM test call failed"
      case .overloaded:
        indicator = "Apple Intelligence overloaded (health check timed out)"
      case .macOSVersionTooOld:
        indicator = "macOS version too old (requires 26+)"
      case .foundationModelsNotImported:
        indicator = "FoundationModels framework not available"
      }
      log.error("❌ Apple Intelligence BECAME UNAVAILABLE - \(indicator, privacy: .public)")
    }

    previousStatus = newStatus
  }

  /// Check LLM health using both official API and actual test call
  /// - Parameter forceRefresh: Skip cache and perform fresh check
  /// - Returns: Current health status
  func checkHealth(forceRefresh: Bool = false) async -> HealthStatus {
    // Return cached status if recent
    if !forceRefresh,
       let cached = cachedStatus,
       let lastCheck = lastCheckTime,
       Date().timeIntervalSince(lastCheck) < cacheInterval {
      return cached
    }

    #if canImport(FoundationModels)
    // Belt: Official availability check
    let availability = SystemLanguageModel.default.availability

    switch availability {
    case .available:
      // Suspenders: Perform actual test call
      let status = await performTestCall()
      logStatusChange(status)
      cachedStatus = status
      lastCheckTime = Date()
      return status

    case .unavailable(let reason):
      let status: HealthStatus
      switch reason {
      case .appleIntelligenceNotEnabled:
        log.info("LLM health check: Apple Intelligence not enabled")
        status = .unavailable(.appleIntelligenceNotEnabled)
      case .deviceNotEligible:
        log.info("LLM health check: Device not eligible for Apple Intelligence")
        status = .unavailable(.deviceNotEligible)
      case .modelNotReady:
        log.info("LLM health check: Language model not ready")
        status = .unavailable(.modelNotReady)
      @unknown default:
        log.warning("LLM health check: Unknown availability reason: \(String(describing: reason))")
        status = .unavailable(.testCallFailed(details: "Unknown availability: \(reason)"))
      }
      logStatusChange(status)
      cachedStatus = status
      lastCheckTime = Date()
      return status
    }
    #else
    let status: HealthStatus = .unavailable(.foundationModelsNotImported)
    logStatusChange(status)
    cachedStatus = status
    lastCheckTime = Date()
    return status
    #endif
  }

  #if canImport(FoundationModels)
  /// Perform actual test LLM call to detect runtime failures
  private func performTestCall() async -> HealthStatus {
    do {
      // Create a minimal test session
      let session = LanguageModelSession(instructions: "You are a test assistant. Respond briefly.")

      let options = GenerationOptions(
        sampling: .greedy,
        temperature: 0,
        maximumResponseTokens: 10
      )

      log.debug("Performing LLM health check test call (with 10s timeout)")

      // Wrapper to make response Sendable for TaskGroup (unsafe but controlled)
      struct ResponseBox: @unchecked Sendable {
        let response: LanguageModelSession.Response<String>
      }

      // Race between LLM call and timeout
      let box = try await withThrowingTaskGroup(of: ResponseBox.self) { group in
        // Task 1: LLM call
        group.addTask {
          let r = try await session.respond(to: "Say 'OK'", options: options)
          return ResponseBox(response: r)
        }

        // Task 2: Timeout
        group.addTask {
          try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
          throw TimeoutError()
        }

        // Return first result
        guard let result = try await group.next() else {
          throw TimeoutError()
        }

        group.cancelAll()
        return result
      }

      log.info("LLM health check: PASSED (response: '\(box.response.content, privacy: .public)')")
      return .healthy

    } catch is TimeoutError {
      log.error("LLM health check: TIMEOUT - Apple Intelligence is not responding (overloaded)")
      return .unavailable(.overloaded)

    } catch is CancellationError {
      // Cancellation can happen when:
      // 1. The timeout fires and cancels the LLM task
      // 2. External cancellation (e.g., app shutdown, health check canceled)
      log.warning("LLM health check: CANCELLED - Task was cancelled (likely due to timeout or external cancellation)")
      return .unavailable(.overloaded)

    } catch let error as LanguageModelSession.GenerationError {
      // Detect specific error patterns
      if case .guardrailViolation(let context) = error {
        // Check for the missing metadata.json system error
        let errorDesc = String(describing: context)
        if errorDesc.contains("metadata.json") && errorDesc.contains("No such file or directory") {
          log.error("LLM health check: FAILED - Guardrail system error (missing metadata.json)")
          return .unavailable(.guardrailSystemError(
            details: "System file missing: metadata.json. This is a known macOS 26 beta issue."
          ))
        } else {
          log.error("LLM health check: FAILED - Guardrail violation: \(context.debugDescription)")
          return .unavailable(.testCallFailed(details: "Guardrail violation: \(context.debugDescription)"))
        }
      } else if case .rateLimited = error {
        // Session is rate-limited - too many concurrent requests
        log.error("LLM health check: RATE LIMITED - Session already processing a request")
        return .unavailable(.overloaded)
      } else {
        log.error("LLM health check: FAILED - Generation error: \(String(describing: error))")
        return .unavailable(.testCallFailed(details: "Generation error: \(error.localizedDescription)"))
      }

    } catch {
      log.error("LLM health check: FAILED - Session creation failed: \(error.localizedDescription)")
      return .unavailable(.sessionCreationFailed(details: error.localizedDescription))
    }
  }
  #endif

  /// Invalidate cached status to force fresh check on next call
  func invalidateCache() {
    cachedStatus = nil
    lastCheckTime = nil
  }

  /// Get the last known status without triggering a new check
  /// Returns cached status if available, otherwise nil (caller should use .checking as default)
  func getLastKnownStatus() -> HealthStatus? {
    return cachedStatus
  }
}
