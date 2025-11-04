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
  private var lastCheckTime: Date?
  private let cacheInterval: TimeInterval = 30

  private init() {}

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
      cachedStatus = status
      lastCheckTime = Date()
      return status
    }
    #else
    let status: HealthStatus = .unavailable(.foundationModelsNotImported)
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

      log.debug("Performing LLM health check test call")

      // Simple test prompt that should always work if LLM is functional
      let response = try await session.respond(
        to: "Say 'OK'",
        options: options
      )

      log.info("LLM health check: PASSED (response: '\(response.content, privacy: .public)')")
      return .healthy

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
}
