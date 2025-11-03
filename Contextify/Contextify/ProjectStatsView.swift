import SwiftUI
import ContextifyCore
import Charts

/// Detailed statistics view for a project
struct ProjectStatsView: View {
  let project: DiscoveredProject
  @Environment(\.dismiss) private var dismiss

  @State private var stats: ProjectStatistics?
  @State private var timeline: [Date: Int] = [:]
  @State private var isLoading = true
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(project.name)
            .font(.title.bold())

          Text(project.path.path)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }

        Spacer()

        Button("Done") {
          dismiss()
        }
        .buttonStyle(.borderedProminent)
      }
      .padding()

      Divider()

      // Content
      if isLoading {
        VStack {
          Spacer()
          ProgressView()
          Text("Loading statistics...")
            .foregroundStyle(.secondary)
          Spacer()
        }
      } else if let error = errorMessage {
        VStack(spacing: 16) {
          Spacer()

          Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 48))
            .foregroundStyle(.orange)

          Text("Failed to load statistics")
            .font(.title3.bold())

          Text(error)
            .font(.body)
            .foregroundStyle(.secondary)

          Spacer()
        }
      } else if let stats = stats {
        ScrollView {
          VStack(spacing: 24) {
            // Overview cards
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
              StatCard(
                title: "Transcripts",
                value: "\(stats.transcriptCount)",
                icon: "doc.text"
              )

              StatCard(
                title: "Entries",
                value: "\(stats.entryCount)",
                icon: "bubble.left.and.bubble.right"
              )

              StatCard(
                title: "Searchable",
                value: "\(stats.searchableEntryCount)",
                icon: "magnifyingglass"
              )
            }

            Divider()

            // Activity timeline
            if !timeline.isEmpty {
              VStack(alignment: .leading, spacing: 12) {
                Label("Activity Over Time (Last 30 Days)", systemImage: "chart.line.uptrend.xyaxis")
                  .font(.headline)

                TimelineChart(timeline: timeline)
                  .frame(height: 200)
              }

              Divider()
            }

            // Providers
            if !stats.providers.isEmpty {
              VStack(alignment: .leading, spacing: 12) {
                Label("Providers", systemImage: "wrench.and.screwdriver")
                  .font(.headline)

                HStack(spacing: 12) {
                  ForEach(Array(stats.providers.sorted()), id: \.self) { provider in
                    Text(provider.capitalized)
                      .font(.body)
                      .padding(.horizontal, 12)
                      .padding(.vertical, 6)
                      .background(Color.secondary.opacity(0.1))
                      .cornerRadius(6)
                  }
                }
              }

              Divider()
            }

            // Topic breakdown
            if !stats.topicBreakdown.isEmpty {
              VStack(alignment: .leading, spacing: 12) {
                Label("Entry Breakdown by Role", systemImage: "chart.pie")
                  .font(.headline)

                ForEach(Array(stats.topicBreakdown.sorted(by: { $0.value > $1.value })), id: \.key) { role, count in
                  HStack {
                    Text(role)
                      .font(.body)

                    Spacer()

                    Text("\(count)")
                      .font(.body.monospacedDigit())
                      .foregroundStyle(.secondary)

                    let percentage = Double(count) / Double(stats.entryCount) * 100
                    Text("\(String(format: "%.1f", percentage))%")
                      .font(.caption.monospacedDigit())
                      .foregroundStyle(.tertiary)
                  }
                  .padding(.vertical, 4)
                }
              }

              Divider()
            }

            // Activity dates
            VStack(alignment: .leading, spacing: 12) {
              Label("Activity Timeline", systemImage: "calendar")
                .font(.headline)

              if let first = stats.firstActivity {
                HStack {
                  Text("First Activity:")
                    .font(.body)
                  Spacer()
                  Text(first, style: .date)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
              }

              if let last = stats.lastActivity {
                HStack {
                  Text("Last Activity:")
                    .font(.body)
                  Spacer()
                  Text(last, style: .date)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
              }

              if let first = stats.firstActivity, let last = stats.lastActivity {
                let days = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
                HStack {
                  Text("Active Days:")
                    .font(.body)
                  Spacer()
                  Text("\(days) days")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
          .padding()
        }
      }
    }
    .frame(width: 700, height: 600)
    .task {
      await loadStatistics()
    }
  }

  private func loadStatistics() async {
    isLoading = true
    errorMessage = nil

    do {
      let statsService = ProjectStatsService(db: try DatabaseManager.shared.pool)
      stats = try await statsService.getStatistics(for: project.path.path)
      timeline = try await statsService.getActivityTimeline(for: project.path.path, days: 30)
    } catch {
      errorMessage = error.localizedDescription
    }

    isLoading = false
  }
}

struct StatCard: View {
  let title: String
  let value: String
  let icon: String

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 32))
        .foregroundStyle(.blue)

      Text(value)
        .font(.title.bold().monospacedDigit())

      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(Color.secondary.opacity(0.05))
    .cornerRadius(8)
  }
}

struct TimelineChart: View {
  let timeline: [Date: Int]

  private var sortedData: [(Date, Int)] {
    timeline.sorted { $0.key < $1.key }
  }

  var body: some View {
    if #available(macOS 13.0, *) {
      Chart {
        ForEach(sortedData, id: \.0) { date, count in
          BarMark(
            x: .value("Date", date, unit: .day),
            y: .value("Entries", count)
          )
          .foregroundStyle(.blue.gradient)
        }
      }
      .chartXAxis {
        AxisMarks(values: .stride(by: .day, count: 5)) { _ in
          AxisGridLine()
          AxisTick()
          AxisValueLabel(format: .dateTime.month().day())
        }
      }
    } else {
      // Fallback for older macOS
      VStack {
        Text("Activity chart requires macOS 13+")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color.secondary.opacity(0.05))
      .cornerRadius(8)
    }
  }
}

#Preview {
  ProjectStatsView(
    project: DiscoveredProject(
      id: "/Users/rob/code/projects/contextify",
      name: "contextify",
      path: URL(fileURLWithPath: "/Users/rob/code/projects/contextify"),
      providers: [.claudeCode, .codexCLI],
      transcriptCount: 24,
      entryCount: 1247,
      lastActivity: Date(),
      isCurrent: true
    )
  )
}
