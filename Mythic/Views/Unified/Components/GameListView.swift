//
//  GameListView.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 6/3/2024.
//

// Copyright © 2023-2025 vapidinfinity

import Foundation
import SwiftUI

struct GameListView: View {
    @Bindable var viewModel: GameListViewModel = .shared
    @Bindable var gameDataStore: GameDataStore = .shared

    @CodableAppStorage("gameListLayout") var layout: GameListViewModel.Layout = .grid
    @AppStorage("gameCardSize") private var gameCardSize: Double = 270.0

    @State private var isGameImportViewPresented = false

    private var adaptiveCardWidth: CGFloat {
        min(max(gameCardSize, 250), 340)
    }

    var body: some View {
        VStack(spacing: 0) {
            if gameDataStore.library.isEmpty {
                VStack(spacing: 14) {
                    ContentUnavailableView(
                        "No games found",
                        systemImage: "gamecontroller",
                        description: Text("Games in your library will appear here.")
                    )

                    Button {
                        isGameImportViewPresented = true
                    } label: {
                        Label("Import Game", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sheet(isPresented: $isGameImportViewPresented) {
                    GameImportView(isPresented: $isGameImportViewPresented)
                }
            } else {
                ScrollView(.vertical) {
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
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)

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
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                    }
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
        .animation(.default, value: viewModel.sortedLibrary)
    }
}

#Preview {
    GameListView()
        .environmentObject(NetworkMonitor.shared)
}
