//
//  HomeView.swift
//  Kraken
//

import SwiftUI
import SwordRPC

struct HomeView: View {
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Bindable var gameDataStore: GameDataStore = .shared

    @State private var isGameImportPresented = false
    @AppStorage("gameCardSize") private var gameCardSize: Double = 260

    private var favouriteGames: [Game] {
        gameDataStore.library
            .filter(\.isFavourited)
            .filter { $0.id != gameDataStore.recent?.id }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var adaptiveCardWidth: CGFloat {
        min(max(gameCardSize, 220), 330)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                heroSection

                if !favouriteGames.isEmpty {
                    sectionHeader(
                        title: "Favourites",
                        subtitle: "Games you want close at hand"
                    )

                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: adaptiveCardWidth, maximum: 330), spacing: 16)
                        ],
                        spacing: 16
                    ) {
                        ForEach(favouriteGames) { game in
                            if let binding = gameDataStore.binding(for: game.id) {
                                GameCard(game: binding)
                            }
                        }
                    }
                }

                if gameDataStore.library.isEmpty {
                    emptyLibrary
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(.background)
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isGameImportPresented = true
                } label: {
                    Label("Add Game", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sheet(isPresented: $isGameImportPresented) {
            GameImportView(isPresented: $isGameImportPresented)
                .fixedSize()
        }
        .task(priority: .background) {
            discordRPC.setPresence({
                var presence = RichPresence()
                presence.details = "Viewing home"
                presence.state = "Idle"
                presence.timestamps.start = .now
                presence.assets.largeImage = "macos_512x512_2x"
                return presence
            }())
        }
    }

    private var heroSection: some View {
        Group {
            if let recentGame = gameDataStore.recent,
               let binding = gameDataStore.binding(for: recentGame.id) {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(
                        title: "Continue Playing",
                        subtitle: "Jump straight back in"
                    )

                    HeroGameCard(game: binding)
                        .frame(minHeight: 300, maxHeight: 410)
                }
            } else {
                welcomeCard
            }
        }
    }

    private var welcomeCard: some View {
        HStack(spacing: 18) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 6) {
                Text(gameDataStore.library.isEmpty ? "Welcome to Kraken" : "Your library is ready")
                    .font(.title2.weight(.semibold))

                Text(
                    gameDataStore.library.isEmpty
                        ? "Add a Windows game to get started. Kraken keeps the compatibility details out of your way."
                        : "Launch a game from your library and it will appear here for quick access."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Button("Add Game") {
                    isGameImportPresented = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("No Games Yet", systemImage: "gamecontroller")
        } description: {
            Text("Add or import your games and they will appear in your unified Kraken library.")
        } actions: {
            Button("Add Game") {
                isGameImportPresented = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title2.weight(.semibold))

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(NetworkMonitor.shared)
}
