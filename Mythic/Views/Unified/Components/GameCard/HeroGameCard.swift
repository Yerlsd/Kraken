//
//  HeroGameCard.swift
//  Kraken
//

import SwiftUI

struct HeroGameCard: View {
    @Binding var game: Game

    @State private var isImageEmpty = true

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                GameImageCard(
                    game: game,
                    url: game.horizontalImageURL,
                    isImageEmpty: $isImageEmpty,
                    withBlur: true
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Label("RECENTLY PLAYED", systemImage: "clock.arrow.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.78))

                        if game.isOperating {
                            Text("RUNNING")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.15), in: .capsule)
                        }
                    }

                    GameCard.TitleAndInformationView(
                        game: $game,
                        font: .largeTitle,
                        withSubscriptedInfo: true
                    )
                    .foregroundStyle(.white)
                    .lineLimit(1)

                    HStack(spacing: 8) {
                        GameCard.ButtonsView(game: $game, withLabel: true)
                            .clipShape(.capsule)

                        GameCard.MenuView(game: $game)
                            .padding(.horizontal, 1)
                    }
                }
                .padding(24)
            }
            .clipShape(.rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(radius: 18, y: 8)
        }
    }
}

#Preview {
    HeroGameCard(game: .constant(placeholderGame(type: Game.self)))
        .frame(width: 820, height: 360)
        .environmentObject(NetworkMonitor.shared)
}
