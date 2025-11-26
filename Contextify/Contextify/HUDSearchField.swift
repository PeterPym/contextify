import SwiftUI
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "HUDSearchField")

/// Search field component for the HUD toolbar
/// - Enter: triggers project-scoped Quick Search
/// - Cmd+Enter: opens Deep Search window (cross-project)
/// - Cmd+F: focuses the search field (via parent binding)
struct HUDSearchField: View {
  @Binding var query: String
  var isFocused: FocusState<Bool>.Binding  // External focus control for Cmd+F
  let onSearch: () -> Void
  let onDeepSearch: () -> Void
  let onClear: () -> Void
  var onQueryChange: (() -> Void)?  // Called when query is edited (to clear stale results)

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
        .font(.system(size: 12))

      TextField("Search", text: $query)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .focused(isFocused)
        .onChange(of: query) { _, _ in
          onQueryChange?()
        }
        .onSubmit {
          if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            onSearch()
          }
        }
        .onKeyPress(.return, phases: .down) { press in
          if press.modifiers.contains(.command) {
            onDeepSearch()
            return .handled
          }
          return .ignored
        }
        .onKeyPress(.escape, phases: .down) { _ in
          if !query.isEmpty {
            onClear()
            return .handled
          }
          return .ignored
        }

      if !query.isEmpty {
        Button {
          onClear()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
            .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .help("Clear search (Esc)")
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(Color(nsColor: .textBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .strokeBorder(isFocused.wrappedValue ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
    )
    .frame(width: 150)
    .help("Search (↩), Deep Search (⌘↩)")
  }
}

struct HUDSearchFieldPreview: View {
  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(spacing: 20) {
      HUDSearchField(
        query: .constant(""),
        isFocused: $isFocused,
        onSearch: {},
        onDeepSearch: {},
        onClear: {}
      )

      HUDSearchField(
        query: .constant("test query"),
        isFocused: $isFocused,
        onSearch: {},
        onDeepSearch: {},
        onClear: {}
      )
    }
    .padding()
    .frame(width: 300)
  }
}

#Preview {
  HUDSearchFieldPreview()
}
