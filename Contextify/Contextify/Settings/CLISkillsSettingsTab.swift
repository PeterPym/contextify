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
  @ObservedObject private var coordinator = CLICoordinator.shared
  @State private var didLogAppear: Bool = false

  private let log = Logger(subsystem: "dev.contextify", category: "CLISettings")

  private let homebrewCommand = "brew install PeterPym/contextify/contextify-query"

  @ViewBuilder
  private func instructionRow(number: String, text: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text(number)
        .font(.system(.caption, design: .monospaced).weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 16)
      Text(text)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var homebrewInstructionsView: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Enable Contextify skills in Claude Code and Codex.")
        .font(.body)

      Text("Due to App Store sandbox restrictions, the CLI must be installed separately via Homebrew:")
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        Text(homebrewCommand)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .padding(.vertical, 6)
          .padding(.horizontal, 8)
          .background(Color(nsColor: .controlBackgroundColor))
          .cornerRadius(6)

        Button {
          homebrewCommand.copyToClipboard()
        } label: {
          Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help("Copy command")
      }

      Text("Then verify installation:")
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        Text("contextify status")
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .padding(.vertical, 6)
          .padding(.horizontal, 8)
          .background(Color(nsColor: .controlBackgroundColor))
          .cornerRadius(6)

        Button {
          "contextify status".copyToClipboard()
        } label: {
          Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help("Copy command")
      }

    }
  }

  private var statusState: CLIStepState {
    switch coordinator.state {
    case .enabled(_, _, let repairIssue):
      return repairIssue != nil ? .warning : .completed
    case .enabledViaHomebrew:
      return .completed
    case .failed, .upgrading:
      return .warning
    default:
      return .neutral
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          VStack(alignment: .leading, spacing: 12) {
            SetupStepCard(title: "CLI Installation", state: statusState) {
            // Action buttons - App Store has no buttons (Homebrew-managed)
            if Sandbox.isSandboxed {
              EmptyView()
            } else if coordinator.isHandlingOperation {
              ProgressView()
                .controlSize(.small)
            } else if coordinator.needsRepair {
              Button("Repair") {
                log.info("[CLI-REPAIR-START]")
                Task {
                  await coordinator.repair()
                }
              }
              .buttonStyle(.borderedProminent)
              .tint(Color.contextifyYellow)
            } else if coordinator.isEnabled {
              Button("Disable") {
                log.info("[CLI-DISABLE-START]")
                Task {
                  await coordinator.disable()
                }
              }
              .buttonStyle(.bordered)
            } else {
              Button("Enable") {
                log.info("[CLI-ENABLE-START]")
                Task {
                  await coordinator.enable()
                }
              }
              .buttonStyle(.borderedProminent)
              .tint(Color.contextifyBlue)
            }
          } content: {
            VStack(alignment: .leading, spacing: 12) {
              // Status display
              switch coordinator.state {
              case .disabled:
                if Sandbox.isSandboxed {
                  // App Store: Show Homebrew instructions
                  homebrewInstructionsView
                } else {
                  // DMG: Simple text
                  Text("Not installed")
                    .font(.body)
                  Text("The CLI shim and skills are not installed. Click Enable to install automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

              case .installing:
                HStack(spacing: 6) {
                  ProgressView()
                    .controlSize(.small)
                  Text("Installing...")
                    .font(.body)
                }

              case .enabled(let version, let pathWarning, let repairIssue):
                HStack(spacing: 6) {
                  if repairIssue != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                      .foregroundStyle(Color.contextifyYellow)
                  } else {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(.green)
                  }
                  Text("Installed (v\(version))")
                    .font(.body)
                }

                // Show repair warning if needed
                if let repairIssue = repairIssue {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(repairWarningMessage(for: repairIssue))
                      .font(.caption)
                      .foregroundStyle(.secondary)
                    Text("Click Repair to fix.")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                } else {
                  Text("The CLI shim and skills are installed and managed automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if pathWarning {
                  VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                      Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.contextifyYellow)
                      Text("~/bin is not on your PATH")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Text("Add to ~/.zshrc or ~/.bashrc:")
                      .font(.caption)
                      .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                      Text("export PATH=\"$HOME/bin:$PATH\"")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(4)

                      Button {
                        "export PATH=\"$HOME/bin:$PATH\"".copyToClipboard()
                      } label: {
                        Image(systemName: "doc.on.doc")
                      }
                      .buttonStyle(.borderless)
                      .help("Copy command")
                    }
                  }
                  .padding(.top, 4)
                }

              case .enabledViaHomebrew(let version):
                HStack(spacing: 6) {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                  Text("Installed via Homebrew (v\(version))")
                    .font(.body)
                }

                Text("The CLI is installed via Homebrew. To upgrade, run:")
                  .font(.caption)
                  .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                  Text("brew upgrade contextify-query")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(4)

                  Button {
                    "brew upgrade contextify-query".copyToClipboard()
                  } label: {
                    Image(systemName: "doc.on.doc")
                  }
                  .buttonStyle(.borderless)
                  .help("Copy command")
                }

              case .upgrading(let from, let to):
                HStack(spacing: 6) {
                  ProgressView()
                    .controlSize(.small)
                  Text("Upgrading from v\(from) to v\(to)...")
                    .font(.body)
                }

              case .failed(let error):
                VStack(alignment: .leading, spacing: 8) {
                  HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                      .foregroundStyle(Color.contextifyYellow)
                    Text("Installation failed")
                      .font(.body)
                  }

                  Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)

                  Text("You can try again or disable CLI features.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
        .listRowBackground(Color.clear)
      }
    }
    .onAppear {
      if !didLogAppear {
        didLogAppear = true
        log.info("[CLI-SETTINGS-TAB-OPEN]")
      }
      coordinator.refreshState()
    }

    Spacer()
  }
  .padding()
  .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Returns user-facing message for repair reason
  private func repairWarningMessage(for reason: CLICoordinator.RepairReason) -> String {
    switch reason {
    case .claudeSkillMissing:
      return "Claude Code skill missing - Total Recall won't work in Claude Code."
    case .codexSkillMissing:
      return "Codex CLI skill missing - Total Recall won't work in Codex CLI."
    case .bothSkillsMissing:
      return "CLI skills missing - Total Recall won't work."
    case .manifestMissing:
      return "Installation incomplete - plugin manifest missing."
    }
  }
}
