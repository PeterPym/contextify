import SwiftUI
import UniformTypeIdentifiers
import OSLog

struct IngestDropZone: View {
    @Environment(HUDViewModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary, style: StrokeStyle(lineWidth: 2, dash: [6]))
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 28))
                Text("Drag a file here or paste a URL above").foregroundStyle(.secondary)
            }
        }
        .frame(height: 140)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task { await handle(providers) }
            return true
        }
    }

    @MainActor
    private func handle(_ providers: [NSItemProvider]) async {
        let logger = Logger(subsystem: "dev.contextify.app", category: "Drop")
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = await loadFileURL(from: p) {
                await model.ingest(.file(url))
            } else {
                logger.error("Failed to resolve dropped item as file URL")
            }
        }
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            // Prefer a file representation when available
            provider.loadFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { url, _ in
                if let url { cont.resume(returning: url) }
                else {
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        if let u = item as? URL { cont.resume(returning: u) }
                        else if let data = item as? Data, let s = String(data: data, encoding: .utf8), let u = URL(string: s) {
                            cont.resume(returning: u)
                        } else {
                            cont.resume(returning: nil)
                        }
                    }
                }
            }
        }
    }
}
