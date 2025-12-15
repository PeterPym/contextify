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
  @StateObject private var pluginDetector = ClaudePluginDetector()
  @State private var didLogAppear: Bool = false
  @State private var showingSudoSheet: Bool = false
  @State private var isAdvancedExpanded: Bool = false

  private let log = Logger(subsystem: "dev.contextify", category: "QueryCLIInstall")

  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading, spacing: 12) {
          SetupStepCard(title: "Installation Status", state: .neutral) {
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
            } else if installer.status.installedOnPATH != nil {
              Button("Install") {
                log.info("[QUERYCLI-INSTALL-START] mode=dmg action=installRecommended")
                installer.installRecommendedDMG()
              }
              .buttonStyle(.borderedProminent)
              .tint(Color.contextifyBlue)
              .keyboardShortcut(.defaultAction)
              .keyboardShortcut("i", modifiers: [.command, .shift])
            } else {
              Button("Install") {
                log.info("[QUERYCLI-INSTALL-START] mode=dmg action=installRecommended")
                installer.installRecommendedDMG()
              }
              .buttonStyle(.borderedProminent)
              .tint(Color.contextifyBlue)
              .keyboardShortcut(.defaultAction)
              .keyboardShortcut("i", modifiers: [.command, .shift])
            }
          } content: {
            VStack(alignment: .leading, spacing: 8) {
              if installer.status.installedIsOurShim {
                HStack(spacing: 6) {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                  Text("Installed")
                    .font(.body)
                }

                LabeledContent("Install path") {
                  if let path = installer.status.installedOnPATH?.path {
                    PathValueRow(value: path)
                  }
                }
              } else if let path = installer.status.installedOnPATH?.path {
                HStack(spacing: 6) {
                  Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.contextifyYellow)
                  Text("Wrong version installed")
                    .font(.body)
                }

                Text("Click Install to replace with Contextify's version.")
                  .font(.caption)
                  .foregroundStyle(.secondary)

                LabeledContent("Install path") {
                  PathValueRow(value: path)
                }
              } else {
                Text("Not installed")
                  .font(.body)

                Text("Install Contextify's shim so tools can run `contextify-query` reliably.")
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
            EmptyView()
          } content: {
            VStack(alignment: .leading, spacing: 12) {
              if pluginDetector.status.canDetect {
                // DMG build - show status
                if pluginDetector.status.marketplaceAdded && pluginDetector.status.pluginInstalled {
                  HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(.green)
                    Text("Plugin installed")
                      .font(.body)
                  }

                  Text("The Contextify query plugin is ready to use in Claude Code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                  VStack(alignment: .leading, spacing: 12) {
                    // Step 1: Add marketplace
                    VStack(alignment: .leading, spacing: 6) {
                      HStack(spacing: 6) {
                        if pluginDetector.status.marketplaceAdded {
                          Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                          Text("Step 1: Marketplace added")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        } else {
                          Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.contextifyYellow)
                          Text("Step 1: Add marketplace")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        }
                      }

                      if !pluginDetector.status.marketplaceAdded {
                        Text("Run in Claude Code:")
                          .font(.caption)
                          .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                          Text("/plugin marketplace add PeterPym/contextify")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)

                          Button {
                            "/plugin marketplace add PeterPym/contextify".copyToClipboard()
                          } label: {
                            Image(systemName: "doc.on.doc")
                          }
                          .buttonStyle(.borderless)
                          .help("Copy command")
                        }
                      }
                    }

                    // Step 2: Install plugin
                    VStack(alignment: .leading, spacing: 6) {
                      HStack(spacing: 6) {
                        if pluginDetector.status.pluginInstalled {
                          Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                          Text("Step 2: Plugin installed")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        } else if pluginDetector.status.marketplaceAdded {
                          Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.contextifyYellow)
                          Text("Step 2: Install plugin")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        } else {
                          Text("Step 2: Install plugin")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        }
                      }

                      if pluginDetector.status.marketplaceAdded && !pluginDetector.status.pluginInstalled {
                        Text("Run in Claude Code:")
                          .font(.caption)
                          .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                          Text("/plugin install query@contextify")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)

                          Button {
                            "/plugin install query@contextify".copyToClipboard()
                          } label: {
                            Image(systemName: "doc.on.doc")
                          }
                          .buttonStyle(.borderless)
                          .help("Copy command")
                        }
                      } else if !pluginDetector.status.marketplaceAdded {
                        Text("Complete Step 1 first")
                          .font(.caption)
                          .foregroundStyle(.secondary)
                      }
                    }
                  }
                }
              } else {
                // App Store build - static instructions
                Text("Install the Contextify query plugin so Claude Code can run deterministic searches and context windows.")
                  .font(.caption)
                  .foregroundStyle(.secondary)

                Text("Run these commands in Claude Code (one at a time):")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                  HStack(spacing: 8) {
                    Text("/plugin marketplace add PeterPym/contextify")
                      .font(.system(.caption, design: .monospaced))
                      .textSelection(.enabled)
                      .padding(.vertical, 4)
                      .padding(.horizontal, 8)
                      .background(Color(nsColor: .controlBackgroundColor))
                      .cornerRadius(4)

                    Button {
                      "/plugin marketplace add PeterPym/contextify".copyToClipboard()
                    } label: {
                      Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy command")
                  }

                  HStack(spacing: 8) {
                    Text("/plugin install query@contextify")
                      .font(.system(.caption, design: .monospaced))
                      .textSelection(.enabled)
                      .padding(.vertical, 4)
                      .padding(.horizontal, 8)
                      .background(Color(nsColor: .controlBackgroundColor))
                      .cornerRadius(4)

                    Button {
                      "/plugin install query@contextify".copyToClipboard()
                    } label: {
                      Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy command")
                  }
                }
              }
            }
          }

          SetupStepCard(title: "Advanced", state: .neutral) {
            Spacer()
          } content: {
            VStack(alignment: .leading, spacing: 10) {
              Button {
                isAdvancedExpanded.toggle()
              } label: {
                HStack(spacing: 8) {
                  Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isAdvancedExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)

                  Text("Bundled paths")
                    .foregroundStyle(.primary)

                  Spacer()
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)

              if isAdvancedExpanded {
                VStack(alignment: .leading, spacing: 12) {
                  LabeledContent("Bundled CLI:") {
                    PathValueRow(value: installer.status.bundledCLIURL.path)
                  }
                  LabeledContent("Bundled shim:") {
                    PathValueRow(value: installer.status.bundledShimURL.path)
                  }
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
    .sheet(isPresented: $showingSudoSheet) {
      if let sudo = installer.lastSudoCommand {
        CommandSheet(
          title: "Permission Fix",
          subtitle: "Copy and run this command in Terminal:",
          command: sudo
        )
      }
    }
    .onAppear {
      if !didLogAppear {
        didLogAppear = true
        log.info("[QUERYCLI-SETTINGS-TAB-OPEN]")
      }
      installer.refreshStatus()
      pluginDetector.refreshStatus()
    }
    .frame(width: 520)
  }
}
