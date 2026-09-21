//
//  SteamGameImportView.swift
//  Kraken
//
// Copyright © 2026 Kraken contributors
//

import SwiftUI
import OSLog

struct SteamGameImportView: View {
    @Bindable var gameDataStore: GameDataStore = .shared
    @Binding var isPresented: Bool

    @State private var discoveredGames: [SteamGame] = []
    @State private var isScanning = false
    @State private var manualAppId: String = ""
    @State private var manualTitle: String = ""
    @State private var manualLocation: URL = .temporaryDirectory
    @State private var isFileImporterPresented = false
    @State private var selectedTab = 0 // 0 = Auto-detect, 1 = Manual

    var body: some View {
        VStack(spacing: 16) {
            Picker("Import Method", selection: $selectedTab) {
                Text("Auto-Detect").tag(0)
                Text("Manual Import").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if selectedTab == 0 {
                autoDetectView
            } else {
                manualImportView
            }
        }
        .padding(.vertical)
        .task {
            scanForSteamGames()
        }
    }

    private var autoDetectView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Installed Steam Games")
                    .font(.headline)
                Spacer()
                if isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Rescan", systemImage: "arrow.clockwise") {
                        scanForSteamGames()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            if discoveredGames.isEmpty && !isScanning {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.folder")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No unimported Steam games found.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Make sure Steam games are installed in ~/Library/Application Support/Steam or in a Kraken container.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(discoveredGames, id: \.id) { game in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.title)
                                .font(.body)
                                .bold()
                            Text("App ID: \(game.id)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Import") {
                            importDiscoveredGame(game)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var manualImportView: some View {
        Form {
            TextField("App ID (e.g. 480)", text: $manualAppId)
            TextField("Game Title", text: $manualTitle)

            HStack {
                VStack(alignment: .leading) {
                    Text("Game Executable")
                    if manualLocation != .temporaryDirectory {
                        Text(manualLocation.prettyPath)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                Spacer()
                Button("Browse...") {
                    isFileImporterPresented = true
                }
                .fileImporter(
                    isPresented: $isFileImporterPresented,
                    allowedContentTypes: [.item]
                ) { result in
                    if case .success(let url) = result {
                        manualLocation = url
                        if manualTitle.isEmpty {
                            manualTitle = url.deletingPathExtension().lastPathComponent
                        }
                    }
                }
            }

            Button("Import Game") {
                guard !manualAppId.isEmpty, !manualTitle.isEmpty, manualLocation != .temporaryDirectory else { return }
                let isWindows = manualLocation.pathExtension.lowercased() == "exe"
                SteamGameManager.importGame(
                    appId: manualAppId,
                    title: manualTitle,
                    executableURL: manualLocation,
                    platform: isWindows ? .windows : .macOS
                )
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .disabled(manualAppId.isEmpty || manualTitle.isEmpty || manualLocation == .temporaryDirectory)
        }
        .padding(.horizontal)
    }

    private func scanForSteamGames() {
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let found = SteamDiscovery.discoverInstalledGames()
            await MainActor.run {
                // Filter out games already in library
                let existingIDs = Set(gameDataStore.library.map(\.id))
                self.discoveredGames = found.filter { !existingIDs.contains($0.id) }
                self.isScanning = false
            }
        }
    }

    private func importDiscoveredGame(_ game: SteamGame) {
        gameDataStore.library.insert(game)
        discoveredGames.removeAll(where: { $0.id == game.id })
        if discoveredGames.isEmpty {
            isPresented = false
        }
    }
}
