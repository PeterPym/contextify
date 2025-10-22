import SwiftUI

struct SettingsView: View {
  var body: some View {
    TabView {
      GeneralSettingsView()
        .tabItem {
          Label("General", systemImage: "gearshape")
        }

      DatabaseSettingsView()
        .tabItem {
          Label("Database", systemImage: "cylinder")
        }
    }
    .frame(width: 500, height: 400)
  }
}

struct GeneralSettingsView: View {
  @AppStorage("outputsDirectory") private var outputsDirectory = "~/Contextify/outputs"

  var body: some View {
    Form {
      Section {
        Text("General Settings")
          .font(.headline)

        Divider()

        LabeledContent("Outputs Directory:") {
          Text(outputsDirectory)
            .foregroundStyle(.secondary)
            .font(.caption)
        }

        Text("Configure application preferences and behavior")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.top, 8)
      }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

struct DatabaseSettingsView: View {
  var body: some View {
    Form {
      Section {
        Text("Database Settings")
          .font(.headline)

        Divider()

        VStack(alignment: .leading, spacing: 12) {
          Text("Database Location:")
            .font(.subheadline)

          Text("~/Library/Application Support/Contextify/contextify.db")
            .font(.caption)
            .foregroundStyle(.secondary)

          HStack {
            Button("Open Database Folder") {
              let dbPath = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Contextify")
              NSWorkspace.shared.open(dbPath)
            }
            .buttonStyle(.bordered)

            Button("Backup Database") {
              // TODO: Implement backup
            }
            .buttonStyle(.bordered)
          }
        }
        .padding(.top, 8)
      }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

#Preview {
  SettingsView()
}
