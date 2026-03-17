import SwiftUI
import ContextifyCore

struct GeneralSettingsView: View {
  @State private var manager = LaunchAtLoginManager.shared
  @AppStorage(HUDPreferences.menuBarExtraEnabledKey, store: ContextifyDefaults.shared)
  private var menuBarExtraEnabled = false
  @AppStorage(HUDPreferences.backgroundUtilityModeEnabledKey, store: ContextifyDefaults.shared)
  private var backgroundUtilityModeEnabled = false

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

      Section("App Presence") {
        Toggle("Show menu bar extra", isOn: Binding(
          get: { menuBarExtraEnabled || backgroundUtilityModeEnabled },
          set: { newValue in
            HUDPreferences.setMenuBarExtraEnabled(newValue)
            menuBarExtraEnabled = HUDPreferences.isMenuBarExtraEnabled()
            AppPresentationController.shared.refreshActivationPolicy()
          }
        ))
        .disabled(backgroundUtilityModeEnabled)
        .accessibilityIdentifier("general-menu-bar-extra-toggle")
        .accessibilityLabel("Show menu bar extra")
        .accessibilityHint("Keeps Contextify available from the menu bar")

        Toggle("Run as background utility", isOn: Binding(
          get: { backgroundUtilityModeEnabled },
          set: { newValue in
            HUDPreferences.setBackgroundUtilityModeEnabled(newValue)
            backgroundUtilityModeEnabled = HUDPreferences.isBackgroundUtilityModeEnabled()
            menuBarExtraEnabled = HUDPreferences.isMenuBarExtraEnabled()
            AppPresentationController.shared.refreshActivationPolicy()
          }
        ))
        .accessibilityIdentifier("general-background-utility-toggle")
        .accessibilityLabel("Run as background utility")
        .accessibilityHint("Hides Dock and Command-Tab presence while keeping Contextify running in the menu bar")

        Text("The menu bar extra gives quick access to Contextify when the main window is closed.")
          .font(.caption)
          .foregroundStyle(.secondary)

        Text(
          backgroundUtilityModeEnabled
            ? "Background utility mode is on. Contextify stays reachable from the menu bar while Dock and Command-Tab presence stay hidden."
            : "Background utility mode keeps Contextify running without a Dock or Command-Tab presence. Turning it on automatically keeps the menu bar extra available."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("general-background-utility-status")
      }
    }
    .formStyle(.grouped)
    .onAppear {
      manager.refreshStatus()
      menuBarExtraEnabled = HUDPreferences.isMenuBarExtraEnabled()
      backgroundUtilityModeEnabled = HUDPreferences.isBackgroundUtilityModeEnabled()
    }
    .accessibilityElement(children: .contain)
  }
}

#Preview {
  GeneralSettingsView()
}
