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
    let skillFile = userSkillSource.appendingPathComponent("SKILL.md")
    let newData = try Data(contentsOf: skillFile)

    // Set up paths for both targets
    let claudeSkillDir = home.appendingPathComponent(".claude/skills/total-recall")
    let claudeSkillDest = claudeSkillDir.appendingPathComponent("SKILL.md")
    let codexSkillDir = home.appendingPathComponent(".codex/skills/total-recall")
    let codexSkillDest = codexSkillDir.appendingPathComponent("SKILL.md")

    // Check state of both destinations
    let claudeState = try checkInstallState(dest: claudeSkillDest, newData: newData)
    let codexState = try checkInstallState(dest: codexSkillDest, newData: newData)

    // If both are up to date, report and exit
    if claudeState == .upToDate && codexState == .upToDate {
      if json {
        let result = InstallResult(
          action: "up_to_date",
          claudeSkillPath: claudeSkillDir.path,
          codexSkillPath: codexSkillDir.path
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
      } else {
        print("Skill already installed and up to date.")
        print("  Claude Code: \(claudeSkillDir.path)")
        print("  Codex CLI:   \(codexSkillDir.path)")
      }
      return
    }

    // Check if any target needs --force
    if !force {
      if claudeState == .existsDiffers {
        throw ValidationError("""
          Claude Code skill exists and differs from source.
          Re-run with --force to overwrite: contextify install-skill --force
          """)
      }
      if codexState == .existsDiffers {
        throw ValidationError("""
          Codex CLI skill exists and differs from source.
          Re-run with --force to overwrite: contextify install-skill --force
          """)
      }
    }

    // Install to Claude Code
    try FileManager.default.createDirectory(at: claudeSkillDir, withIntermediateDirectories: true)
    if claudeState != .upToDate {
      if FileManager.default.fileExists(atPath: claudeSkillDest.path) {
        try FileManager.default.removeItem(at: claudeSkillDest)
      }
      try newData.write(to: claudeSkillDest, options: .atomic)
    }

    // Warn about CODEX_HOME if set
    if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !codexHome.isEmpty {
      let warning = "Warning: CODEX_HOME is set to \(codexHome)\n" +
                    "Skill installed to default ~/.codex/skills/ - you may need to copy manually.\n"
      FileHandle.standardError.write(Data(warning.utf8))
    }

    // Install to Codex CLI
    try FileManager.default.createDirectory(at: codexSkillDir, withIntermediateDirectories: true)
    if codexState != .upToDate {
      if FileManager.default.fileExists(atPath: codexSkillDest.path) {
        try FileManager.default.removeItem(at: codexSkillDest)
      }
      try newData.write(to: codexSkillDest, options: .atomic)
    }

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

// MARK: - Install State

private enum InstallState {
  case notInstalled
  case upToDate
  case existsDiffers
}

private func checkInstallState(dest: URL, newData: Data) throws -> InstallState {
  guard FileManager.default.fileExists(atPath: dest.path) else {
    return .notInstalled
  }
  let existingData = try Data(contentsOf: dest)
  return existingData == newData ? .upToDate : .existsDiffers
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

  // Resolve path if not absolute - search PATH manually for portability
  if !executablePath.contains("/") {
    if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
      let pathDirs = pathEnv.split(separator: ":").map(String.init)
      for dir in pathDirs {
        let candidate = URL(fileURLWithPath: dir).appendingPathComponent(executablePath)
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
          executablePath = candidate.path
          break
        }
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
