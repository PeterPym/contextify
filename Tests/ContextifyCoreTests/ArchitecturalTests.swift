import XCTest
import SwiftSyntax
import SwiftParser
@testable import ContextifyCore

/// Architectural boundary tests to enforce layer discipline
/// Prevents UI layer from directly importing database dependencies
final class ArchitecturalTests: XCTestCase {

  // MARK: - Layer Boundary Tests

  func testUILayerDoesNotImportGRDB() throws {
    // Find the UI layer directory (Contextify/Contextify/)
    let uiDirectory = try findUIDirectory()

    // Get all Swift files in UI directory
    let uiFiles = try FileManager.default
      .contentsOfDirectory(at: uiDirectory, includingPropertiesForKeys: nil, options: [])
      .filter { $0.pathExtension == "swift" }

    XCTAssertGreaterThan(uiFiles.count, 0, "Should find Swift files in UI directory")

    var violations: [(file: String, imports: [String])] = []

    for file in uiFiles {
      let source = try String(contentsOf: file)
      let tree = Parser.parse(source: source)

      let visitor = ImportVisitor(viewMode: .sourceAccurate)
      visitor.walk(tree)

      let grdbImports = visitor.imports.filter { $0.contains("GRDB") }

      if !grdbImports.isEmpty {
        violations.append((file: file.lastPathComponent, imports: grdbImports))
      }
    }

    XCTAssertTrue(
      violations.isEmpty,
      """

      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      ⚠️  Layer Boundary Violation Detected
      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      UI files should not import GRDB directly.
      Use TranscriptOrchestrator or other service layer APIs instead.

      Violations found:
      \(violations.map { "  • \($0.file): \($0.imports.joined(separator: ", "))" }.joined(separator: "\n"))

      Architecture rule:
        UI → ViewModel → Orchestrator → Repository → Database

      Never skip layers. UI files must not import database libraries.

      Fix: Remove GRDB imports and use TranscriptOrchestrator methods.
      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      """
    )
  }

  func testViewModelLayerDoesNotImportGRDB() throws {
    // ViewModels should also not directly import GRDB
    let viewModelFiles = try findSwiftFiles(matching: "*ViewModel.swift")

    var violations: [(file: String, imports: [String])] = []

    for file in viewModelFiles {
      let source = try String(contentsOf: file)
      let tree = Parser.parse(source: source)

      let visitor = ImportVisitor(viewMode: .sourceAccurate)
      visitor.walk(tree)

      let grdbImports = visitor.imports.filter { $0.contains("GRDB") }

      if !grdbImports.isEmpty {
        violations.append((file: file.lastPathComponent, imports: grdbImports))
      }
    }

    XCTAssertTrue(
      violations.isEmpty,
      """

      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      ⚠️  Layer Boundary Violation in ViewModels
      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      ViewModel files should not import GRDB directly.
      Use TranscriptOrchestrator or other service layer APIs instead.

      Violations found:
      \(violations.map { "  • \($0.file): \($0.imports.joined(separator: ", "))" }.joined(separator: "\n"))

      ViewModels are part of the presentation layer and should remain
      database-agnostic. They should interact with the orchestrator/service
      layer, which handles all database operations.
      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      """
    )
  }

  func testCoreModelsDoNotImportUIKit() throws {
    // Core data models should not import UI frameworks
    let coreDirectory = try findCoreDirectory()
    let modelFiles = try FileManager.default
      .contentsOfDirectory(at: coreDirectory.appendingPathComponent("Database"), includingPropertiesForKeys: nil, options: [])
      .filter { $0.pathExtension == "swift" }

    var violations: [(file: String, imports: [String])] = []

    for file in modelFiles {
      let source = try String(contentsOf: file)
      let tree = Parser.parse(source: source)

      let visitor = ImportVisitor(viewMode: .sourceAccurate)
      visitor.walk(tree)

      let uiImports = visitor.imports.filter {
        $0.contains("SwiftUI") ||
        $0.contains("AppKit") ||
        $0.contains("UIKit")
      }

      if !uiImports.isEmpty {
        violations.append((file: file.lastPathComponent, imports: uiImports))
      }
    }

    XCTAssertTrue(
      violations.isEmpty,
      """

      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      ⚠️  Reverse Dependency Violation
      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      Core layer files should not import UI frameworks.
      This creates circular dependencies and reduces reusability.

      Violations found:
      \(violations.map { "  • \($0.file): \($0.imports.joined(separator: ", "))" }.joined(separator: "\n"))

      Core models, repositories, and database code should be UI-agnostic
      and importable by non-UI code (CLI tools, tests, background workers).
      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      """
    )
  }

