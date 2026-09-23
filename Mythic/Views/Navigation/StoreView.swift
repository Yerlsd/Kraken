//
//  StoreView.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 10/9/2023.
//

// Copyright © 2023-2025 vapidinfinity

import SwiftUI
import SwordRPC

struct StoreView: View {
    @StateObject private var browser = StoreBrowserController()
    @State private var storeError: Error?
    private let storeURL = URL(string: "https://store.epicgames.com/")

    @CodableAppStorage("epicGamesWebDataStore") var epicGamesWebDataStore: UUID = .init()

    var body: some View {
        Group {
            if let storeURL {
                WebView(
                    url: storeURL,
                    datastore: .init(forIdentifier: epicGamesWebDataStore),
                    browser: browser,
                    error: $storeError
                )
                .overlay {
                    if let storeError {
                        ContentUnavailableView(
                            "Store unavailable",
                            systemImage: "wifi.exclamationmark",
                            description: Text(storeError.localizedDescription)
                        )
                        .padding()
                    }
                }
            } else {
                ContentUnavailableView("Store unavailable", systemImage: "storefront")
            }
        }
        .navigationTitle("Store")

        .task(priority: .background) {
            discordRPC.setPresence({
                var presence: RichPresence = .init()
                presence.details = "Browsing the Epic Games Store"
                presence.state = "Looking for games to purchase"
                presence.timestamps.start = .now
                presence.assets.largeImage = "macos_512x512_2x"
                
                return presence
            }())
        }
        
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    browser.goBack()
                } label: {
                    Image(systemName: "arrow.left")
                        .symbolVariant(.circle)
                }
                .disabled(!browser.canGoBack)
                .help("Go Back")
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    browser.goForward()
                } label: {
                    Image(systemName: "arrow.right")
                        .symbolVariant(.circle)
                }
                .disabled(!browser.canGoForward)
                .help("Go Forward")
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    storeError = nil
                    browser.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .symbolVariant(.circle)
                }
                .help("Reload Store")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    if let storeURL = browser.currentURL ?? storeURL {
                        NSWorkspace.shared.open(storeURL)
                    }
                } label: {
                    Image(systemName: "arrow.up.forward")
                }
                .help("Open Store in Browser")
            }
        }
    }
}

#Preview {
    StoreView()
}
