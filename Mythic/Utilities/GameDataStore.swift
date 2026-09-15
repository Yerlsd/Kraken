//
//  GameDataStore.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 2/12/2025.
//

// Copyright © 2023-2025 vapidinfinity

import Foundation
import Combine
import Observation
import OSLog

// TODO: eventually, migrate to SwiftData.
@Observable @MainActor final class GameDataStore {
    static let shared: GameDataStore = .init()
    let log: Logger = .custom(category: "GameDataStore")
    
    private let gamesObserver: CodableUserDefaultsObserver<[AnyGame]>
    private var isUpdatingFromObserver = false

    @ObservationIgnored
    private var observedGameObjects: Set<ObjectIdentifier> = []
    
    var library: Set<Game> = .init() {
        didSet {
            reconcileGameObservers()

            guard !isUpdatingFromObserver else { return }

            persistLibrary()
        }
    }

    @MainActor private init() {
        // initialise observer
        gamesObserver = .init(key: "games",
                              defaultValue: [])
        
        // load library on initialisation
        library = Set(gamesObserver.value.map({ $0.base }))

        reconcileGameObservers()

        // observe external changes
        gamesObserver.$value
            .sink { [weak self] newGames in
                guard let self else { return }
                let newLibrary = Set(newGames.map({ $0.base }))
                
                guard newLibrary != self.library else { return }
                self.log.debug("Games key changed in UserDefaults, updating library")
                
                self.isUpdatingFromObserver = true
                defer { self.isUpdatingFromObserver = false }
                self.library = newLibrary
            }
            .store(in: &cancellables)
    }
    
    @ObservationIgnored
    private var cancellables: Set<AnyCancellable> = .init()

    private func persistLibrary() {
        do {
            try UserDefaults.standard.encodeAndSet(
                library.map({ AnyGame($0) }),
                forKey: "games"
            )
        } catch {
            log.error(
                "Unable to persist game library: \(error.localizedDescription)"
            )
        }
    }

    private func reconcileGameObservers() {
        let currentIDs = Set(library.map(ObjectIdentifier.init))

        observedGameObjects.formIntersection(currentIDs)

        for game in library {
            let objectID = ObjectIdentifier(game)

            guard !observedGameObjects.contains(objectID) else {
                continue
            }

            observedGameObjects.insert(objectID)
            observeGameChanges(for: game)
        }
    }

    private func observeGameChanges(for game: Game) {
        let gameID = game.id

        withObservationTracking {
            _ = game.title
            _ = game.installationState
            _ = game.launchProfile
            _ = game.isFavourited
            _ = game.lastLaunched
            _ = game._verticalImageURL
            _ = game._horizontalImageURL
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }

                guard let game = self.library.first(where: { $0.id == gameID }) else {
                    return
                }

                self.persistLibrary()
                self.observeGameChanges(for: game)
            }
        }
    }

    var recent: Game? {
        guard !library.allSatisfy({ $0.lastLaunched == nil }) else { return nil }

        return library.max {
            $0.lastLaunched ?? .distantPast < $1.lastLaunched ?? .distantPast
        }
    }

    func refreshFromStorefronts(_ storefronts: Game.Storefront...) async throws {
        GameListViewModel.shared.isUpdatingLibrary = true
        defer {
            GameListViewModel.shared.isUpdatingLibrary = false
        }
        
        // if variadics are empty, default to all cases
        let storefronts = storefronts.isEmpty ? Game.Storefront.allCases : storefronts as [Game.Storefront]
        
        // legendary (epic games)
        if storefronts.contains(.epicGames) {
            do {
                let installables = try Legendary.getInstallableGames()
                let installed = try Legendary.getInstalledGames()
                
                // add installables that aren't installed
                for game in installables where !installed.contains(where: { $0 == game }) {
                    library.update(with: game)
                }
                
                // installed: merge instead of overwrite
                for fetchedGame in installed {
                    if let existing = library.first(where: { $0 == fetchedGame }) {
                        try existing.merge(with: fetchedGame, requiring: .identicalIgnoredKeys)
                        library.update(with: existing)
                    } else {
                        library.update(with: fetchedGame)
                    }
                }
            } catch {
                log.error("Unable to refresh game data from Epic Games: \(error.localizedDescription)")
                throw error
            }
        }
        
        // TODO: others
        // if storefronts.contains(...) { ... }
    }
}
