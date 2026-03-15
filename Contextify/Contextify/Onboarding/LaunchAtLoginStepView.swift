//
//  LaunchAtLoginStepView.swift
//  Contextify
//
//  Step 3 of the App Store onboarding wizard.
//  Offers the user the option to enable launch at login.
//  This step is optional -- the user can skip it.
//

import SwiftUI
import ContextifyCore
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "Onboarding")

/// Step 3: Launch at login opt-in.
/// The user can enable or skip this step. It does not block wizard completion.
struct LaunchAtLoginStepView: View {
  @State private var manager = LaunchAtLoginManager.shared

  var body: some View {
    VStack(spacing: 16) {
      Spacer()

      VStack(spacing: 8) {
        Image(systemName: "sunrise")
          .font(.system(size: 36))
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)

        Text("Launch at Login")
          .font(.headline)

        Text("Contextify can start automatically when you log in, so your project timeline is always ready.")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 380)
      }

      Toggle("Launch Contextify at login", isOn: Binding(
        get: { manager.isEnabled },
        set: { manager.setEnabled($0) }
      ))
      .toggleStyle(.switch)
      .padding(.horizontal, 40)
      .accessibilityLabel("Launch Contextify at login")
      .accessibilityHint("When enabled, Contextify starts automatically when you log in")

      if manager.requiresApproval {
        HStack(spacing: 6) {
          Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(.yellow)
          Text("Permission needed. Open System Settings to allow Contextify in Login Items.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Permission required: Open System Settings to allow Contextify in Login Items")
      }

      Spacer()
    }
    .padding(.horizontal, 32)
    .padding(.vertical, 16)
    .onAppear {
      manager.refreshStatus()
      log.info("[ONBOARD-STEP3] Launch at login step appeared, status: \(String(describing: manager.status), privacy: .public)")
    }
  }
}

#Preview {
  LaunchAtLoginStepView()
}
