//
//  GameListView.swift
//  Kraken
//

import Foundation
import SwiftUI

struct GameListView: View {
    @Bindable var viewModel: GameListViewModel = .shared
    @Bindable var gameDataStore: GameDataStore = .shared

    @CodableAppStorage("gameListLayout") var layout: GameListViewModel.Layout = .grid
    @AppStorage("gameCardSize") private var gameCardSize: Double = 270

    @State private var isGameImportViewPresented = false

    private var adaptiveCardWidth: CGFloat {
        min(max(gameCardSize, 240), 340)
    }

    var body: some View {
        Group {
            if gameDataStore.library.isEmpty {
                ContentUnavailableView {
                    Label("Your Library Is Empty", systemImage: "gamecontroller")
                } description: {
                    Text("Add a game to see it here.")
                } actions: {
                    Button("Add Game") {
                        isGameImportViewPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.sortedLibrary.isEmpty {
                ContentUnavailableView(
                    "No Matching Games",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search or filter.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Text("\(viewModel.sortedLibrary.count) \(viewModel.sortedLibrary.count == 1 ? "game" : "games")")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)

                            Spacer()

                            if !viewModel.searchTokens.isEmpty {
                                Text("Filtered")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.quaternary, in: .capsule)
                            }
                        }

                        switch layout {
                        case .grid:
                            LazyVGrid(
                                columns: [
                                    GridItem(
                                        .adaptive(minimum: adaptiveCardWidth, maximum: 340),
                                        spacing: 18
                                    )
                                ],
                                spacing: 18
                            ) {
                                ForEach(viewModel.sortedLibrary) { game in
                                    if let binding = gameDataStore.binding(for: game.id) {
                                        GameCard(game: binding)
                                    }
                                }
                            }

                        case .list:
                            LazyVStack(spacing: 8) {
                                ForEach(viewModel.sortedLibrary) { game in
                                    if let binding = gameDataStore.binding(for: game.id) {
                                        ListGameCard(game: binding)
                                    }
                                }
                            }
                            .frame(maxWidth: 1080)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
                .searchable(
                    text: $viewModel.searchString,
                    tokens: $viewModel.searchTokens,
                    suggestedTokens: .constant(viewModel.suggestedTokens),
                    placement: .toolbar
                ) { token in
                    switch token {
                    case .platform(let platform):
                        Text(platform.description)
                    case .storefront(let storefront):
                        Text(storefront.description)
                    case .installed:
                        Text("Installed")
                    case .notInstalled:
                        Text("Not Installed")
                    case .favourited:
                        Text("Favourited")
                    }
                }
            }
        }
        .animation(.easeInOut, value: layout)
        .sheet(isPresented: $isGameImportViewPresented) {
            GameImportView(isPresented: $isGameImportViewPresented)
                .fixedSize()
        }
    }
}

#Preview {
    GameListView()
        .environmentObject(NetworkMonitor.shared)
}
