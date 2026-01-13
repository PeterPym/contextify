import ArgumentParser
import Foundation

/// Uninstall the Total Recall skill from Claude Code and Codex CLI
struct UninstallSkillCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "uninstall-skill",
    abstract: "Remove Total Recall skill from Claude Code and Codex CLI",
    discussion: """
      Removes the Total Recall skill directories from both Claude Code and
      Codex CLI skill locations.

      REMOVED LOCATIONS:
        ~/.claude/skills/total-recall/
        ~/.codex/skills/total-recall/
      """
  )

  @Flag(name: .long, help: "Output result as JSON")
  var json: Bool = false

  func run() throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    var removedClaude = false
    var removedCodex = false

    // Remove from Claude Code
    let claudeSkillDir = home.appendingPathComponent(".claude/skills/total-recall")
    if FileManager.default.fileExists(atPath: claudeSkillDir.path) {
      try FileManager.default.removeItem(at: claudeSkillDir)
      removedClaude = true
    }

    // Remove from Codex CLI
    let codexSkillDir = home.appendingPathComponent(".codex/skills/total-recall")
    if FileManager.default.fileExists(atPath: codexSkillDir.path) {
      try FileManager.default.removeItem(at: codexSkillDir)
      removedCodex = true
    }

    // Output result
    if json {
      let result = UninstallResult(
        action: "uninstalled",
        claudeSkillPath: claudeSkillDir.path,
        codexSkillPath: codexSkillDir.path,
        claudeRemoved: removedClaude,
        codexRemoved: removedCodex
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } else {
      if removedClaude || removedCodex {
        print("Contextify Total Recall uninstalled.")
        if removedClaude {
          print("  Removed: \(claudeSkillDir.path)")
        }
        if removedCodex {
          print("  Removed: \(codexSkillDir.path)")
        }
      } else {
        print("Total Recall skill was not installed.")
      }
    }
  }
}

// MARK: - Helpers

private struct UninstallResult: Encodable {
  let action: String
  let claudeSkillPath: String
  let codexSkillPath: String
  let claudeRemoved: Bool
  let codexRemoved: Bool
}
