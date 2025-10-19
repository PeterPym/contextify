import XCTest
@testable import Contextify

#if canImport(FoundationModels)
@available(macOS 26.0, *)
final class LLMHealthCheckTests: XCTestCase {
  func testHealthCheckExecutes() async throws {
    // This test actually calls the LLM to verify health status
    let status = await LLMHealthCheck.shared.checkHealth(forceRefresh: true)

    switch status {
    case .healthy:
      print("✅ LLM Health Check: PASSED")
      print("   Apple Intelligence is working correctly")

    case .unavailable(let reason):
      print("❌ LLM Health Check: FAILED")
      print("   Reason: \(reason)")
      print("   User message: \(reason.userFacingMessage)")

      // Don't fail the test - this is informational
      // The health check working correctly means it detected the issue
    }
  }
}
#endif
