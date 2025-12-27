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

/// Full-screen image preview with navigation
struct ImagePreviewSheet: View {
    let images: [ExtractedImage]
    let promptText: String?
    @Binding var selectedIndex: Int
    @Binding var isPresented: Bool

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    /// Maximum characters for prompt text (~2 tweets)
    private let maxPromptLength = 280

    var body: some View {
        ZStack {
            // Dark background - tap to dismiss
            Color.black.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(spacing: 0) {
                // Header with close button and counter - draggable area
                WindowDragArea {
                    HStack {
                        Button(action: { isPresented = false }) {
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
                    .background(Color.black.opacity(0.01)) // Ensure hit testing works
                }

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
                            .gesture(
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
        }
        .frame(minWidth: 600, minHeight: 400)
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

/// A view that enables window dragging when the user drags within it
struct WindowDragArea<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .background(WindowDragGesture())
    }
}

/// NSViewRepresentable that enables window dragging
private struct WindowDragGesture: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = WindowDragView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Custom NSView that initiates window drag on mouse down
private class WindowDragView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override var mouseDownCanMoveWindow: Bool { true }
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
