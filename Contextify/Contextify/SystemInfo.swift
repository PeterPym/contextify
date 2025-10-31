import Foundation
import AppKit

/// Utility for gathering system information for support requests
struct SystemInfo {
  static func gatherSystemInfo() -> String {
    var info: [String] = []

    // macOS version
    let osVersion = ProcessInfo.processInfo.operatingSystemVersion
    let osVersionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
    info.append("macOS Version: \(osVersionString)")

    // Build version
    if let buildVersion = ProcessInfo.processInfo.operatingSystemVersionString
      .components(separatedBy: "Build ")
      .last?
      .trimmingCharacters(in: CharacterSet(charactersIn: ")")) {
      info.append("Build: \(buildVersion)")
    }

    // Architecture
    #if arch(arm64)
    info.append("Architecture: ARM64 (Apple Silicon)")
    #elseif arch(x86_64)
    info.append("Architecture: x86_64 (Intel)")
    #else
    info.append("Architecture: Unknown")
    #endif

    // App version
    if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
      info.append("Contextify Version: \(appVersion)")
    }

    // Build number
    if let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
      info.append("Build Number: \(buildNumber)")
    }

    return info.joined(separator: "\n")
  }

  static func createSupportMailtoURL() -> URL? {
    let recipient = "rob@banagale.com"
    let subject = "Contextify App Support Request"
    let systemInfo = gatherSystemInfo()

    let body = """
    Hello there,

    Your message here

    ---
    System Info:
    \(systemInfo)
    """

    // URL encode the parameters
    guard let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
      return nil
    }

    let mailtoString = "mailto:\(recipient)?subject=\(encodedSubject)&body=\(encodedBody)"
    return URL(string: mailtoString)
  }

  static func openSupportEmail() {
    guard let url = createSupportMailtoURL() else {
      NSLog("Failed to create mailto URL")
      return
    }

    NSWorkspace.shared.open(url)
  }
}
