//
//  DebugScrollTestWindow.swift
//  Contextify
//
//  Minimal test window to isolate macOS 15 horizontal ScrollView click bug.
//  This strips away all ProjectSwitcherView complexity to test if Button+ButtonStyle
//  actually works inside a horizontal ScrollView.
//

import SwiftUI
import AppKit
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "DebugScrollTest")

// MARK: - ScrollView-compatible Button Style (same as ProjectSwitcherView)

private struct ScrollViewButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.7 : 1.0)
  }
}

// MARK: - Debug View

struct DebugScrollTestView: View {
  @State private var clickCount = 0
  @State private var lastClickedTab: Int?
  @State private var scrollOffset: CGFloat = 0

  var body: some View {
    let _ = log.info("[DEBUG-SCROLL] View body evaluated, clickCount=\(clickCount)")

    VStack(alignment: .leading, spacing: 16) {
      // Header with status
      VStack(alignment: .leading, spacing: 4) {
        Text("macOS 15 ScrollView Click Test")
          .font(.headline)
        Text("Click count: \(clickCount)  |  Last clicked: \(lastClickedTab.map { "Tab \($0)" } ?? "none")")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal)

      Divider()

      // Instructions
      Text("Click any tab below. Watch Console for [DEBUG-TAP] logs.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)

      // The test subject: horizontal ScrollView with clickable buttons
      ScrollView(.horizontal, showsIndicators: true) {
        HStack(spacing: 12) {
          ForEach(1...15, id: \.self) { i in
            Button {
              log.info("[DEBUG-TAP] ✅ CLICKED Tab \(i) via Button+ScrollViewButtonStyle")
              clickCount += 1
              lastClickedTab = i
            } label: {
              Text("Tab \(i)")
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(lastClickedTab == i ? Color.blue.opacity(0.3) : Color.gray.opacity(0.15))
                .cornerRadius(6)
            }
            .buttonStyle(ScrollViewButtonStyle())
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
          GeometryReader { geo in
            Color.clear
              .onAppear {
                log.info("[DEBUG-SCROLL] ScrollView content appeared, width=\(geo.size.width)")
              }
          }
        )
      }
      .frame(height: 60)
      .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))

      Divider()

      // Additional test: plain HStack (no ScrollView) for comparison
      VStack(alignment: .leading, spacing: 4) {
        Text("Control: Plain HStack (no ScrollView)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal)

        HStack(spacing: 12) {
          ForEach(1...5, id: \.self) { i in
            Button {
              log.info("[DEBUG-TAP-CONTROL] ✅ CLICKED Control \(i) (no ScrollView)")
              clickCount += 1
              lastClickedTab = 100 + i  // Distinguish from ScrollView tabs
            } label: {
              Text("Ctrl \(i)")
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(lastClickedTab == (100 + i) ? Color.green.opacity(0.3) : Color.gray.opacity(0.15))
                .cornerRadius(6)
            }
            .buttonStyle(ScrollViewButtonStyle())
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
      }

      Spacer()

      // Debug info
      VStack(alignment: .leading, spacing: 2) {
        Text("Debug Info:")
          .font(.caption.bold())
        Text("• Look for [DEBUG-TAP] in Console.app")
        Text("• Filter by subsystem: dev.contextify")
        Text("• Category: DebugScrollTest")
      }
      .font(.caption2)
      .foregroundStyle(.tertiary)
      .padding()
    }
    .padding(.top)
    .frame(minWidth: 500, minHeight: 300)
    .onAppear {
      log.info("[DEBUG-SCROLL] ========================================")
      log.info("[DEBUG-SCROLL] Debug window appeared")
      log.info("[DEBUG-SCROLL] macOS version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
      log.info("[DEBUG-SCROLL] Testing: Button + ScrollViewButtonStyle inside horizontal ScrollView")
      log.info("[DEBUG-SCROLL] ========================================")
    }
  }
}

// MARK: - Window Controller

@MainActor
final class DebugScrollTestWindowController {
  static let shared = DebugScrollTestWindowController()

  private var window: NSWindow?

  private init() {}

  func showWindow() {
    if let existing = window, existing.isVisible {
      existing.makeKeyAndOrderFront(nil)
      return
    }

    let hostingView = NSHostingView(rootView: DebugScrollTestView())
    hostingView.frame = NSRect(x: 0, y: 0, width: 550, height: 350)

    let newWindow = NSWindow(
      contentRect: hostingView.frame,
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    newWindow.title = "ScrollView Click Debug"
    newWindow.contentView = hostingView
    newWindow.center()
    newWindow.makeKeyAndOrderFront(nil)

    // Don't retain - let it close naturally
    newWindow.isReleasedWhenClosed = false
    self.window = newWindow

    log.info("[DEBUG-SCROLL] Window opened")
  }
}

// MARK: - Preview

#Preview {
  DebugScrollTestView()
}
