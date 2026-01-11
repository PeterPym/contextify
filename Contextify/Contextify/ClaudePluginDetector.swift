import Foundation
import Combine
import ContextifyCore

@MainActor
final class ClaudePluginDetector: ObservableObject {
  struct Status: Equatable {
    var marketplaceAdded: Bool
    var pluginInstalled: Bool
    var canDetect: Bool

    static let unknown = Status(marketplaceAdded: false, pluginInstalled: false, canDetect: false)
  }

  @Published private(set) var status: Status = .unknown

  init() {
    refreshStatus()
  }

  func refreshStatus() {
    // App Store builds cannot access ~/.claude/plugins/ due to sandbox
    guard !Sandbox.isSandboxed else {
      status = .unknown
      return
    }

    let marketplaceAdded = checkMarketplaceAdded()
    let pluginInstalled = checkPluginInstalled()

    status = Status(
      marketplaceAdded: marketplaceAdded,
      pluginInstalled: pluginInstalled,
      canDetect: true
    )
  }

  private func checkMarketplaceAdded() -> Bool {
    let url = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/plugins/known_marketplaces.json")

    guard let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return false
    }

    return json["contextify"] != nil
  }

  private func checkPluginInstalled() -> Bool {
    let url = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/plugins/installed_plugins.json")

    guard let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let plugins = json["plugins"] as? [String: Any] else {
      return false
    }

    return plugins["query@contextify"] != nil
  }
}
