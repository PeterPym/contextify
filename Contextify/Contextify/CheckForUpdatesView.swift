//
//  CheckForUpdatesView.swift
//  Contextify
//
//  Menu item for checking for updates via Sparkle.
//  This file is compiled only when SPARKLE is defined (DMG builds).
//

#if SPARKLE
import SwiftUI
import Sparkle
import Combine

/// Menu button that triggers Sparkle update check
struct CheckForUpdatesView: View {
  @ObservedObject private var viewModel: CheckForUpdatesViewModel
  private let updater: SPUUpdater

  init(updater: SPUUpdater) {
    self.updater = updater
    self.viewModel = CheckForUpdatesViewModel(updater: updater)
  }

  var body: some View {
    Button("Check for Updates...") {
      updater.checkForUpdates()
    }
    .disabled(!viewModel.canCheckForUpdates)
  }
}

/// ViewModel that observes Sparkle's canCheckForUpdates state
final class CheckForUpdatesViewModel: ObservableObject {
  @Published var canCheckForUpdates = false

  init(updater: SPUUpdater) {
    updater.publisher(for: \.canCheckForUpdates)
      .assign(to: &$canCheckForUpdates)
  }
}
#endif
