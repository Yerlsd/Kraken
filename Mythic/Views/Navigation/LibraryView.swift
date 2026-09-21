//
//  LibraryView.swift
//  Kraken
//

import SwiftUI
import SwordRPC

struct LibraryView: View {
    @Bindable var gameDataStore: GameDataStore = .shared
    @Bindable var gameListViewModel: GameListViewModel = .shared
    @CodableAppStorage("gameListLayout") var gameListLayout: GameListViewModel.Layout = .grid

    @State private var isGameImportSheetPresented = false

    var body: some View {
        GameListView()
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isGameImportSheetPresented = true
                    } label: {
                        Label("Add Game", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if !gameListViewModel.sortedLibrary.isEmpty {
                    ToolbarItem(placement: .automatic) {
                        Picker("Layout", selection: $gameListLayout) {
                            Label("Grid", systemImage: "square.grid.3x3").tag(GameListViewModel.Layout.grid)
                            Label("List", systemImage: "list.bullet").tag(GameListViewModel.Layout.list)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }

                    ToolbarItem(placement: .automatic) {
                        Menu {
                            Section("Platform") {
                                ForEach(Game.Platform.allCases, id: \.self) { platform in
                                    Toggle(
                                        platform.description,
                                        isOn: searchTokenBinding(for: .platform(platform))
                                    )
                                }
                            }

                            Section("Source") {
                                ForEach(Game.Storefront.allCases, id: \.self) { storefront in
                                    Toggle(
                                        storefront.description,
                                        isOn: searchTokenBinding(for: .storefront(storefront))
                                    )
                                }
                            }

                            Section("Status") {
                                Toggle("Installed", isOn: searchTokenBinding(for: .installed))
                                Toggle("Not Installed", isOn: searchTokenBinding(for: .notInstalled))
                                Toggle("Favourites", isOn: searchTokenBinding(for: .favourited))
                            }
                        } label: {
                            Label("Filter", systemImage: "line.3.horizontal.decrease")
                        }
                    }
                }
            }
            .sheet(isPresented: $isGameImportSheetPresented) {
                GameImportView(isPresented: $isGameImportSheetPresented)
                    .fixedSize()
            }
            .task(priority: .background) {
                discordRPC.setPresence({
                    var presence = RichPresence()
                    presence.details = "Looking through the game library"
                    presence.state = "Viewing Library"
                    presence.timestamps.start = .now
                    presence.assets.largeImage = "macos_512x512_2x"
                    return presence
                }())
            }
    }

    private func searchTokenBinding(for token: GameListViewModel.SearchToken) -> Binding<Bool> {
        Binding(
            get: { gameListViewModel.searchTokens.contains(token) },
            set: { isOn in
                if isOn {
                    if !gameListViewModel.searchTokens.contains(token) {
                        gameListViewModel.searchTokens.append(token)
                    }
                } else {
                    gameListViewModel.searchTokens.removeAll { $0 == token }
                }
            }
        )
    }
}

#Preview {
    LibraryView()
        .environmentObject(NetworkMonitor.shared)
        .frame(minHeight: 300)
}
