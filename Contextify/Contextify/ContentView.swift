//
//  ContentView.swift
//  Contextify
//
//  Created by Rob Banagale on 9/13/25.
//

import SwiftUI
import AppKit
import OSLog

private let uiLog = Logger(subsystem: "dev.contextify", category: "UI")

struct ContentView: View {
    @Environment(HUDViewModel.self) private var model
    @State private var showToast = false
    @State private var toastText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if case .ingesting = model.state {
                ProgressView().controlSize(.small)
            }
            urlEntry
            IngestDropZone()
            controls
        }
        .padding(16)
        .background(WindowTitleWriter(title: "Project: \(model.projectDisplayName)"))
        .overlay(alignment: .top) { toast }
        .onAppear { model.updateGitInfo() }
        .alert("Project Root", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onChange(of: model.state) { _, newState in
            if case .success(let msg) = newState {
                toastText = msg
                withAnimation { showToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { showToast = false }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 360)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label(model.projectDisplayName, systemImage: "folder")
            Label(model.branchDisplay, systemImage: "arrow.branch")
            if model.projectRootURL == nil {
                Button("Set Project Root…") {
                    let ok = pickProjectRoot()
                    uiLog.info("Set Project Root result=\(ok, privacy: .public)")
                }
                .buttonStyle(.link)
            }
            Divider().frame(height: 16)
            Label(model.session, systemImage: "tag")
            Spacer()
            if let url = model.lastOutputURL {
                Button("Last: \(url.lastPathComponent)") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.link)
            } else {
                Text(model.status).foregroundStyle(.secondary)
            }
        }
    }

    private var urlEntry: some View {
        HStack {
            TextField(
                "Paste a URL…",
                text: Binding(
                    get: { model.urlText },
                    set: { model.urlText = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit { Task { await model.ingestURLString() } }
            Button("Ingest") { Task { await model.ingestURLString() } }
                .buttonStyle(.borderedProminent)
                .disabled(model.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
        }
        .disabled(isBusy)
    }

    private var controls: some View {
        HStack {
            Button("New Session") { model.newSession() }
                .disabled(isBusy)
            Button("Checkpoint") { Task { await model.checkpoint() } }
                .disabled(isBusy)
            Button("Reveal Outputs") {
                Task {
                    let dir = await model.prepareOutputsDirectory()
                    NSWorkspace.shared.open(dir)
                }
            }
            Spacer()
        }
    }

    private var toast: some View {
        Group {
            if showToast {
                Text(toastText)
                    .padding(10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

#Preview { ContentView().environment(HUDViewModel()) }

private extension ContentView {
    var isBusy: Bool {
        if case .ingesting = model.state { return true }
        return false
    }

    @discardableResult
    func pickProjectRoot() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.urls.first {
            let result = model.setProjectRoot(url: url)
            switch result {
            case .success(let root):
                #if DEBUG
                uiLog.info("Set Project Root path=\(root.path, privacy: .public)")
                #else
                uiLog.info("Set Project Root path=\(root.path, privacy: .private)")
                #endif
                return true
            case .failure(let error):
                uiLog.error("Failed to set project root: \(String(describing: error), privacy: .public)")
                return false
            }
        }
        return false
    }
}
