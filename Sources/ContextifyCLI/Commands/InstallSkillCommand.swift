import ArgumentParser
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Install the Total Recall skill for Claude Code and Codex CLI
struct InstallSkillCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "install-skill",
    abstract: "Install Total Recall skill for Claude Code and Codex CLI",
    discussion: """
      Installs the Total Recall skill to enable searching your conversation
      history from within Claude Code or Codex CLI.

      SKILL LOCATIONS:
        Claude Code: ~/.claude/skills/total-recall/SKILL.md
        Codex CLI:   ~/.codex/skills/total-recall/SKILL.md

      After installation, restart your CLI tool and use /total-recall to
      search your past conversations.
      """
  )

  @Flag(name: .long, help: "Output result as JSON")
  var json: Bool = false

  @Flag(name: .long, help: "Overwrite existing skill files")
  var force: Bool = false

  func run() throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let userSkillSource = try findUserSkillSource()

    // Install to Claude Code
    let claudeSkillDir = home.appendingPathComponent(".claude/skills/total-recall")
    try FileManager.default.createDirectory(at: claudeSkillDir, withIntermediateDirectories: true)

    let skillFile = userSkillSource.appendingPathComponent("SKILL.md")
    let claudeSkillDest = claudeSkillDir.appendingPathComponent("SKILL.md")

    if FileManager.default.fileExists(atPath: claudeSkillDest.path) {
      if force {
        try FileManager.default.removeItem(at: claudeSkillDest)
      } else if !json {
        // Check if files are identical
        let existingData = try Data(contentsOf: claudeSkillDest)
        let newData = try Data(contentsOf: skillFile)
        if existingData == newData {
          print("Skill already installed and up to date.")
          print("  Claude Code: \(claudeSkillDir.path)")
          return
        }
      }
    }
    try FileManager.default.copyItem(at: skillFile, to: claudeSkillDest)

    // Warn about CODEX_HOME if set
    if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !codexHome.isEmpty {
      let warning = "Warning: CODEX_HOME is set to \(codexHome)\n" +
                    "Skill installed to default ~/.codex/skills/ - you may need to copy manually.\n"
      FileHandle.standardError.write(Data(warning.utf8))
    }

    // Install to Codex CLI
    let codexSkillDir = home.appendingPathComponent(".codex/skills/total-recall")
    try FileManager.default.createDirectory(at: codexSkillDir, withIntermediateDirectories: true)
    let codexSkillDest = codexSkillDir.appendingPathComponent("SKILL.md")

    let skillData = try Data(contentsOf: skillFile)
    if FileManager.default.fileExists(atPath: codexSkillDest.path) {
      try FileManager.default.removeItem(at: codexSkillDest)
    }
    try skillData.write(to: codexSkillDest, options: .atomic)

    // Output result
    if json {
      let result = InstallResult(
        action: "installed",
        claudeSkillPath: claudeSkillDir.path,
        codexSkillPath: codexSkillDir.path
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } else {
      print("Contextify Total Recall installed!")
      print("  Claude Code: \(claudeSkillDir.path)")
      print("  Codex CLI:   \(codexSkillDir.path)")
      print("")
      print("Restart your CLI tool, then use /total-recall to search history.")
    }
  }
}

// MARK: - Helpers

private struct InstallResult: Encodable {
  let action: String
  let claudeSkillPath: String
  let codexSkillPath: String
}

/// Find the source directory containing the SKILL.md file
private func findUserSkillSource() throws -> URL {
  // 1. Check relative to current working directory (repo checkout)
  let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  let repoUserSkill = cwdURL.appendingPathComponent("contextify-query/user-skill/total-recall")
  if FileManager.default.fileExists(atPath: repoUserSkill.appendingPathComponent("SKILL.md").path) {
    return repoUserSkill
  }

  // 2. Check relative to executable (tarball extraction)
  var executablePath = CommandLine.arguments[0]

  // Resolve path if not absolute
  if !executablePath.contains("/") {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = [executablePath]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    try? process.run()
    process.waitUntilExit()

    if process.terminationStatus == 0 {
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
         !path.isEmpty {
        executablePath = path
      }
    }
  }

  let executableURL = URL(fileURLWithPath: executablePath)
  let execDir = executableURL.deletingLastPathComponent()

  // Check sibling directory
  let siblingUserSkill = execDir.appendingPathComponent("user-skill/total-recall")
  if FileManager.default.fileExists(atPath: siblingUserSkill.appendingPathComponent("SKILL.md").path) {
    return siblingUserSkill
  }

  // 3. Check Homebrew Cellar structure
  let resolvedExec = URL(fileURLWithPath: (executablePath as NSString).resolvingSymlinksInPath)
  let cellarBin = resolvedExec.deletingLastPathComponent()
  let cellarRoot = cellarBin.deletingLastPathComponent()
  let cellarUserSkill = cellarRoot.appendingPathComponent("share/user-skill/total-recall")
  if FileManager.default.fileExists(atPath: cellarUserSkill.appendingPathComponent("SKILL.md").path) {
    return cellarUserSkill
  }

  throw ValidationError("""
    Skill files not found.

    If using the Linux release tarball:
      Extract the archive and run install-skill from that directory,
      or ensure user-skill/ is in the same directory as the contextify binary.

    Searched locations:
      - \(repoUserSkill.path)
      - \(siblingUserSkill.path)
      - \(cellarUserSkill.path)
    """)
}
