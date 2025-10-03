import Foundation
import OSLog

@MainActor
enum ComposeURLRouter {
  private static let log = Logger(subsystem: "dev.contextify", category: "URL")
  private static let acceptedSchemes: Set<String> = ["contextify", "contextify-dev"]

  static func handle(_ url: URL) {
    guard let scheme = url.scheme, acceptedSchemes.contains(scheme) else { return }

    let path = (url.host ?? "") + url.path
    guard path.hasPrefix("compose") || path.hasSuffix("/compose") else { return }

    var initialText = ""
    var title = "Compose"
    var tmpFilePath: String?
    var sendOnSubmit = true

    if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
       let items = components.queryItems {
      for item in items {
        switch item.name {
        case "text":
          initialText = (item.value ?? "").removingPercentEncoding ?? ""
        case "text64":
          if let value = item.value,
             let data = Data(base64Encoded: value),
             let decoded = String(data: data, encoding: .utf8) {
            initialText = decoded
          }
        case "title":
          title = (item.value ?? "Compose").removingPercentEncoding ?? "Compose"
        case "tmpfile":
          tmpFilePath = (item.value ?? "").removingPercentEncoding
        case "send":
          sendOnSubmit = (item.value ?? "true").lowercased() != "false"
        default:
          break
        }
      }
    }

    log.info(
      "OpenURL compose title=\(title, privacy: .public) tmpfile=\(tmpFilePath ?? "-", privacy: .public) initial.len=\(initialText.count, privacy: .public)"
    )

    ComposePresenter.present(
      initialText: initialText,
      title: title,
      tmpFilePath: tmpFilePath,
      sendToITermOnSubmit: sendOnSubmit
    )
  }
}