  func testOrchestratorLayerDoesNotImportSwiftUI() throws {
    // Orchestrator layer should not import UI frameworks (they're service layer)
    let orchestratorFiles = try findSwiftFiles(matching: "*Orchestrator.swift")

    var violations: [(file: String, imports: [String])] = []

    for file in orchestratorFiles {
      let source = try String(contentsOf: file)
      let tree = Parser.parse(source: source)

      let visitor = ImportVisitor(viewMode: .sourceAccurate)
      visitor.walk(tree)

      let uiImports = visitor.imports.filter {
        $0.contains("SwiftUI") ||
        $0.contains("AppKit")
      }

      if !uiImports.isEmpty {
        violations.append((file: file.lastPathComponent, imports: uiImports))
      }
    }

    XCTAssertTrue(
      violations.isEmpty,
      """

      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      ⚠️  Service Layer Should Be UI-Agnostic
      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      Orchestrator files should not import UI frameworks.
      They are part of the service/business logic layer.

      Violations found:
      \(violations.map { "  • \($0.file): \($0.imports.joined(separator: ", "))" }.joined(separator: "\n"))

      Orchestrators should be testable and reusable without UI dependencies.
      If you need to communicate with UI, use async callbacks or notifications.
      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      """
    )
  }

  // MARK: - Helper Methods

  private func findUIDirectory() throws -> URL {
    // Try to find the UI directory from test bundle
    let currentFile = URL(fileURLWithPath: #file)
    var current = currentFile.deletingLastPathComponent()

    // Navigate up to find Contextify directory
    for _ in 0..<10 {
      let contextifyDir = current.appendingPathComponent("Contextify").appendingPathComponent("Contextify")
      if FileManager.default.fileExists(atPath: contextifyDir.path) {
        return contextifyDir
      }
      current = current.deletingLastPathComponent()
    }

    throw XCTSkip("Could not find UI directory (Contextify/Contextify/)")
  }

  private func findCoreDirectory() throws -> URL {
    let currentFile = URL(fileURLWithPath: #file)
    var current = currentFile.deletingLastPathComponent()

    // Navigate up to find app/Sources/ContextifyCore
    for _ in 0..<10 {
      let coreDir = current.appendingPathComponent("app").appendingPathComponent("Sources").appendingPathComponent("ContextifyCore")
      if FileManager.default.fileExists(atPath: coreDir.path) {
        return coreDir
      }
      current = current.deletingLastPathComponent()
    }

    throw XCTSkip("Could not find Core directory (app/Sources/ContextifyCore/)")
  }

  private func findSwiftFiles(matching pattern: String) throws -> [URL] {
    let uiDirectory = try findUIDirectory()
    let allFiles = try FileManager.default
      .contentsOfDirectory(at: uiDirectory, includingPropertiesForKeys: nil, options: [])
      .filter { $0.pathExtension == "swift" }

    // Simple glob matching (convert * to regex)
    let regexPattern = pattern
      .replacingOccurrences(of: "*", with: ".*")
      .replacingOccurrences(of: ".", with: "\\.")

    return allFiles.filter { file in
      let filename = file.lastPathComponent
      return filename.range(of: regexPattern, options: .regularExpression) != nil
    }
  }
}

// MARK: - SwiftSyntax Visitor

private class ImportVisitor: SyntaxVisitor {
  var imports: [String] = []

  override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
    let importPath = node.path.description.trimmingCharacters(in: .whitespaces)
    imports.append(importPath)
    return .visitChildren
  }
}

// MARK: - Integration with Pre-commit Hook

extension ArchitecturalTests {
  /// This test is designed to be run by pre-commit hooks
  /// It will fail fast if any layer violations are detected
  func testAllArchitecturalRules() throws {
    var allViolations: [String] = []

    // Run all architectural tests and collect violations
    do {
      try testUILayerDoesNotImportGRDB()
    } catch {
      allViolations.append("UI Layer GRDB violations: \(error.localizedDescription)")
    }

    do {
      try testViewModelLayerDoesNotImportGRDB()
    } catch {
      allViolations.append("ViewModel Layer GRDB violations: \(error.localizedDescription)")
    }

    do {
      try testCoreModelsDoNotImportUIKit()
    } catch {
      allViolations.append("Core Layer UI import violations: \(error.localizedDescription)")
    }

    do {
      try testOrchestratorLayerDoesNotImportSwiftUI()
    } catch {
      allViolations.append("Orchestrator Layer UI import violations: \(error.localizedDescription)")
    }

    XCTAssertTrue(
      allViolations.isEmpty,
      """

      ╔═══════════════════════════════════════════════════════════════╗
      ║                                                               ║
      ║  🚨 ARCHITECTURAL VIOLATIONS DETECTED                         ║
      ║                                                               ║
      ╚═══════════════════════════════════════════════════════════════╝

      The following layer boundary violations were found:

      \(allViolations.map { "  ❌ \($0)" }.joined(separator: "\n\n"))

      Architecture rules (UI → ViewModel → Orchestrator → Repository → DB):

        1. UI files must NOT import GRDB
        2. ViewModels must NOT import GRDB
        3. Core/Database files must NOT import SwiftUI/AppKit
        4. Orchestrators must NOT import SwiftUI/AppKit

      Why these rules matter:

        • Maintainability: Clear separation of concerns
        • Testability: Each layer can be tested independently
        • Reusability: Core logic works without UI
        • Safety: Prevents circular dependencies and tight coupling

      To fix: Remove direct database imports from UI/ViewModel layers.
      Use TranscriptOrchestrator or service layer APIs instead.

      """
    )
  }
}
