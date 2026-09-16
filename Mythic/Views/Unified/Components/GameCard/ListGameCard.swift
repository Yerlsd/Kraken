//
//  ListGameCard.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 10/20/24.
//

// Copyright © 2023-2025 vapidinfinity

import SwiftUI

struct ListGameCard: View {
    @Binding var game: Game

    @State private var isImageEmpty: Bool = true

    static let defaultHeight: CGFloat = 88

    var body: some View {
        HStack(spacing: 14) {
            GameImageCard(
                url: game.horizontalImageURL,
                isImageEmpty: $isImageEmpty,
                withBlur: false
            )
            .aspectRatio(16 / 9, contentMode: .fill)
            .frame(width: 104, height: 64)
            .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(game.title)
                    .font(.headline)
                    .bold()
                    .lineLimit(1)
                    .truncationMode(.tail)

                GameCard.SubscriptedInfoView(game: $game)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            GameCard.ButtonsView(game: $game)
                .clipShape(.capsule)
                .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: Self.defaultHeight, maxHeight: Self.defaultHeight)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.background.secondary)
        }
        .contentShape(.rect(cornerRadius: 14))
    }
}

#Preview {
    ListGameCard(game: .constant(placeholderGame(type: Game.self)))
        .padding()
        .environmentObject(NetworkMonitor.shared)
}
