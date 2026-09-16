//
//  WhatsNewCollection.swift
//  Kraken
//
//  Created by vapidinfinity (esi) on 11/9/24.
//

// Copyright © 2023-2025 vapidinfinity

import WhatsNewKit
import SwiftUI

extension KrakenApp: @MainActor WhatsNewCollectionProvider {
    var whatsNewCollection: WhatsNewCollection {
        WhatsNew(
            version: "0.6.0",
            title: "Welcome to Kraken",
            features: [
                .init(
                    image: .init(systemName: "sparkles"),
                    title: "A cleaner Kraken",
                    subtitle: "The library, game settings, and everyday navigation are being rebuilt around a simpler, calmer experience."
                ),
                .init(
                    image: .init(systemName: "square.grid.2x2"),
                    title: "A better game library",
                    subtitle: "Grid and list layouts are being streamlined so your games stay readable and easy to scan."
                ),
                .init(
                    image: .init(systemName: "play.circle"),
                    title: "Made for launching games",
                    subtitle: "Kraken keeps the important actions close while moving technical controls out of the way."
                ),
                .init(
                    image: .init(systemName: "slider.horizontal.3"),
                    title: "Compatibility controls when you need them",
                    subtitle: "Advanced runtime and container options remain available without overwhelming the normal game setup."
                ),
                .init(
                    image: .init(systemName: "hammer"),
                    title: "Built as Kraken",
                    subtitle: "This branch is the foundation for Kraken's own launcher experience while retaining the existing engine underneath."
                )
            ],
            primaryAction: .init(),
            secondaryAction: .init(
                title: "Learn more",
                action: .openURL(.init(string: "https://github.com/Yerlsd/Kraken"))
            )
        )

        // Historical entries are intentionally retained so existing installations
        // can continue to resolve previously displayed release notes.
        WhatsNew(
            version: "0.5.0",
            title: "What's new in Kraken",
            features: [
                .init(image: .init(systemName: "ladybug"), title: "Bug Fixes & Performance Improvements", subtitle: "A fair bit of bugfixes this time around."),
                .init(image: .init(systemName: "macwindow"), title: "Brand New Interface", subtitle: "Kraken now uses Apple's new 'Liquid Glass' design language."),
                .init(image: .init(systemName: "figure.wave"), title: "Overhauled Onboarding Experience", subtitle: "Reimagined for speed and ease-of-use."),
                .init(image: .init(systemName: "macwindow.and.pointer.arrow"), title: "Improved View Responsiveness", subtitle: "Smoother scrolling, snappier animations, happier everyone!!"),
                .init(image: .init(systemName: "curlybraces"), title: "Codebase Improvements", subtitle: "Refactored for Swift 6 safety and swiftness.")
            ],
            primaryAction: .init(),
            secondaryAction: .init(
                title: "Learn more",
                action: .openURL(.init(string: "https://github.com/Yerlsd/Kraken/releases/tag/v0.5.0"))
            )
        )

        // TODO: Continue consolidating older release notes as the launcher reaches
        // a stable public release. Do not remove entries until migration behaviour
        // is verified against existing installations.
    }
}

#Preview {
    WhatsNewView(whatsNew: KrakenApp().whatsNewCollection.first ?? WhatsNew(title: "N/A", features: []))
}
