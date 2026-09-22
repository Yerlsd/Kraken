import SwiftUI
import SwordRPC

/// The landing page for Kraken.
///
/// The home screen is intentionally a dashboard rather than a settings form:
/// one hero game, then useful shelves. Every shelf uses adaptive layouts so
/// resizing the window never produces clipped cards or oversized fixed panels.
struct HomeView: View {
    @Bindable private var gameDataStore: GameDataStore = .shared

    @State private var heroImageEmpty = true

    private var favourites: [Game] {
        gameDataStore.library
            .filter(\.isFavourited)
            .filter { $0 != gameDataStore.recent }
    }

    private var recentGames: [Game] {
        gameDataStore.library
            .filter { $0.lastLaunched != nil }
            .sorted { ($0.lastLaunched ?? .distantPast) > ($1.lastLaunched ?? .distantPast) }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                hero

                if !recentGames.isEmpty {
                    shelf(title: "Recently Played", subtitle: "Jump back into your last games") {
                        ForEach(recentGames) { game in
                            gameBinding(for: game) { binding in
                                GameCard(game: binding)
                            }
                        }
                    }
                }

                shelf(title: "Favorites", subtitle: "Your pinned games") {
                    if favourites.isEmpty {
                        emptyShelf(
                            title: "No favorites yet",
                            message: "Star a game in your Library and it will appear here.",
                            systemImage: "star"
                        )
                    } else {
                        ForEach(favourites) { game in
                            gameBinding(for: game) { binding in
                                GameCard(game: binding)
                            }
                        }
                    }
                }

                ContainerListView()
                    .padding(.top, 2)
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 32)
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(destination: LibraryView()) {
                    Label("Browse Library", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .task(priority: .background) {
            discordRPC.setPresence({
                var presence: RichPresence = .init()
                presence.details = "Browsing Kraken"
                presence.state = "Home"
                presence.timestamps.start = .now
                presence.assets.largeImage = "macos_512x512_2x"
                return presence
            }())
        }
    }

    @ViewBuilder
    private var hero: some View {
        if let recent = gameDataStore.recent,
           let binding = gameDataStore.binding(for: recent.id) {
            ZStack(alignment: .bottomLeading) {
                GameImageCard(
                    url: recent.horizontalImageURL,
                    isImageEmpty: $heroImageEmpty
                )
                .aspectRatio(2.25, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.82)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 12) {
                    Label("CONTINUE PLAYING", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))

                    GameCard.TitleAndInformationView(
                        game: binding,
                        font: .largeTitle,
                        withSubscriptedInfo: true
                    )
                    .foregroundStyle(.white)

                    GameCard.ButtonsView(game: binding, withLabel: true)
                        .buttonStyle(.borderedProminent)
                        .clipShape(.capsule)
                }
                .padding(24)
            }
            .clipShape(.rect(cornerRadius: 22))
            .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        } else {
            HStack(spacing: 18) {
                Image("KrakenLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(.rect(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Welcome to Kraken")
                        .font(.title.bold())
                    Text("Your recently played game will appear here. Browse your Library to get started.")
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(.rect(cornerRadius: 22))
        }
    }

    @ViewBuilder
    private func shelf<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2.bold())
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190, maximum: 250), spacing: 16)],
                spacing: 16,
                content: content
            )
        }
    }

    private func emptyShelf(title: String, message: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }

    @ViewBuilder
    private func gameBinding<Content: View>(for game: Game, @ViewBuilder content: (Binding<Game>) -> Content) -> some View {
        if let binding = gameDataStore.binding(for: game.id) {
            content(binding)
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(NetworkMonitor.shared)
}
