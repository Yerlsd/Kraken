import SwiftUI

/// Kraken's reusable library tile.
/// Artwork stays dominant while controls live in a compact material footer.
struct GameCard: View {
    @Binding var game: Game

    @State private var isImageEmpty = true
    @State private var isHovering = false
    @AppStorage("libraryArtworkGlow") private var artworkGlow = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                GameImageCard(game: game, url: game.verticalImageURL, isImageEmpty: $isImageEmpty)
                    .aspectRatio(4 / 5, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()

                HStack(spacing: 6) {
                    Text(game.storefront?.description ?? "Local")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: .capsule)

                    Spacer()

                    if game.isFavourited {
                        Image(systemName: "star.fill")
                            .font(.caption.weight(.bold))
                            .padding(7)
                            .background(.ultraThinMaterial, in: .circle)
                    }
                }
                .padding(10)
            }
            .clipShape(.rect(topLeadingRadius: 16, topTrailingRadius: 16))

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(game.title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(game.lastLaunched == nil ? "Not played yet" : "Recently played")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                GameCard.ButtonsView(game: $game)
                    .labelStyle(.iconOnly)
            }
            .padding(11)
            .background(.regularMaterial)
        }
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(artworkGlow ? (isHovering ? 0.16 : 0.08) : 0),
            radius: artworkGlow ? (isHovering ? 14 : 8) : 0,
            y: artworkGlow ? (isHovering ? 7 : 4) : 0
        )
        .scaleEffect(isHovering ? 1.012 : 1)
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .onHover { isHovering = $0 }
        .contextMenu {
            GameCard.MenuView(game: $game)
        }
    }
}

#Preview {
    GameCard(game: .constant(placeholderGame(type: Game.self)))
        .frame(width: 230)
        .environmentObject(NetworkMonitor.shared)
}
