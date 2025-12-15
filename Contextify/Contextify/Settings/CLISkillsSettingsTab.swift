import SwiftUI
import ContextifyCore
import OSLog

private enum CLIStepState: Equatable {
  case neutral
  case completed
  case warning

  var iconName: String? {
    switch self {
    case .neutral: return nil
    case .completed: return "checkmark.circle.fill"
    case .warning: return "exclamationmark.triangle.fill"
    }
  }

  var iconColor: Color {
    switch self {
    case .neutral: return .secondary
    case .completed: return .green
    case .warning: return .contextifyYellow
    }
  }
}

private struct CopyIconButton: View {
  let value: String

  var body: some View {
    Button {
      value.copyToClipboard()
    } label: {
      Image(systemName: "doc.on.doc")
    }
    .buttonStyle(.borderless)
    .help("Copy")
  }
}

private struct PathValueRow: View {
  let value: String

  var body: some View {
    HStack(spacing: 8) {
      Text(value)
        .font(.system(.caption, design: .monospaced))
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)

      CopyIconButton(value: value)
    }
  }
}

private struct SetupStepCard<Content: View, Action: View>: View {
  let title: String
  let state: CLIStepState
  @ViewBuilder var action: Action
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Text(title)
          .font(.headline)

        Spacer()

        if let iconName = state.iconName {
          Image(systemName: iconName)
            .foregroundStyle(state.iconColor)
        }

        action
      }

      content
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor))
    .cornerRadius(8)
  }
}

private struct CommandSheet: View {
  let title: String
  let subtitle: String
  let command: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.headline)

      Text(subtitle)
        .foregroundStyle(.secondary)

      Text(command)
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)

      HStack {
        Spacer()
        Button("Copy") {
          command.copyToClipboard()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(16)
    .frame(width: 640)
  }
}

struct CLISkillsSettingsTab: View {
  @StateObject private var installer = ContextifyQueryCLIInstaller()
  @State private var didLogAppear: Bool = false
  @State private var showingSudoSheet: Bool = false
  @State private var showingClaudeSheet: Bool = false

  private let log = Logger(subsystem: "dev.contextify", category: "QueryCLIInstall")
  private let claudePluginCommands = "/plugin marketplace add PeterPym/contextify\n/plugin install query@contextify"

  var body: some View {
    Form {
      Section {
        let installState: CLIStepState = {
          if installer.status.installedIsOurShim { return .completed }
          if installer.status.installedOnPATH != nil { return .warning }
          return .neutral
        }()

        VStack(alignment: .leading, spacing: 12) {
          SetupStepCard(title: "Install Contextify CLI", state: installState) {
            if Sandbox.isSandboxed {
              if installer.status.installedIsOurShim {
                Button("Install/Repair") {
                  log.info("[QUERYCLI-INSTALL-START] mode=appstore action=chooseFolder")
                  installer.chooseFolderAndInstallSandboxed()
                }
                .buttonStyle(.bordered)
              } else {
                Button("Install/Repair") {
                  log.info("[QUERYCLI-INSTALL-START] mode=appstore action=chooseFolder")
                  installer.chooseFolderAndInstallSandboxed()
                }
                .buttonStyle(.borderedProminent)
              }

              if installer.status.sandboxedInstallDirectory != nil, !installer.status.installedIsOurShim {
                Button("Repair") {
                  log.info("[QUERYCLI-INSTALL-START] mode=appstore action=repairSavedFolder")
                  installer.repairUsingSavedSandboxedFolder()
                }
                .buttonStyle(.bordered)
              }
            } else if installer.status.installedIsOurShim {
              Button("Uninstall") {
                log.info("[QUERYCLI-UNINSTALL-START]")
                installer.uninstallFromInstalledPATH()
              }
              .buttonStyle(.bordered)
              .keyboardShortcut("u", modifiers: [.command, .shift])
            } else {
              Button("Install/Repair") {
                log.info("[QUERYCLI-INSTALL-START] mode=dmg action=installRecommended")
                installer.installRecommendedDMG()
              }
              .buttonStyle(.borderedProminent)
              .keyboardShortcut(.defaultAction)
              .keyboardShortcut("i", modifiers: [.command, .shift])
            }
          } content: {
            VStack(alignment: .leading, spacing: 8) {
              LabeledContent("Install path") {
                if let path = installer.status.installedOnPATH?.path {
                  PathValueRow(value: path)
                } else {
                  Text("Not found")
                    .foregroundStyle(.secondary)
                }
              }

              if installer.status.installedIsOurShim, let path = installer.status.installedOnPATH?.path {
                Text("Contextify shim is installed at \(path).")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              } else if installer.status.installedOnPATH != nil {
                Text("A `contextify-query` executable is on PATH, but it does not look like Contextify’s shim.")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              } else {
                Text("Install Contextify’s shim so tools can run `contextify-query` reliably.")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }

              if installer.lastSudoCommand != nil {
                HStack(spacing: 8) {
                  Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.contextifyYellow)
                  Text("Permission is required to install into the selected folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  Spacer()
                  Button("Show…") { showingSudoSheet = true }
                    .controlSize(.small)
                }
              }

              if let success = installer.lastSuccess {
                Text(success)
                  .font(.caption)
                  .foregroundStyle(.green)
              }

              if let error = installer.lastError {
                Text(error)
                  .font(.caption)
                  .foregroundStyle(.red)
              }
            }
          }

          SetupStepCard(title: "Enable Claude Code plugin", state: .neutral) {
            Button("Show commands…") {
              showingClaudeSheet = true
            }
            .buttonStyle(.bordered)
          } content: {
            Text("Install the Contextify query plugin so Claude Code can run deterministic searches and context windows.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
        .listRowBackground(Color.clear)
      }

      Section {
        SetupStepCard(title: "Advanced", state: .neutral) {
          Spacer()
        } content: {
          DisclosureGroup("Bundled paths") {
            VStack(alignment: .leading, spacing: 12) {
              LabeledContent("Bundled CLI:") {
                PathValueRow(value: installer.status.bundledCLIURL.path)
              }
              LabeledContent("Bundled shim:") {
                PathValueRow(value: installer.status.bundledShimURL.path)
              }
            }
            .padding(.top, 6)
          }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
        .listRowBackground(Color.clear)
      }
    }
    .sheet(isPresented: $showingSudoSheet) {
      if let sudo = installer.lastSudoCommand {
        CommandSheet(
          title: "Permission Fix",
          subtitle: "Copy and run this command in Terminal:",
          command: sudo
        )
      }
    }
    .sheet(isPresented: $showingClaudeSheet) {
      CommandSheet(
        title: "Claude Code plugin commands",
        subtitle: "Run these commands in Claude Code:",
        command: claudePluginCommands
      )
    }
    .onAppear {
      if !didLogAppear {
        didLogAppear = true
        log.info("[QUERYCLI-SETTINGS-TAB-OPEN]")
      }
      installer.refreshStatus()
    }
    .frame(width: 520)
  }
}
