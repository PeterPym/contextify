//
//  ContentView.swift
//  Contextify
//
//  Created by Rob Banagale on 9/13/25.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var model = HUDViewModel()
    @State private var showToast = false
    @State private var toastText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            urlEntry
            IngestDropZone()
            controls
        }
        .padding(16)
        .environment(model)
        .overlay(alignment: .top) { toast }
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
            Label(model.branch, systemImage: "arrow.branch")
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
            TextField("Paste a URL…", text: $model.urlText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await model.ingestURLString() } }
            Button("Ingest") { Task { await model.ingestURLString() } }
                .buttonStyle(.borderedProminent)
                .disabled(model.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var controls: some View {
        HStack {
            Button("New Session") { model.newSession() }
            Button("Checkpoint") { model.checkpoint() }
            Button("Reveal Outputs") { NSWorkspace.shared.open(model.outputsDirectory) }
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

#Preview { ContentView() }
