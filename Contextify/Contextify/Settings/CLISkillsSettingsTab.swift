import SwiftUI
import ContextifyCore
import OSLog

private struct MonospaceCopyRow: View {
  let value: String
  let copyLabel: String

  init(_ value: String, copyLabel: String = "Copy") {
    self.value = value
    self.copyLabel = copyLabel
  }

  var body: some View {
    HStack(spacing: 8) {
      Text(value)
        .font(.system(.caption, design: .monospaced))
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)

      Button(copyLabel) {
        value.copyToClipboard()
      }
      .controlSize(.small)
    }
  }
}

struct CLISkillsSettingsTab: View {
  @StateObject private var installer = ContextifyQueryCLIInstaller()
  @State private var didLogAppear: Bool = false

  private let log = Logger(subsystem: "dev.contextify", category: "QueryCLIInstall")
  private let claudePluginCommands = "/plugin marketplace add PeterPym/contextify\n/plugin install query@contextify"

  var body: some View {
    Form {
      Section("CLI") {
        LabeledContent("Installed on PATH:") {
          if let path = installer.status.installedOnPATH?.path {
            MonospaceCopyRow(path)
          } else {
            Text("Not found")
              .foregroundStyle(.secondary)
          }
        }

        if let path = installer.status.installedOnPATH, installer.status.installedIsOurShim {
          Text("Detected Contextify shim at \(path.path)")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if installer.status.installedOnPATH != nil {
          Text("An executable named `contextify-query` is on PATH, but it does not look like Contextify’s shim.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        HStack(spacing: 12) {
          if Sandbox.isSandboxed {
            Button("Choose Install Folder…") {
              log.info("[QUERYCLI-INSTALL-START] mode=appstore action=chooseFolder")
              installer.chooseFolderAndInstallSandboxed()
            }

            if installer.status.sandboxedInstallDirectory != nil {
              Button("Repair") {
                log.info("[QUERYCLI-INSTALL-START] mode=appstore action=repairSavedFolder")
                installer.repairUsingSavedSandboxedFolder()
              }
            }
          } else {
            Button("Install/Repair") {
              log.info("[QUERYCLI-INSTALL-START] mode=dmg action=installRecommended")
              installer.installRecommendedDMG()
            }
            .keyboardShortcut(.defaultAction)
            .keyboardShortcut("i", modifiers: [.command, .shift])
          }

          if installer.status.installedIsOurShim, installer.status.installedOnPATH != nil {
            Button("Uninstall") {
              log.info("[QUERYCLI-UNINSTALL-START]")
              installer.uninstallFromInstalledPATH()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
          }
        }

        if let sudo = installer.lastSudoCommand {
          VStack(alignment: .leading, spacing: 8) {
            Text("Permission Fix (copy/paste):")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(sudo)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
              .lineLimit(3)
              .truncationMode(.tail)
              .padding(8)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color(nsColor: .controlBackgroundColor))
              .cornerRadius(6)
            Button("Copy sudo command") {
              log.info("[QUERYCLI-INSTALL-SUDO-COPY]")
              sudo.copyToClipboard()
            }
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

      Section("Claude Code") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Install the Contextify query plugin in Claude Code:")
            .font(.caption)
            .foregroundStyle(.secondary)

          Text(claudePluginCommands)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)

          HStack {
            Menu("Copy…") {
              Button("Marketplace command") {
                "/plugin marketplace add PeterPym/contextify".copyToClipboard()
              }
              Button("Install command") {
                "/plugin install query@contextify".copyToClipboard()
              }
              Divider()
              Button("Both commands") {
                claudePluginCommands.copyToClipboard()
              }
            }
            .controlSize(.small)

            Spacer()
          }
        }
      }

      Section("Advanced") {
        DisclosureGroup("Bundled paths") {
          VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Bundled CLI:") {
              MonospaceCopyRow(installer.status.bundledCLIURL.path)
            }
            LabeledContent("Bundled shim:") {
              MonospaceCopyRow(installer.status.bundledShimURL.path)
            }
          }
          .padding(.top, 6)
        }
      }
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
