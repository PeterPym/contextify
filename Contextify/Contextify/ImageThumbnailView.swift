import SwiftUI
import AppKit
import OSLog

private let log = Logger(subsystem: "dev.contextify.timeline", category: "ImageThumbnail")

/// Displays a row of image thumbnails for a timeline entry
struct ImageThumbnailRow: View {
    let images: [ExtractedImage]
    let onTap: (Int) -> Void

    /// Maximum number of thumbnails to show inline
    private let maxVisible = 4
    /// Thumbnail size
    private let thumbnailSize: CGFloat = 48

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(images.prefix(maxVisible).enumerated()), id: \.element.id) { index, image in
                ImageThumbnail(image: image)
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .onTapGesture {
                        log.info("[THUMBNAIL-TAP] Tapped image \(index, privacy: .public) of \(images.count, privacy: .public)")
                        onTap(index)
                    }
            }

            // Show overflow indicator if more images
            if images.count > maxVisible {
                Text("+\(images.count - maxVisible)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture {
                        onTap(maxVisible)
                    }
            }
        }
    }
}

/// A single image thumbnail
@MainActor
struct ImageThumbnail: View {
    let image: ExtractedImage

    var body: some View {
        Group {
            if let nsImage = image.nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Fallback for failed decode
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .help("Click to preview")
    }
}

/// Controller for presenting image preview in a floating panel
@MainActor
final class ImagePreviewPanelController: NSObject, NSWindowDelegate {
    static let shared = ImagePreviewPanelController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<ImagePreviewPanelContent>?

    func show(images: [ExtractedImage], promptText: String?, startIndex: Int) {
        // Close existing panel if any
        close()

        // Create the panel
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Image Preview"
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.9)
        panel.delegate = self  // P1.4: Handle window close via delegate

        // Create content view
        let contentView = ImagePreviewPanelContent(
            images: images,
            promptText: promptText,
            initialIndex: startIndex,
            onClose: { [weak self] in self?.close() }
        )

        let hostingView = NSHostingView(rootView: contentView)
        panel.contentView = hostingView

        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelFrame = panel.frame
            let x = screenFrame.midX - panelFrame.width / 2
            let y = screenFrame.midY - panelFrame.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        self.hostingView = hostingView
    }

    func close() {
        panel?.close()
        panel = nil
        hostingView = nil
    }

    // MARK: - NSWindowDelegate

    /// Clean up references when user closes panel via window chrome (red button)
    /// Guard against race where rapid reopen could cause new panel to be cleared
    nonisolated func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        Task { @MainActor in
            // Only clear if the closing window is the current panel
            guard self.panel === closingWindow else { return }
            self.panel = nil
            self.hostingView = nil
        }
    }
}

/// Content view for the floating image preview panel
@MainActor
struct ImagePreviewPanelContent: View {
    let images: [ExtractedImage]
    let promptText: String?
    let initialIndex: Int
    let onClose: () -> Void

    @State private var selectedIndex: Int
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    /// Maximum characters for prompt text (~2 tweets)
    private let maxPromptLength = 280

    init(images: [ExtractedImage], promptText: String?, initialIndex: Int, onClose: @escaping () -> Void) {
        self.images = images
        self.promptText = promptText
        self.initialIndex = initialIndex
        self.onClose = onClose
        self._selectedIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with close button and counter
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Text("\(selectedIndex + 1) of \(images.count)")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                // Placeholder for symmetry
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .opacity(0)
            }
            .padding()

            // Main image view
            GeometryReader { geometry in
                if selectedIndex < images.count,
                   let nsImage = images[selectedIndex].nsImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = value
                                }
                                .onEnded { _ in
                                    withAnimation(.spring()) {
                                        scale = 1.0
                                        offset = .zero
                                    }
                                }
                        )
                        .simultaneousGesture(  // P2.2: Use simultaneousGesture for zoom/pan compatibility
                            DragGesture()
                                .onChanged { value in
                                    offset = value.translation
                                }
                                .onEnded { _ in
                                    withAnimation(.spring()) {
                                        offset = .zero
                                    }
                                }
                        )
                } else {
                    // Fallback
                    Image(systemName: "photo")
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // Prompt text (if available)
            if let prompt = promptText, !prompt.isEmpty {
                Text(truncatedPrompt(prompt))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }

            // Navigation arrows (only if multiple images)
            if images.count > 1 {
                HStack(spacing: 40) {
                    Button(action: previousImage) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(selectedIndex > 0 ? 0.8 : 0.3))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(selectedIndex == 0)

                    Button(action: nextImage) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(selectedIndex < images.count - 1 ? 0.8 : 0.3))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(selectedIndex >= images.count - 1)
                }
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(Color.black.opacity(0.9))
    }

    private func truncatedPrompt(_ text: String) -> String {
        if text.count <= maxPromptLength {
            return text
        }
        let truncated = String(text.prefix(maxPromptLength - 3))
        return truncated + "..."
    }

    private func previousImage() {
        guard selectedIndex > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedIndex -= 1
            resetZoom()
        }
    }

    private func nextImage() {
        guard selectedIndex < images.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedIndex += 1
            resetZoom()
        }
    }

    private func resetZoom() {
        scale = 1.0
        offset = .zero
    }
}

#Preview("Thumbnail Row") {
    // Create sample images for preview
    let sampleData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header bytes
    let images = [
        ExtractedImage(mediaType: "image/png", data: sampleData),
        ExtractedImage(mediaType: "image/png", data: sampleData),
        ExtractedImage(mediaType: "image/png", data: sampleData)
    ]

    return ImageThumbnailRow(images: images) { index in
        print("Tapped image \(index)")
    }
    .padding()
    .frame(width: 300)
}
