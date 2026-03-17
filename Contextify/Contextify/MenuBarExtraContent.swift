import SwiftUI
import Observation
import ContextifyCore

@MainActor
@Observable
final class MenuBarActivityModel {
  static let shared = MenuBarActivityModel()

  private(set) var backgroundIngestMessage: String?
  @ObservationIgnored private var backgroundObservationTask: Task<Void, Never>?

  private init() {}

  func start() {
    guard backgroundObservationTask == nil else { return }

    backgroundObservationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      let stream = NotificationCenter.default.notifications(named: .backgroundIngestProgress)
      for await note in stream {
        guard
          let total = note.userInfo?["total"] as? Int,
          let remaining = note.userInfo?["remaining"] as? Int
        else { continue }

        if total <= 0 || remaining <= 0 {
          self.backgroundIngestMessage = nil
          continue
        }

        let completed = total - remaining
        let current = completed + 1
        self.backgroundIngestMessage = "Indexing \(current)/\(total) projects..."
      }
    }
  }
}
