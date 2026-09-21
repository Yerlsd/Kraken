//
//  GameCard.swift
//  Kraken
//

import SwiftUI

struct GameCard: View {
    @Binding var game: Game

    @State private var isImageEmpty = true
    @State private var isImageEmptyPreMacOSTahoe = true

    var body: some View {
        GameImageCard(
            game: game,
            url: game.verticalImageURL,
            isImageEmpty: $isImageEmpty
        )
        .aspectRatio(4 / 5, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 18))
        .overlay(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                GameCard.TitleAndInformationView(
                    game: $game,
                    font: .headline,
                    withSubscriptedInfo: true
                )
                .lineLimit(2)
                .layoutPriority(1)

                GameCard.ButtonsView(game: $game)
                    .clipShape(.capsule)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .onChange(of: isImageEmpty) {
                if #unavailable(macOS 26.0) {
                    isImageEmptyPreMacOSTahoe = $1
                }
            }
            .conditionalTransform(if: !isImageEmptyPreMacOSTahoe) { view in
                view.foregroundStyle(.white)
            }
            .padding(7)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .padding(7)
        }
        .overlay(alignment: .topLeading) {
            statusBadge
                .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            if game.isFavourited {
                Image(systemName: "star.fill")
                    .symbolRenderingMode(.hierarchical)
                    .padding(8)
                    .background(.ultraThinMaterial, in: .circle)
                    .padding(10)
            }
        }
        .contentShape(.rect(cornerRadius: 18))
    }

    @ViewBuilder
    private var statusBadge: some View {
        if game.isOperating {
            Label("Running", systemImage: "play.fill")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: .capsule)
        } else if case .installed = game.installationState {
            Label("Installed", systemImage: "checkmark")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: .capsule)
        }
    }
}

/// ViewModifier that enables views to have a fade-in effect.
struct FadeInModifier: ViewModifier {
    @State private var opacity = 0.0

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.35)) {
                    opacity = 1
                }
            }
    }
}

#Preview {
    GameCard(game: .constant(placeholderGame(type: Game.self)))
        .environmentObject(NetworkMonitor.shared)
}
