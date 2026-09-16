//
//  GameCard.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 5/3/2024.
//

// Copyright © 2023-2025 vapidinfinity

import SwiftUI
import SwiftyJSON
import Glur
import OSLog

struct GameCard: View {
    @Binding var game: Game

    @State private var isImageEmpty: Bool = true
    @State private var isImageEmptyPreMacOSTahoe: Bool = true

    var body: some View {
        GameImageCard(game: game, url: game.verticalImageURL, isImageEmpty: $isImageEmpty)
            .aspectRatio(4 / 5, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 16))
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 7) {
                    GameCard.TitleAndInformationView(
                        game: $game,
                        font: .headline,
                        withSubscriptedInfo: true
                    )
                    .lineLimit(2)
                    .layoutPriority(1)

                    GameCard.ButtonsView(game: $game)
                        .clipShape(.capsule)
                        .progressViewStyle(.circular)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .onChange(of: isImageEmpty) {
                    if #unavailable(macOS 26.0) {
                        isImageEmptyPreMacOSTahoe = $1
                    }
                }
                .conditionalTransform(if: !isImageEmptyPreMacOSTahoe) { view in
                    view.foregroundStyle(.white)
                }
                .customTransform { view in
                    if #available(macOS 26.0, *) {
                        view
                            .glassEffect(in: .rect(cornerRadius: 14.0))
                            .padding(6)
                    } else {
                        view
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .padding(.bottom, 8)
                    }
                }
            }
            .overlay(alignment: .top) {
                if game.isUpdateAvailable == true {
                    Label("Update available", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .customTransform { view in
                            if #available(macOS 26.0, *) {
                                view.glassEffect(in: .capsule)
                            } else {
                                view.background(in: .capsule)
                            }
                        }
                        .padding(8)
                }
            }
    }
}

/// ViewModifier that enables views to have a fade in effect.
struct FadeInModifier: ViewModifier {
    @State private var opacity: Double = 0

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5)) {
                    opacity = 1
                }
            }
    }
}

#Preview {
    GameCard(game: .constant(placeholderGame(type: Game.self)))
        .environmentObject(NetworkMonitor.shared)
}
