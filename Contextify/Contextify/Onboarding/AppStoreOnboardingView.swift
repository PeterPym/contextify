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

/// Focus states for step 2 (permissions).
/// Tab/Shift+Tab cycles through available items.
enum PermissionsFocus: Equatable {
  case claude
  case codex
  case continueButton
}

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

  /// Trigger to open folder picker from parent (for keyboard shortcut)
  @State private var openFolderPickerTrigger = false

  /// On step 2, tracks which element has keyboard focus.
  /// Tab/Shift+Tab cycles through: Claude → Codex → Continue → Claude...
  @State private var permissionsFocus: PermissionsFocus = .claude

  /// Authorization status for each source (needed to determine available focus targets)
  @State private var authorizations: [SourceID: AuthorizationStatus] = [:]

  /// Trigger for Grant Access action (set by Enter key handler)
  @State private var triggerGrantAccess: SourceID?

  private let totalSteps = 2

  /// Returns the ordered list of focusable items on step 2
  private var availableFocusTargets: [PermissionsFocus] {
    var targets: [PermissionsFocus] = []
    // Claude is focusable if not yet authorized
    if authorizations[.claude] != .authorized {
      targets.append(.claude)
    }
    // Codex is focusable if not yet authorized
    if authorizations[.codex] != .authorized {
      targets.append(.codex)
    }
    // Continue is focusable if at least one permission granted
    if permissionsConfigured {
      targets.append(.continueButton)
    }
    return targets
  }

  /// Move focus to next available target
  private func focusNext() {
    let targets = availableFocusTargets
    guard !targets.isEmpty else { return }
    if let currentIndex = targets.firstIndex(of: permissionsFocus) {
      let nextIndex = (currentIndex + 1) % targets.count
      permissionsFocus = targets[nextIndex]
    } else {
      // Current focus not in available targets, go to first
      permissionsFocus = targets[0]
    }
  }

  /// Move focus to previous available target
  private func focusPrevious() {
    let targets = availableFocusTargets
    guard !targets.isEmpty else { return }
    if let currentIndex = targets.firstIndex(of: permissionsFocus) {
      let prevIndex = (currentIndex - 1 + targets.count) % targets.count
      permissionsFocus = targets[prevIndex]
    } else {
      // Current focus not in available targets, go to last
      permissionsFocus = targets[targets.count - 1]
    }
  }

  /// Handle Enter key press based on current step
  private func handleEnterForCurrentStep() {
    if currentStep == 1 {
      handleEnterStep1()
    } else {
      handleEnterStep2()
    }
  }

  /// Step 1: Enter triggers folder picker or advances to step 2
  private func handleEnterStep1() {
    if databaseLocationConfigured {
      withAnimation { currentStep += 1 }
    } else {
      // Async delay ensures Enter key event is fully consumed before NSOpenPanel appears
      // (otherwise the Enter might dismiss the panel immediately)
      DispatchQueue.main.async {
        self.openFolderPickerTrigger = true
      }
    }
  }

  /// Step 2: Enter triggers focused element
  private func handleEnterStep2() {
    switch permissionsFocus {
    case .claude:
      if authorizations[.claude] != .authorized {
        triggerGrantAccess = .claude
      }
    case .codex:
      if authorizations[.codex] != .authorized {
        triggerGrantAccess = .codex
      }
    case .continueButton:
      if permissionsConfigured {
        onComplete()
      }
    }
  }

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
            selectedFolderName: $selectedFolderName,
            openPickerTrigger: $openFolderPickerTrigger
          )
        } else {
          PermissionsStepView(
            folderAccessController: folderAccessController,
            isConfigured: $permissionsConfigured,
            permissionsFocus: $permissionsFocus,
            authorizations: $authorizations,
            triggerGrantAccess: $triggerGrantAccess
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
    .background(KeyboardHandler(
      isEnabled: true,  // Handle keys on both steps
      onTab: { if currentStep == 2 { focusNext() } },
      onShiftTab: { if currentStep == 2 { focusPrevious() } },
      onEnter: { handleEnterForCurrentStep() }
    ))
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
            .accessibilityIdentifier("onboarding-previous")
          }

          Spacer()

          // Next button (step 1) or Continue button (step 2)
          // Enabled: borderedProminent with brand color (filled, vibrant) + focus ring
          // Disabled: bordered (outline only, visually recedes)
          if currentStep == 1 {
            if databaseLocationConfigured {
              Button("Next") {
                withAnimation { currentStep += 1 }
              }
              .buttonStyle(.borderedProminent)
              .tint(Color.contextifyBlue)
              .modifier(FocusRingStyle(isActive: true))  // Always show ring when enabled
              .accessibilityIdentifier("onboarding-next")
            } else {
              Button("Next") {}
                .buttonStyle(.bordered)
                .disabled(true)
                .accessibilityIdentifier("onboarding-next")
            }
          } else {
            // Continue button - uses focus ring instead of system keyboard shortcut
            // to maintain consistent brand colors
            if permissionsConfigured {
              Button("Continue") { onComplete() }
                .buttonStyle(.borderedProminent)
                .tint(Color.contextifyBlue)
                .modifier(FocusRingStyle(isActive: permissionsFocus == .continueButton))
                .accessibilityIdentifier("onboarding-continue")
            } else {
              Button("Continue") {}
                .buttonStyle(.bordered)
                .disabled(true)
                .accessibilityIdentifier("onboarding-continue")
            }
          }
        }
      }
      .padding(.vertical, 12)
      .padding(.horizontal, 24)
    }
  }

}

