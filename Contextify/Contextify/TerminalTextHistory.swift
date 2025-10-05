import Foundation

@MainActor
final class TerminalTextHistory {
    struct Entry {
        let text: String
        let savedAt: Date
    }

    static let shared = TerminalTextHistory()

    private let maxEntries = 20
    private var entries: [Entry] = []

    private init() {}

    func push(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let first = entries.first, first.text == trimmed {
            return
        }

        entries.insert(Entry(text: trimmed, savedAt: Date()), at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }

    func pop() -> Entry? {
        guard !entries.isEmpty else { return nil }
        return entries.removeFirst()
    }

    func requeue(_ entry: Entry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }

    var hasEntries: Bool { !entries.isEmpty }
}
