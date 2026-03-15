import SwiftUI
import ContextifyCore

struct GeneralSettingsView: View {
  @State private var manager = LaunchAtLoginManager.shared

  var body: some View {
    Form {
      Section("Startup") {
        Toggle("Launch at login", isOn: Binding(
          get: { manager.isEnabled },
          set: { manager.setEnabled($0) }
        ))
        .accessibilityLabel("Launch Contextify at login")
        .accessibilityHint("When enabled, Contextify starts automatically when you log in")

        if let errorMessage = manager.lastErrorMessage {
          HStack {
            Image(systemName: "xmark.circle")
              .foregroundStyle(.red)
            Text(errorMessage)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel("Error: \(errorMessage)")
        }

        if manager.requiresApproval {
          HStack {
            Image(systemName: "exclamationmark.triangle")
              .foregroundStyle(.yellow)
            Text("Contextify needs permission to launch at login.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel("Permission required: Contextify needs approval to launch at login")

          Button("Open Login Items Settings") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
              NSWorkspace.shared.open(url)
            }
          }
          .accessibilityLabel("Open Login Items in System Settings")
        }

        // DMG-only: warn if not in /Applications
        if !Sandbox.isSandboxed {
          let appPath = Bundle.main.bundlePath
          if !appPath.hasPrefix("/Applications") {
            HStack {
              Image(systemName: "info.circle")
                .foregroundStyle(.blue)
              Text("Move Contextify to /Applications for reliable launch at login.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Recommendation: Move Contextify to Applications folder for reliable launch at login")
          }
        }
      }
    }
    .formStyle(.grouped)
    .onAppear { manager.refreshStatus() }
    .accessibilityElement(children: .contain)
  }
}

#Preview {
  GeneralSettingsView()
}
