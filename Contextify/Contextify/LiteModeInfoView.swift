//
//  LiteModeInfoView.swift
//  Contextify
//
//  Standalone modal for lite mode information (shown on subsequent launches)
//

import SwiftUI
import ContextifyCore

/// Information modal shown to lite mode users on subsequent launches.
///
/// This view is separate from WelcomeModal to avoid sheet stacking conflicts.
/// - First launch: Lite mode callout appears in WelcomeModal
/// - Subsequent launches: This standalone modal appears (if not dismissed)
///
/// The modal has a "Don't show again" checkbox that is checked by default,
/// so users only see this once unless they explicitly uncheck it.
struct LiteModeInfoView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var dontShowAgain = true  // Checked by default

  var body: some View {
    VStack(spacing: 24) {
      // Header
      VStack(spacing: 12) {
        Image(systemName: "sparkles")
          .font(.system(size: 48))
          .foregroundStyle(.secondary)

        Text("Lite Mode")
          .font(.title2)
          .fontWeight(.semibold)
      }

      // Body
      VStack(spacing: 16) {
        Text("Contextify is running in Lite Mode because Apple Intelligence is not available on this version of macOS.")
          .multilineTextAlignment(.center)

        Text("Your conversations are being saved and indexed. AI-powered summaries will appear as you browse when you upgrade to macOS 26 (Tahoe).")
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      Divider()

      // Checkbox + dismiss
      VStack(spacing: 16) {
        Toggle("Don't show this again", isOn: $dontShowAgain)
          .toggleStyle(.checkbox)

        Button("Continue") {
          if dontShowAgain {
            HUDPreferences.setLiteModeInfoDismissed(true)
          }
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(32)
    .frame(width: 400)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

#Preview {
  LiteModeInfoView()
}
