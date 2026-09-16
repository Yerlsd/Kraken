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
    @AppStorage("gameCardSize") private var gameCardSize: Double = 240.0
    
    @State private var isGameImportViewPresented: Bool = false
    
    private var adaptiveCardWidth: CGFloat {
        min(max(gameCardSize, 220), 280)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if gameDataStore.library.isEmpty {
                ContentUnavailableView(
                    "No games found",
                    systemImage: "gamecontroller",
                    description: Text("Games in your library will appear here.")
                )
                
                Button {
                    isGameImportViewPresented = true
                } label: {
                    Label("Import Game", systemImage: "plus.app")
                }
                .buttonStyle(.borderedProminent)
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
                                    .adaptive(minimum: adaptiveCardWidth, maximum: 280),
                                    spacing: 16
                                )
                            ],
                            spacing: 16
                        ) {
                            ForEach(viewModel.sortedLibrary) { game in
                                GameCard(game: .constant(game))
                                    .frame(maxWidth: 280)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                    case .list:
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.sortedLibrary) { game in
                                ListGameCard(game: .constant(game))
                            }
                        }
                        .frame(maxWidth: 980)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
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
