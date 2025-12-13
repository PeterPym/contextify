//
//  TranscriptDetailView.swift
//  Contextify
//
//  Detail view for displaying transcript metadata and content in the inventory window.
//  Extracted from TranscriptInventoryView.swift for better code organization.
//

import SwiftUI
import ContextifyCore
import OSLog

/// Displays detailed information for a selected transcript session
///
/// Shows:
/// - LLM-generated metadata (title, description, topics)
/// - File information (path, size, lines)
/// - v7 metadata (file snapshots, system events, usage statistics)
/// - Actions (reveal in Finder, open in editor, copy path)
struct TranscriptDetailView: View {
  let session: TranscriptSession
  let isActive: Bool
  let onMetadataUpdate: ((String, TranscriptMetadata) -> Void)?  // Changed from URL to transcript ID
  let orchestrator: TranscriptOrchestrator?

  @State private var metadata: TranscriptMetadata?
  @State private var isRegenerating = false

  // v7 Metadata
  @State private var fileSnapshots: [FileSnapshot] = []
  @State private var systemEvents: [SystemEvent] = []
  @State private var usageStats: UsageAggregate?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Header with status badge
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            // Use metadata title if available, otherwise fall back to identifier
            Text(metadata?.title ?? session.identifier)
              .font(.title2)
              .fontWeight(.semibold)

            // Show description if available, otherwise show provider + filename
            if let meta = metadata, !meta.description.isEmpty {
              Text(meta.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            } else {
              Text("\(providerName) • \(session.fileURL.lastPathComponent)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          }

          Spacer()

          // v23: Active pill
          if isActive {
            Label("Active", systemImage: "circle.fill")
              .font(.caption)
              .foregroundStyle(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 4)
              .background(Color.green)
              .clipShape(Capsule())
          }
        }

        Divider()

        // Transcript Details (File Info + LLM metadata if available)
        VStack(alignment: .leading, spacing: 12) {
          Text("Transcript Details")
            .font(.headline)

          // Include Title and Description from LLM metadata if available
          if let meta = metadata {
            metadataRow(label: "Title", value: meta.title)
            metadataRow(label: "Description", value: meta.description)
          }

          metadataRow(label: "Last Modified", value: formattedDate(session.lastActivity))

          // File Path with Finder reveal button
          HStack(alignment: .top) {
            Text("File Path")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .frame(width: 100, alignment: .leading)

            Text(session.fileURL.path)
              .font(.subheadline)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)

            Button {
              NSWorkspace.shared.selectFile(session.fileURL.path, inFileViewerRootedAtPath: "")
            } label: {
              Image(systemName: "folder")
                .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
          }

          metadataRow(label: "File Name", value: session.fileURL.lastPathComponent)
          metadataRow(label: "Provider", value: providerName)

          if let fileSize = fileSize() {
            metadataRow(label: "File Size", value: fileSize)
          }

          if let lineCount = lineCount() {
            metadataRow(label: "Lines", value: "\(lineCount)")
          }
        }

        Divider()

        // AI-Generated Metadata
        if let meta = metadata {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("AI Summary")
                .font(.headline)

              if meta.needsReview {
                Text("Needs Review")
                  .font(.caption)
                  .foregroundStyle(.white)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 2)
                  .background(Color.orange)
                  .clipShape(Capsule())
              }

              if meta.promptVersion < 2 {
                Text("Stale")
                  .font(.caption)
                  .foregroundStyle(.white)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 2)
                  .background(Color.yellow)
                  .clipShape(Capsule())
              }

              Spacer()

              if !isLiteModeActive() {
                Button {
                  Task {
                    await regenerateMetadata()
                  }
                } label: {
                  HStack(spacing: 4) {
                    if isRegenerating {
                      ProgressView()
                        .controlSize(.mini)
                        .frame(width: 10, height: 10)
                    } else {
                      Image(systemName: "arrow.clockwise")
                    }
                    Text("Regenerate")
                  }
                  .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(isRegenerating)
              }
            }

            HStack(alignment: .top) {
              Text("Topics")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

              HStack(spacing: 6) {
                ForEach(meta.topics, id: \.self) { topic in
                  Text(topic)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
                }
              }
            }

            metadataRow(label: "Confidence", value: String(format: "%.2f", meta.confidence))
            metadataRow(label: "Generated", value: formattedDate(meta.generatedAt))
            metadataRow(label: "Strategy", value: meta.strategy)
            metadataRow(label: "Model", value: meta.model)
            metadataRow(label: "Messages", value: "\(meta.messageCount)")
            metadataRow(label: "Latency", value: "\(meta.latencyMs)ms")
          }

