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
      case healthCheckCancelled  // Health check was cancelled externally (not a real failure)

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
        case .healthCheckCancelled:
          return "Health check was cancelled during startup. Retrying..."
        case .macOSVersionTooOld:
          return "Requires macOS 26 (Tahoe) or later."
        case .foundationModelsNotImported:
          return "FoundationModels framework not available."
        }
      }
    }
  }

  // Dynamic cache interval with exponential backoff
  private var cachedStatus: HealthStatus?
  private var previousStatus: HealthStatus?  // Track for change detection
  private var lastCheckTime: Date?
  private var cacheInterval: TimeInterval = 5  // Start with 5s, back off on repeated failures
  private var consecutiveFailures = 0
  private let maxCacheInterval: TimeInterval = 30

  private init() {}

  /// Update cache interval based on health check result (exponential backoff on failures)
  private func updateCacheInterval(for status: HealthStatus) {
    switch status {
    case .healthy:
      // Reset on success
      consecutiveFailures = 0
      cacheInterval = 5

    case .unavailable(let reason):
      // Don't penalize cancellation (not a real failure)
      if case .healthCheckCancelled = reason {
        // Keep current interval, don't increment failures
        log.debug("Health check cancelled - not treating as failure (interval stays \(Int(self.cacheInterval))s)")
      } else {
        // Real failure - increment and back off
        consecutiveFailures += 1
        // Exponential backoff: 5s → 10s → 20s → 30s (cap)
        cacheInterval = min(5 * pow(2.0, Double(consecutiveFailures - 1)), maxCacheInterval)
        log.info("Health check failed \(self.consecutiveFailures) consecutive times, cache interval now \(Int(self.cacheInterval))s")
      }
    }
  }

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
      // Log what specifically is unavailable with detailed reason
      let indicator: String
      let reasonDetail: String
      switch reason {
      case .appleIntelligenceNotEnabled:
        indicator = "Apple Intelligence not enabled in System Settings"
        reasonDetail = "appleIntelligenceNotEnabled"
      case .deviceNotEligible:
        indicator = "Device not eligible for Apple Intelligence"
        reasonDetail = "deviceNotEligible"
      case .modelNotReady:
        indicator = "Language model not ready"
        reasonDetail = "modelNotReady"
      case .guardrailSystemError(let details):
        indicator = "Guardrail system error (metadata.json missing)"
        reasonDetail = "guardrailSystemError(\(details))"
      case .sessionCreationFailed(let details):
        indicator = "Session creation failed"
        reasonDetail = "sessionCreationFailed(\(details))"
      case .testCallFailed(let details):
        indicator = "LLM test call failed"
        reasonDetail = "testCallFailed(\(details))"
      case .overloaded:
        indicator = "Apple Intelligence overloaded (health check timed out)"
        reasonDetail = "overloaded"
      case .healthCheckCancelled:
        indicator = "Health check cancelled (external cancellation, not a real failure)"
        reasonDetail = "healthCheckCancelled"
      case .macOSVersionTooOld:
        indicator = "macOS version too old (requires 26+)"
        reasonDetail = "macOSVersionTooOld"
      case .foundationModelsNotImported:
        indicator = "FoundationModels framework not available"
        reasonDetail = "foundationModelsNotImported"
      }
      log.error("❌ Apple Intelligence BECAME UNAVAILABLE - \(indicator, privacy: .public)")
      log.error("   Reason: .\(reasonDetail, privacy: .public)")
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
      updateCacheInterval(for: status)
      cachedStatus = status
      lastCheckTime = Date()
      return status

    case .unavailable(let reason):
      let status: HealthStatus
      switch reason {
      case .appleIntelligenceNotEnabled:
        log.error("LLM health check: FAILED - Apple Intelligence not enabled in System Settings")
        log.error("   Source: SystemLanguageModel.default.availability")
        log.error("   Reason: .unavailable(.appleIntelligenceNotEnabled)")
        status = .unavailable(.appleIntelligenceNotEnabled)
      case .deviceNotEligible:
        log.error("LLM health check: FAILED - Device not eligible for Apple Intelligence")
        log.error("   Source: SystemLanguageModel.default.availability")
        log.error("   Reason: .unavailable(.deviceNotEligible)")
        status = .unavailable(.deviceNotEligible)
      case .modelNotReady:
        log.warning("LLM health check: Language model not ready (may be downloading/initializing)")
        log.warning("   Source: SystemLanguageModel.default.availability")
        log.warning("   Reason: .unavailable(.modelNotReady)")
        status = .unavailable(.modelNotReady)
      @unknown default:
        log.error("LLM health check: FAILED - Unknown availability reason from Apple")
        log.error("   Source: SystemLanguageModel.default.availability")
        log.error("   Reason: .unavailable(\(String(describing: reason)))")
        status = .unavailable(.testCallFailed(details: "Unknown availability: \(reason)"))
      }
      logStatusChange(status)
      updateCacheInterval(for: status)
      cachedStatus = status
      lastCheckTime = Date()
      return status
    }
    #else
    let status: HealthStatus = .unavailable(.foundationModelsNotImported)
    logStatusChange(status)
    updateCacheInterval(for: status)
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
      log.error("LLM health check: TIMEOUT - Apple Intelligence took >10s to respond")
      log.error("   Error type: TimeoutError (internal timeout, NOT external cancellation)")
      return .unavailable(.overloaded)

    } catch is CancellationError {
      // Cancellation can happen when:
      // 1. The timeout fires and cancels the LLM task (but timeout would be caught first)
      // 2. External cancellation (e.g., app shutdown, project switch, parent task cancelled)
      log.info("LLM health check: CANCELLED - Task was cancelled by external cancellation")
      log.info("   Error type: CancellationError (parent task cancelled, likely app lifecycle event)")
      log.info("   This is NOT a real Apple Intelligence failure - treating as transient")
      return .unavailable(.healthCheckCancelled)

    } catch let error as LanguageModelSession.GenerationError {
      // Detect specific error patterns
      if case .guardrailViolation(let context) = error {
        // Check for the missing metadata.json system error
        let errorDesc = String(describing: context)
        if errorDesc.contains("metadata.json") && errorDesc.contains("No such file or directory") {
          log.error("LLM health check: FAILED - Guardrail system error (missing metadata.json)")
          log.error("   Error type: GenerationError.guardrailViolation (system file missing)")
          log.error("   Details: \(errorDesc, privacy: .public)")
          return .unavailable(.guardrailSystemError(
            details: "System file missing: metadata.json. This is a known macOS 26 beta issue."
          ))
        } else {
          log.error("LLM health check: FAILED - Guardrail violation: \(context.debugDescription)")
          log.error("   Error type: GenerationError.guardrailViolation (content filtered)")
          return .unavailable(.testCallFailed(details: "Guardrail violation: \(context.debugDescription)"))
        }
      } else if case .rateLimited = error {
        // Session is rate-limited - too many concurrent requests
        log.error("LLM health check: RATE LIMITED - Too many concurrent requests")
        log.error("   Error type: GenerationError.rateLimited (Apple Intelligence overloaded)")
        return .unavailable(.overloaded)
      } else {
        log.error("LLM health check: FAILED - Generation error: \(String(describing: error))")
        log.error("   Error type: GenerationError.\(String(describing: error).components(separatedBy: "(").first ?? "unknown")")
        return .unavailable(.testCallFailed(details: "Generation error: \(error.localizedDescription)"))
      }

    } catch {
      log.error("LLM health check: FAILED - Session creation failed: \(error.localizedDescription)")
      log.error("   Error type: \(type(of: error))")
      log.error("   Details: \(String(describing: error), privacy: .public)")
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
