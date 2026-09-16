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

    static let defaultHeight: CGFloat = 76

    var body: some View {
        HStack(spacing: 14) {
            GameImageCard(
                url: game.horizontalImageURL,
                isImageEmpty: $isImageEmpty,
                withBlur: false
            )
            .aspectRatio(16 / 9, contentMode: .fill)
            .frame(width: 92, height: 56)
            .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(game.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                GameCard.SubscriptedInfoView(game: $game)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 10)

            GameCard.ButtonsView(game: $game)
                .clipShape(.capsule)
                .layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: Self.defaultHeight, maxHeight: Self.defaultHeight)
        .background(.background.secondary)
        .clipShape(.rect(cornerRadius: 13))
        .contentShape(.rect(cornerRadius: 13))
    }
}

#Preview {
    ListGameCard(game: .constant(placeholderGame(type: Game.self)))
        .padding()
        .environmentObject(NetworkMonitor.shared)
}
