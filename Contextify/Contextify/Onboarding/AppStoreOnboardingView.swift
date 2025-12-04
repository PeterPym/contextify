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

  private let totalSteps = 2

  var body: some View {
    VStack(spacing: 0) {
      // Header
      header
        .padding(.top, 24)
        .padding(.bottom, 16)

      Divider()

      // Step content
      Group {
        if currentStep == 1 {
          DatabaseLocationStepView(isConfigured: $databaseLocationConfigured)
        } else {
          PermissionsStepView(
            folderAccessController: folderAccessController,
            onComplete: onComplete
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      Divider()

      // Navigation footer
      navigationFooter
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
    }
    .frame(width: 520, height: 560)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear {
      log.info("[ONBOARD-WIZARD] Wizard appeared, step \(currentStep)")
    }
  }

  // MARK: - Header

  private var header: some View {
    VStack(spacing: 12) {
      if let iconName = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
         let appIcon = NSImage(named: iconName) {
        Image(nsImage: appIcon)
          .resizable()
          .frame(width: 64, height: 64)
      }

      Text("Welcome to Contextify")
        .font(.title)
        .fontWeight(.semibold)

      // Step indicator dots
      HStack(spacing: 8) {
        ForEach(1...totalSteps, id: \.self) { step in
          Circle()
            .fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
            .frame(width: 8, height: 8)
        }
      }

      Text(stepTitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var stepTitle: String {
    switch currentStep {
    case 1: return "Step 1: Choose where to store your data"
    case 2: return "Step 2: Grant access to transcript folders"
    default: return ""
    }
  }

  // MARK: - Navigation Footer

  private var navigationFooter: some View {
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

      // Next/Done button
      if currentStep < totalSteps {
        Button("Next") {
          withAnimation {
            currentStep += 1
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!databaseLocationConfigured)
      }
    }
  }
}

#Preview {
  AppStoreOnboardingView(
    folderAccessController: FolderAccessController(),
    onComplete: {}
  )
}
