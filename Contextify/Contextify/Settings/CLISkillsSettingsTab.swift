import SwiftUI
import ContextifyCore
import OSLog

struct CLISkillsSettingsTab: View {
  @StateObject private var installer = ContextifyQueryCLIInstaller()
  @State private var didLogAppear: Bool = false

  private let log = Logger(subsystem: "dev.contextify", category: "QueryCLIInstall")

  var body: some View {
    Form {
      Section("CLI") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Bundled CLI:")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(installer.status.bundledCLIURL.path)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Bundled shim (installed onto PATH):")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(installer.status.bundledShimURL.path)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .foregroundStyle(.secondary)
        }

        Divider()

        HStack(spacing: 12) {
          if Sandbox.isSandboxed {
            Button("Choose Install Folder…") {
              log.info("[QUERYCLI-INSTALL-START] mode=appstore action=chooseFolder")
              installer.chooseFolderAndInstallSandboxed()
            }

            if installer.status.sandboxedInstallDirectory != nil {
              Button("Repair (Saved Folder)") {
                log.info("[QUERYCLI-INSTALL-START] mode=appstore action=repairSavedFolder")
                installer.repairUsingSavedSandboxedFolder()
              }
            }
          } else {
            Button("Install/Repair (Recommended)") {
              log.info("[QUERYCLI-INSTALL-START] mode=dmg action=installRecommended")
              installer.installRecommendedDMG()
            }
          }

          if installer.status.installedIsOurShim, installer.status.installedOnPATH != nil {
            Button("Uninstall") {
              log.info("[QUERYCLI-UNINSTALL-START]")
              installer.uninstallFromInstalledPATH()
            }
          }
        }
      }

      Section("Status") {
        HStack {
          Text("Installed on PATH:")
          Spacer()
          if let path = installer.status.installedOnPATH?.path {
            Text(path)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
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

        if let sudo = installer.lastSudoCommand {
          VStack(alignment: .leading, spacing: 8) {
            Text("Permission Fix (copy/paste):")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(sudo)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
              .padding(6)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color(nsColor: .controlBackgroundColor))
              .cornerRadius(4)
            Button("Copy sudo command") {
              log.info("[QUERYCLI-INSTALL-SUDO-COPY]")
              sudo.copyToClipboard()
            }
            .controlSize(.small)
          }
        }
      }

      Section("Claude Code plugin") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Install in Claude Code (after Contextify is installed):")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text("/plugin marketplace add PeterPym/contextify\n/plugin install query@contextify")
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
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