// MARK: - Keyboard Handler

/// Monitors for Tab, Shift+Tab, and Enter key presses.
/// Uses NSEvent local monitoring since SwiftUI's .onKeyPress doesn't reliably capture Tab.
private struct KeyboardHandler: NSViewRepresentable {
  let isEnabled: Bool
  let onTab: () -> Void
  let onShiftTab: () -> Void
  let onEnter: () -> Void

  func makeNSView(context: Context) -> NSView {
    let view = KeyboardView()
    view.onTab = onTab
    view.onShiftTab = onShiftTab
    view.onEnter = onEnter
    view.isEnabled = isEnabled
    // Set up monitor immediately - local monitors work at app level, no window needed
    view.setupMonitorIfNeeded()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    guard let view = nsView as? KeyboardView else { return }
    view.onTab = onTab
    view.onShiftTab = onShiftTab
    view.onEnter = onEnter
    view.isEnabled = isEnabled
  }

  @MainActor
  class KeyboardView: NSView {
    var onTab: (() -> Void)?
    var onShiftTab: (() -> Void)?
    var onEnter: (() -> Void)?
    var isEnabled = false
    private var monitor: Any?

    func setupMonitorIfNeeded() {
      guard monitor == nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self = self, self.isEnabled else { return event }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Tab key (keyCode 48)
        if event.keyCode == 48 {
          if flags == .shift {
            self.onShiftTab?()
            return nil  // Consume
          } else if flags.isEmpty {
            self.onTab?()
            return nil  // Consume
          }
        }

        // Enter/Return key (keyCode 36)
        if event.keyCode == 36 && flags.isEmpty {
          self.onEnter?()
          return nil  // Consume
        }

        return event
      }
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      // Backup call in case makeNSView didn't set it up
      if window != nil {
        setupMonitorIfNeeded()
      }
    }

    override func removeFromSuperview() {
      if let monitor = monitor {
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
      }
      super.removeFromSuperview()
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

// MARK: - Focus Ring Style

/// Shows a focus ring around buttons to indicate keyboard focus.
/// Consistent styling across Grant Access and Continue buttons.
private struct FocusRingStyle: ViewModifier {
  let isActive: Bool

  func body(content: Content) -> some View {
    content
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(isActive ? Color.contextifyBlue : Color.clear, lineWidth: 2)
          .padding(-4)
      )
      .animation(.easeInOut(duration: 0.15), value: isActive)
  }
}

#Preview {
  AppStoreOnboardingView(
    folderAccessController: FolderAccessController(),
    onComplete: {}
  )
}