          Divider()
        } else {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("AI Summary")
                .font(.headline)
              Spacer()
              if !isLiteModeActive() {
                ProgressView()
                  .controlSize(.mini)
                  .frame(width: 10, height: 10)
              }
            }
            if isLiteModeActive() {
              Text("Lite Mode: \(LLMAvailability.current.reasonText)")
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
              Text("Generating metadata…")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          Divider()
        }

        // File Activity (v7 metadata)
        if !fileSnapshots.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text("File Activity")
              .font(.headline)

            metadataRow(label: "Snapshots", value: "\(fileSnapshots.count)")

            if let firstSnapshot = fileSnapshots.first {
              metadataRow(label: "Last Snapshot", value: formattedTimestamp(firstSnapshot.snapshotTimestamp))
            }

            // Show most recent snapshot details
            if let snapshot = fileSnapshots.first {
              // Get tracked files for this snapshot
              if let orchestrator = orchestrator,
                 let trackedFiles = try? orchestrator.getTrackedFiles(snapshotId: snapshot.id),
                 !trackedFiles.isEmpty {
                metadataRow(label: "Tracked Files", value: "\(trackedFiles.count)")

                // Show file list (limited to 5)
                VStack(alignment: .leading, spacing: 4) {
                  ForEach(trackedFiles.prefix(5), id: \.id) { file in
                    HStack {
                      Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                      Text(file.filePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                      Spacer()
                      Text("v\(file.version)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    }
                  }

                  if trackedFiles.count > 5 {
                    Text("+ \(trackedFiles.count - 5) more files")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                }
              }
            }
          }

          Divider()
        }

        // Usage Statistics (v7 metadata)
        if let stats = usageStats, stats.messageCount > 0 {
          VStack(alignment: .leading, spacing: 12) {
            Text("Usage Statistics")
              .font(.headline)

            metadataRow(label: "Messages", value: "\(stats.messageCount)")
            metadataRow(label: "Input Tokens", value: formatNumber(stats.totalInputTokens))
            metadataRow(label: "Output Tokens", value: formatNumber(stats.totalOutputTokens))

            if stats.totalCacheCreation > 0 {
              metadataRow(label: "Cache Creation", value: formatNumber(stats.totalCacheCreation))
            }

            if stats.totalCacheRead > 0 {
              metadataRow(label: "Cache Read", value: formatNumber(stats.totalCacheRead))
            }

            let totalTokens = stats.totalInputTokens + stats.totalOutputTokens +
                              stats.totalCacheCreation + stats.totalCacheRead
            metadataRow(label: "Total Tokens", value: formatNumber(totalTokens))
          }

          Divider()
        }

        // System Events (v7 metadata)
        if !systemEvents.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text("System Events")
              .font(.headline)

            metadataRow(label: "Total Events", value: "\(systemEvents.count)")

            // Count errors
            let errorCount = systemEvents.filter { $0.level == "error" }.count
            if errorCount > 0 {
              metadataRow(label: "Errors", value: "\(errorCount)")
            }

            // Show recent events (limited to 5)
            VStack(alignment: .leading, spacing: 6) {
              ForEach(systemEvents.prefix(5), id: \.id) { event in
                HStack(alignment: .top, spacing: 8) {
                  // Level indicator
                  Image(systemName: eventIcon(event.level))
                    .font(.caption)
                    .foregroundStyle(eventColor(event.level))
                    .frame(width: 12)

                  VStack(alignment: .leading, spacing: 2) {
                    Text(event.subtype)
                      .font(.caption)
                      .fontWeight(.medium)

                    if let content = event.content {
                      Text(content)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    }

                    if let error = event.error {
                      Text("Error: \(error)")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                    }

                    Text(formattedTimestamp(event.timestamp))
                      .font(.system(size: 9))
                      .foregroundStyle(.tertiary)
                  }

                  Spacer()
                }
                .padding(.vertical, 4)
              }

              if systemEvents.count > 5 {
                Text("+ \(systemEvents.count - 5) more events")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }

          Divider()
        }

        // Actions
        VStack(spacing: 8) {
          Button {
            NSWorkspace.shared.selectFile(session.fileURL.path, inFileViewerRootedAtPath: "")
          } label: {
            Label("Reveal in Finder", systemImage: "folder")
              .frame(maxWidth: .infinity)
          }

          Button {
            NSWorkspace.shared.open(session.fileURL)
          } label: {
            Label("Open in Default Editor", systemImage: "doc.text")
              .frame(maxWidth: .infinity)
          }

          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.fileURL.path, forType: .string)
          } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.bordered)
      }
      .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task(id: session.identifier) {  // Changed from fileURL to identifier
      // Reset state when session changes to prevent showing stale data
      metadata = nil
      fileSnapshots = []
      systemEvents = []
      usageStats = nil

      // Load metadata on appearance or when session changes
      await loadMetadata()
      await loadV7Metadata()
    }
    .onReceive(NotificationCenter.default.publisher(for: .transcriptMetadataUpdated)) { notification in
      // Reload metadata when generation completes
      guard let completedId = notification.object as? String,
            completedId == session.identifier else { return }

      Task {
        await loadMetadata()
      }
    }
  }

  // MARK: - Data Loading

  @MainActor
  private func loadMetadata() async {
    // Load from SQL backend
    guard let orchestrator = orchestrator else {
      return
    }

    // Check SQL cache first
    if let record = try? orchestrator.getMetadata(forTranscript: session.identifier) {
      metadata = record.toUIModel()
    } else {
      // Not in cache, trigger generation
      do {
        metadata = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(for: session)
      } catch {
        // Failed to generate, metadata stays nil
      }
    }
  }

  @MainActor
  private func regenerateMetadata() async {
    isRegenerating = true
    defer { isRegenerating = false }

    do {
      let newMetadata = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(
        for: session,
        forceRegenerate: true
      )
      metadata = newMetadata

      // Notify parent view to update list (using transcript ID)
      onMetadataUpdate?(session.identifier, newMetadata)
    } catch {
      // Failed to regenerate, keep existing metadata
    }
  }

  @MainActor
  private func loadV7Metadata() async {
    guard let orchestrator = orchestrator else { return }

    do {
      // Load file snapshots
      fileSnapshots = try orchestrator.getFileSnapshots(transcriptId: session.identifier)

      // Load system events (limit to recent 50)
      systemEvents = try orchestrator.getSystemEvents(transcriptId: session.identifier, limit: 50)

      // Load usage statistics
      usageStats = try orchestrator.getTranscriptUsageStats(transcriptId: session.identifier)
    } catch {
      // Failed to load v7 metadata, keep empty arrays
    }
  }

  // MARK: - Helper Views

  @ViewBuilder
  private func metadataRow(label: String, value: String) -> some View {
    HStack(alignment: .top) {
      Text(label)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(width: 100, alignment: .leading)

      Text(value)
        .font(.subheadline)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: - Computed Properties

  private var providerName: String {
    switch session.provider {
    case .claudeCode: return "Claude Code"
    case .codexCLI: return "Codex CLI"
    case .other: return "Other"
    }
  }

  // MARK: - Formatting Helpers

  private func formattedDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  private func fileSize() -> String? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: session.fileURL.path),
          let size = attrs[.size] as? Int64 else {
      return nil
    }

    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
  }

  private func lineCount() -> Int? {
    // Use database entry count instead of reading the entire file
    guard let orch = orchestrator else { return nil }

    // Use session identifier directly (it's already the database transcript ID)
    let transcriptId = session.identifier

    do {
      let entries = try orch.getEntries(forTranscript: transcriptId, afterTimestamp: nil)
      return entries.count
    } catch {
      return nil
    }
  }

  // v7 Metadata Helpers

  private func formattedTimestamp(_ timestamp: Int) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  private func formatNumber(_ number: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
  }

  private func eventIcon(_ level: String) -> String {
    switch level.lowercased() {
    case "error": return "exclamationmark.circle.fill"
    case "warning": return "exclamationmark.triangle.fill"
    case "info": return "info.circle.fill"
    default: return "circle.fill"
    }
  }

  private func eventColor(_ level: String) -> Color {
    switch level.lowercased() {
    case "error": return .red
    case "warning": return .orange
    case "info": return .blue
    default: return .secondary
    }
  }
}
