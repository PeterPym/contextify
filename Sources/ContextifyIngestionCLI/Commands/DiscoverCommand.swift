// SPDX-License-Identifier: MIT
// DiscoverCommand.swift - Discover transcripts without ingesting

import ArgumentParser
import Foundation
#if os(macOS)
import ContextifyCore
#else
import ContextifyIngestionCore
#endif

struct DiscoverCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "discover",
    abstract: "Discover transcripts without ingesting them"
  )

  @Option(name: .long, parsing: .upToNextOption, help: "Input directories to scan for transcripts")
  var input: [String] = []

  @Option(name: .long, help: "Transcript provider: auto, claude, or codex")
  var provider: ProviderOption = .auto

  @Option(name: .long, help: "Output format: jsonl, json, or human")
  var format: OutputFormat = .human

  enum ProviderOption: String, ExpressibleByArgument {
    case auto, claude, codex
  }

  enum OutputFormat: String, ExpressibleByArgument {
    case jsonl, json, human
  }

  mutating func run() async throws {
    // Use LightweightDiscoveryService for fast discovery
    let discovery = LightweightDiscoveryService()
    var projects = await discovery.discoverProjectsLightweight()

    // Filter by provider if specified
    if provider != .auto {
      let providerFilter = provider == .claude ? "claude.code" : "codex.cli"
      projects = projects.filter { $0.provider == providerFilter }
    }

    // Filter by input paths if specified
    if !input.isEmpty {
      let inputURLs = Set(input.map { URL(fileURLWithPath: $0).standardizedFileURL })
      projects = projects.filter { project in
        project.transcriptFiles.contains { url in
          inputURLs.contains { inputURL in
            url.path.hasPrefix(inputURL.path)
          }
        }
      }
    }

    // Output results
    switch format {
    case .human:
      printHumanFormat(projects)
    case .json:
      printJSONFormat(projects)
    case .jsonl:
      printJSONLFormat(projects)
    }
  }

  private func printHumanFormat(_ projects: [LightweightProject]) {
    print("Discovered Projects")
    print("===================")
    print("")

    if projects.isEmpty {
      print("No projects found.")
      if input.isEmpty {
        print("")
        print("Searched default locations:")
        print("  ~/.claude/projects/")
        print("  ~/.codex/sessions/")
      }
      return
    }

    var totalTranscripts = 0
    for project in projects {
      print("Project: \(project.displayName)")
      print("  Provider: \(project.provider)")
      print("  Path: \(project.canonicalRootPath)")
      print("  Transcripts: \(project.transcriptFiles.count)")

      if project.transcriptFiles.count <= 5 {
        for url in project.transcriptFiles {
          print("    - \(url.lastPathComponent)")
        }
      } else {
        for url in project.transcriptFiles.prefix(3) {
          print("    - \(url.lastPathComponent)")
        }
        print("    ... and \(project.transcriptFiles.count - 3) more")
      }
      print("")

      totalTranscripts += project.transcriptFiles.count
    }

    print("===================")
    print("Total: \(projects.count) projects, \(totalTranscripts) transcripts")
  }

  private func printJSONFormat(_ projects: [LightweightProject]) {
    let output: [[String: Any]] = projects.map { project in
      [
        "id": project.id,
        "name": project.displayName,
        "provider": project.provider,
        "path": project.canonicalRootPath,
        "cwd": project.cwd as Any,
        "transcripts": project.transcriptFiles.map { $0.path }
      ]
    }

    if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
       let json = String(data: data, encoding: .utf8) {
      print(json)
    }
  }

  private func printJSONLFormat(_ projects: [LightweightProject]) {
    for project in projects {
      let output: [String: Any] = [
        "id": project.id,
        "name": project.displayName,
        "provider": project.provider,
        "path": project.canonicalRootPath,
        "cwd": project.cwd as Any,
        "transcriptCount": project.transcriptFiles.count,
        "transcripts": project.transcriptFiles.map { $0.path }
      ]

      if let data = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]),
         var json = String(data: data, encoding: .utf8) {
        json.append("\n")
        print(json, terminator: "")
      }
    }
  }
}
