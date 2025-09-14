import SwiftUI
import UniformTypeIdentifiers

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
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            Task { await handle(providers) }
            return true
        }
    }

    @MainActor
    private func handle(_ providers: [NSItemProvider]) async {
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let item = try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier), let url = item as? URL {
                await model.ingest(.file(url))
            }
        }
    }
}

