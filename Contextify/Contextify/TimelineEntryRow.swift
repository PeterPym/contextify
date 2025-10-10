import SwiftUI
import AppKit

extension Notification.Name {
    static let revealTranscript = Notification.Name("revealTranscript")
}

struct TimelineEntryRow: View {
    let entry: TimelineEntry
    let allEntries: [TimelineEntry]
    let onScrollToEntry: (UUID) -> Void

    @State private var isExpanded = false
    @State private var showCopiedToast = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Text(entry.summary)
                .font(.callout)
                .foregroundStyle(.primary)

            if isExpanded {
                Divider()
                Text(entry.detail)
                    .font(.caption)
                    .textSelection(.enabled)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(alignment: .leading) {
            Capsule()
                .fill(entry.isError ? .red : entry.kind.accentColor)
                .frame(width: 3)
                .padding(.vertical, 4)
        }
        .overlay(alignment: .topTrailing) {
            if showCopiedToast {
                Label("Copied", systemImage: "checkmark")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.opacity)
                    .offset(x: -4, y: 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
        .contextMenu {
            Button("Copy Markdown Snippet") { copy(entry.markdownPayload()) }
            Button("Copy Summary") { copy(entry.summary) }
            Button("Copy Detail") { copy(entry.detail) }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Use provider-specific icon for system messages, default icon for others
            if entry.kind == .system, let provider = entry.sourceContext?.provider {
                Image(provider.iconImage)
                    .renderingMode(.template)
                    .foregroundStyle(providerColor(provider))
            } else {
                Image(systemName: entry.kind.iconName)
                    .foregroundStyle(entry.kind.accentColor)
            }
            Text(entry.timestamp, format: .dateTime.hour().minute())
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            if entry.isDirective {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.caption)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("User directive")
            } else if entry.isCompletion {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Task completed")

                if let duration = calculateDuration() {
                    Text(duration)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                if let requestId = entry.requestId {
                    Button(action: { onScrollToEntry(requestId) }) {
                        Image(systemName: "arrow.up.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Jump to original request")
                }
            }
            Spacer()
            if case .revealInInventory = entry.action {
                Button(action: revealInInventory) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Reveal in transcript inventory")
            }
            Button(action: { copy(entry.markdownPayload()) }) {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Copy markdown snippet")
        }
    }

    private func calculateDuration() -> String? {
        guard let requestId = entry.requestId,
              let requestEntry = allEntries.first(where: { $0.id == requestId }) else {
            return nil
        }

        let duration = entry.timestamp.timeIntervalSince(requestEntry.timestamp)
        guard duration > 0 else { return nil }

        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60

        if minutes > 0 {
            return "(\(minutes)m \(seconds)s)"
        } else {
            return "(\(seconds)s)"
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.easeInOut(duration: 0.25)) {
            showCopiedToast = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeInOut(duration: 0.25)) {
                showCopiedToast = false
            }
        }
    }

    private func revealInInventory() {
        guard case .revealInInventory(let transcriptPath) = entry.action else { return }

        // Open the inventory window
        openWindow(id: "transcript-inventory")

        // Post notification to select the transcript
        NotificationCenter.default.post(
            name: .revealTranscript,
            object: nil,
            userInfo: ["path": transcriptPath]
        )
    }

    private func providerColor(_ provider: TimelineSourceContext.Provider) -> Color {
        switch provider {
        case .claudeCode: return .orange
        case .codexCLI: return .blue
        case .other: return .gray
        }
    }
}

private extension TimelineEntryKind {
    var accentColor: Color {
        switch self {
        case .user: return .blue
        case .assistant: return .purple
        case .system: return .gray
        }
    }

    var iconName: String {
        switch self {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        case .system: return "gearshape"
        }
    }
}
