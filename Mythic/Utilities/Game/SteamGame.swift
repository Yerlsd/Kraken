//
//  SteamGame.swift
//  Kraken
//
// Copyright © 2026 Kraken contributors
//

import Foundation
import AppKit
import OSLog

/// A game sourced from or configured for the Steam platform.
///
/// Follows the single launch architecture:
/// Game → LaunchProfile → LaunchPlan → LaunchSession
final class SteamGame: Game, @unchecked Sendable {
    override var storefront: Storefront? { .steam }

    var appId: String { id }

    var installDir: String? {
        guard case .installed(let location, _) = installationState else { return nil }
        return location.deletingLastPathComponent().lastPathComponent
    }

    override var computedVerticalImageURL: URL? {
        URL(string: "https://steamcdn-a.akamaihd.net/steam/apps/\(id)/library_600x900_2x.jpg")
    }

    override var computedHorizontalImageURL: URL? {
        URL(string: "https://steamcdn-a.akamaihd.net/steam/apps/\(id)/header.jpg")
    }

    init(
        appId: String,
        title: String,
        installationState: InstallationState,
        containerURL: URL? = nil
    ) {
        super.init(
            id: appId,
            title: title,
            installationState: installationState,
            containerURL: containerURL
        )
    }

    // MARK: - Codable

    required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
    }

    // MARK: - Lifecycle & Execution

    override func _checkIfGameIsRunning(location: URL, platform: Platform) -> Bool {
        switch platform {
        case .macOS:
            return NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL == location })
        case .windows:
            return ProcessMonitor.shared.isGameRunning(gameId: self.id)
        }
    }

    @MainActor override func _launch() async throws {
        try await SteamGameManager.launch(game: self)
    }

    override func _update() async throws {
        // Steam handles updates through its client or protocol
        Logger.app.info("Update requested for Steam game \(self.id).")
    }

    @MainActor override func _move(
        from currentLocation: URL,
        to newLocation: URL
    ) async throws {
        try await SteamGameManager.move(game: self, to: newLocation)
    }

    @MainActor override func _verifyInstallation() async throws {
        guard case .installed(let location, _) = installationState else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard FileManager.default.fileExists(atPath: location.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
    }
}
