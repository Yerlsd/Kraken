//
//  HomeView.swift
//  Kraken
//
//  Created by vapidinfinity (esi) on 12/9/2023.
//

// Copyright © 2023-2025 vapidinfinity

import SwiftUI
import Cocoa
import SwordRPC

/// The main view displaying the home screen of the Kraken app.
struct HomeView: View {
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Bindable var gameDataStore: GameDataStore = .shared

    @AppStorage("gameCardSize") private var gameCardSize: Double = 260.0

    @State private var isImageEmpty = true
    @State private var isFavouritesSectionExpanded = true
    @State private var isContainersSectionExpanded = true

    private var favouriteGamesExcludingRecent: [Game] {
        gameDataStore.library
            .filter(\.self.isFavourited)
            .filter { $0 != gameDataStore.recent }
    }

    private var adaptiveCardWidth: CGFloat {
        min(max(gameCardSize, 240), 330)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    continuePlayingView
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 250, maxHeight: min(360, geometry.size.height * 0.52))

                    Form {
                        Section("Your Favourites", isExpanded: $isFavouritesSectionExpanded) {
                            if favouriteGamesExcludingRecent.isEmpty {
                                HStack {
                                    Spacer()
                                    ContentUnavailableView(
                                        "No Favourites",
                                        systemImage: "star.slash",
                                        description: Text("Favourite a game to keep it close at hand.")
                                    )
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            } else {
                                LazyVGrid(
                                    columns: [
                                        GridItem(.adaptive(minimum: adaptiveCardWidth, maximum: 330), spacing: 14)
                                    ],
                                    spacing: 14
                                ) {
                                    ForEach(favouriteGamesExcludingRecent) { game in
                                        if let binding = gameDataStore.binding(for: game.id) {
                                            GameCard(game: binding)
                                        }
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }

                        Section("Your Containers", isExpanded: $isContainersSectionExpanded) {
                            ContainerListView()
                        }
                    }
                    .formStyle(.grouped)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .customTransform { view in
            if #available(macOS 15.0, *) {
                view
                    .toolbar(removing: .title)
                    .toolbarBackgroundVisibility(.hidden)
            } else {
                view.toolbarBackground(.hidden)
            }
        }
        .navigationTitle("Home")
        .task(priority: .background) {
            discordRPC.setPresence({
                var presence: RichPresence = .init()
                presence.details = "Viewing home"
                presence.state = "Idle"
                presence.timestamps.start = .now
                presence.assets.largeImage = "macos_512x512_2x"
                return presence
            }())
        }
    }

    @ViewBuilder
    private var continuePlayingView: some View {
        if let recentGame = gameDataStore.recent {
            ZStack(alignment: .bottomLeading) {
                GameImageCard(url: recentGame.horizontalImageURL, isImageEmpty: $isImageEmpty)
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.15),
                        .init(color: .black.opacity(0.78), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(alignment: .bottom, spacing: 14) {
                    if isImageEmpty && recentGame.isFallbackImageAvailable {
                        GameImageCard.FallbackGameImageCard(game: .constant(recentGame))
                            .frame(width: 56, height: 56)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("CONTINUE PLAYING")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))

                        GameCard.TitleAndInformationView(
                            game: .constant(recentGame),
                            withSubscriptedInfo: true
                        )
                        .foregroundStyle(.white)

                        if let recentBinding = gameDataStore.binding(for: recentGame.id) {
                            GameCard.ButtonsView(game: recentBinding, withLabel: true)
                                .clipShape(.capsule)
                        }
                    }
                }
                .padding(20)
            }
            .clipShape(.rect(cornerRadius: 18))
            .contentShape(.rect(cornerRadius: 18))
        } else {
            HStack(spacing: 18) {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Welcome to Kraken")
                        .font(.title2.weight(.semibold))

                    Text("Your recently played game will appear here. Launch a game from your Library to get started.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background.secondary)
            .clipShape(.rect(cornerRadius: 18))
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(NetworkMonitor.shared)
}
