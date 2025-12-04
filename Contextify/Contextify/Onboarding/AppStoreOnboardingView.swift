//
//  AppStoreOnboardingView.swift
//  Contextify
//
//  Two-step onboarding wizard for App Store builds.
//  Ensures users select a database location and grant transcript permissions
//  before the app can proceed.
//

import SwiftUI
import ContextifyCore
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "Onboarding")

/// Container view for the App Store onboarding wizard.
/// Displays two steps: Database Location and Permissions.
struct AppStoreOnboardingView: View {
  @ObservedObject var folderAccessController: FolderAccessController
  let onComplete: () -> Void

  @State private var currentStep: Int = 1
  @State private var databaseLocationConfigured = false
  @State private var selectedPath: String?
  @State private var selectedFolderName: String?
  @State private var permissionsConfigured = false

  private let totalSteps = 2

  var body: some View {
    VStack(spacing: 0) {
      // Header with icon and welcome text
      header
        .padding(.top, 16)
        .padding(.bottom, 12)

      // Divider below header
      Divider()
        .padding(.horizontal, 32)

      // Step content
      Group {
        if currentStep == 1 {
          DatabaseLocationStepView(
            isConfigured: $databaseLocationConfigured,
            selectedPath: $selectedPath,
            selectedFolderName: $selectedFolderName
          )
        } else {
          PermissionsStepView(
            folderAccessController: folderAccessController,
            isConfigured: $permissionsConfigured
          )
        }
      }

      // Bottom navigation bar
      bottomBar
    }
    .frame(width: 520)
    .fixedSize(horizontal: false, vertical: true)
    .background(Color(nsColor: .windowBackgroundColor))
    .background(OnboardingWindowConfigurator())
    .onAppear {
      log.info("[ONBOARD-WIZARD] Wizard appeared, step \(currentStep)")
    }
  }

  // MARK: - Header

  private var header: some View {
    VStack(spacing: 12) {
      // App icon
      if let appIcon = NSApp.applicationIconImage {
        Image(nsImage: appIcon)
          .resizable()
          .frame(width: 64, height: 64)
      }

      // Welcome text only - no step indicator or subtitle
      Text("Welcome to Contextify")
        .font(.title)
        .fontWeight(.semibold)
    }
  }

  // MARK: - Bottom Bar

  private var bottomBar: some View {
    VStack(spacing: 0) {
      Divider()

      ZStack {
        // Progress dots (truly centered)
        HStack(spacing: 8) {
          ForEach(1...totalSteps, id: \.self) { step in
            Circle()
              .fill(step == currentStep ? Color.contextifyBlue : Color.secondary.opacity(0.3))
              .frame(width: 8, height: 8)
          }
        }

        // Buttons aligned to edges
        HStack {
          // Previous button (only on step 2)
          if currentStep > 1 {
            Button("Previous") {
              withAnimation {
                currentStep -= 1
              }
            }
            .buttonStyle(.bordered)
          }

          Spacer()

          // Next button (step 1) or Continue button (step 2)
          if currentStep == 1 {
            Button("Next") {
              withAnimation {
                currentStep += 1
              }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.contextifyBlue)
            .disabled(!databaseLocationConfigured)
          } else {
            Button("Continue") {
              onComplete()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.contextifyBlue)
            .disabled(!permissionsConfigured)
          }
        }
      }
      .padding(.vertical, 12)
      .padding(.horizontal, 24)
    }
  }

}

// MARK: - Onboarding Window Configurator

/// Configures the onboarding window chrome: disables minimize/zoom, hides title
private struct OnboardingWindowConfigurator: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      if let window = view.window {
        configureWindow(window)
      }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      if let window = nsView.window {
        configureWindow(window)
      }
    }
  }

  private func configureWindow(_ window: NSWindow) {
    // Remove window title
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = false

    // Disable all traffic light buttons - this is a mandatory wizard
    window.standardWindowButton(.closeButton)?.isEnabled = false
    window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
    window.standardWindowButton(.zoomButton)?.isEnabled = false

    // Prevent resizing
    window.styleMask.remove(.resizable)

    // Set explicit content size to prevent Window scene from using cached size
    window.setContentSize(NSSize(width: 520, height: 380))
  }
}

#Preview {
  AppStoreOnboardingView(
    folderAccessController: FolderAccessController(),
    onComplete: {}
  )
}
