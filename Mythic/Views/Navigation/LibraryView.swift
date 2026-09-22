import SwiftUI
import SwordRPC

struct LibraryView: View {
    @Bindable private var gameDataStore: GameDataStore = .shared
    @Bindable private var gameListViewModel: GameListViewModel = .shared
    @State private var isGameImportSheetPresented = false
    @CodableAppStorage("gameListLayout") private var gameListLayout: GameListViewModel.Layout = .grid

    var body: some View {
        VStack(spacing: 0) {
            libraryToolbar
            Divider()

            if gameListViewModel.sortedLibrary.isEmpty {
                ContentUnavailableView {
                    Label("No Games Found", systemImage: "gamecontroller")
                } description: {
                    Text(gameListViewModel.searchString.isEmpty
                         ? "Import a game or connect a supported storefront."
                         : "Try a different search or clear your filters.")
                } actions: {
                    if !gameListViewModel.searchString.isEmpty || !gameListViewModel.searchTokens.isEmpty {
                        Button("Clear Filters") {
                            gameListViewModel.searchString = ""
                            gameListViewModel.searchTokens.removeAll()
                        }
                    } else {
                        Button("Import Game") {
                            isGameImportSheetPresented = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else if gameListLayout == .grid {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 205, maximum: 280), spacing: 18)],
                        spacing: 18
                    ) {
                        ForEach(gameListViewModel.sortedLibrary) { game in
                            if let binding = gameDataStore.binding(for: game.id) {
                                GameCard(game: binding)
                            }
                        }
                    }
                    .padding(24)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(gameListViewModel.sortedLibrary) { game in
                            if let binding = gameDataStore.binding(for: game.id) {
                                LibraryListRow(game: binding)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Library")
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $isGameImportSheetPresented) {
            GameImportView(isPresented: $isGameImportSheetPresented)
                .fixedSize()
        }
        .task(priority: .background) {
            discordRPC.setPresence({
                var presence: RichPresence = .init()
                presence.details = "Browsing the game library"
                presence.state = "Library"
                presence.timestamps.start = .now
                presence.assets.largeImage = "macos_512x512_2x"
                return presence
            }())
        }
    }

    private var libraryToolbar: some View {
        HStack(spacing: 12) {
            TextField("Search games", text: $gameListViewModel.searchString)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220, maxWidth: 420)

            Menu {
                Section("Storefront") {
                    ForEach(Game.Storefront.allCases, id: \.self) { storefront in
                        Toggle(storefront.description, isOn: searchTokenBinding(for: .storefront(storefront)))
                    }
                }
                Section("Installation") {
                    Toggle("Installed", isOn: searchTokenBinding(for: .installed))
                    Toggle("Not Installed", isOn: searchTokenBinding(for: .notInstalled))
                }
                Section("Other") {
                    Toggle("Favorites", isOn: searchTokenBinding(for: .favourited))
                }
                if !gameListViewModel.searchTokens.isEmpty {
                    Divider()
                    Button("Clear Filters") {
                        gameListViewModel.searchTokens.removeAll()
                    }
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)

            Spacer()

            if gameListViewModel.isUpdatingLibrary {
                ProgressView().controlSize(.small)
            }

            Picker("View", selection: $gameListLayout) {
                Image(systemName: "square.grid.2x2").tag(GameListViewModel.Layout.grid)
                Image(systemName: "list.bullet").tag(GameListViewModel.Layout.list)
            }
            .pickerStyle(.segmented)
            .frame(width: 90)

            Button {
                isGameImportSheetPresented = true
            } label: {
                Label("Import", systemImage: "plus")
            }
            .buttonStyle(.bordered)

            Button {
                Task(priority: .userInitiated) {
                    try? await gameDataStore.refreshFromStorefronts()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh Library")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func searchTokenBinding(for token: GameListViewModel.SearchToken) -> Binding<Bool> {
        Binding(
            get: { gameListViewModel.searchTokens.contains(token) },
            set: { isOn in
                if isOn {
                    gameListViewModel.searchTokens.append(token)
                } else {
                    gameListViewModel.searchTokens.removeAll { $0 == token }
                }
            }
        )
    }
}

private struct LibraryListRow: View {
    @Binding var game: Game
    @State private var imageEmpty = true

    var body: some View {
        HStack(spacing: 14) {
            GameImageCard(game: game, url: game.verticalImageURL, isImageEmpty: $imageEmpty)
                .frame(width: 76, height: 92)
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                GameCard.TitleAndInformationView(game: $game, font: .headline, withSubscriptedInfo: true)
                    .lineLimit(1)
                if case .installed(let location, _) = game.installationState {
                    Text(location.deletingLastPathComponent().prettyPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 10)

            GameCard.ButtonsView(game: $game, withLabel: true)
                .buttonStyle(.borderedProminent)
                .clipShape(.capsule)
        }
        .padding(10)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 14))
    }
}

#Preview {
    LibraryView()
        .environmentObject(NetworkMonitor.shared)
        .frame(minWidth: 850, minHeight: 550)
}
