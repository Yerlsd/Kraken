//
//  GameDataStore.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 2/12/2025.
//

// Copyright © 2023-2025 vapidinfinity

import Foundation
import SwiftUI
import Combine
import Observation
import OSLog

// TODO: eventually, migrate to SwiftData.
@Observable @MainActor final class GameDataStore {
    static let shared: GameDataStore = .init()
    let log: Logger = .custom(category: "GameDataStore")

    /// Key holding the encoded game library.
    static let libraryKey: String = "games"

    /// Health of the persisted library, as observed at load time.
    enum PersistenceState: Equatable {
        /// The stored library was absent or decoded completely.
        case healthy

        /// Some records decoded; `lostRecords` did not.
        case partiallyReadable(lostRecords: Int)

        /// A payload is present but nothing could be decoded from it.
        case unreadable

        var isDegraded: Bool { self != .healthy }
    }

    private let store: UserDefaults
    private let gamesObserver: CodableUserDefaultsObserver<[AnyGame]>
    private var isUpdatingFromObserver = false

    /// Whether writing the library back to disk is currently allowed.
    ///
    /// Writes are suspended whenever the stored payload was not fully readable.
    /// Persisting in that state would replace real user data with whatever
    /// subset happened to decode — which is precisely how a library gets lost.
    private(set) var persistenceState: PersistenceState = .healthy

    /// Description of the most recent persistence problem, for surfacing in UI.
    private(set) var persistenceFailureDescription: String?

    /// Location of the backup taken of an unreadable payload, if one was made.
    private(set) var recoveredPayloadURL: URL?

    var isPersistenceSuspended: Bool { persistenceState.isDegraded }

    @ObservationIgnored
    private var observedGameObjects: Set<ObjectIdentifier> = []

    @ObservationIgnored
    private var cancellables: Set<AnyCancellable> = .init()

    var library: Set<Game> = .init() {
        didSet {
            reconcileGameObservers()

            guard !isUpdatingFromObserver else { return }

            persistLibrary()
        }
    }

    @MainActor init(store: UserDefaults = .standard) {
        self.store = store

        // Resiliently load first, so one bad record cannot blank the library.
        let loaded = Self.loadLibrary(from: store, log: .custom(category: "GameDataStore"))

        gamesObserver = .init(
            key: Self.libraryKey,
            defaultValue: [],
            store: store,
            initialValue: loaded.games,
            isStoredValueMalformed: loaded.state.isDegraded
        )

        persistenceState = loaded.state
        persistenceFailureDescription = loaded.failureDescription

        // Property observers do not fire for assignments made inside `init`,
        // so this load cannot trigger a write back over the stored payload.
        library = Set(loaded.games.map({ $0.base }))

        reconcileGameObservers()

        if loaded.state.isDegraded, let payload = loaded.rawPayload {
            recoveredPayloadURL = Self.backUpUnreadablePayload(
                payload,
                log: log
            )
            log.error("""
                Library persistence suspended: \(String(describing: loaded.state), privacy: .public). \
                Game state will not be written until this is resolved.
                """)
        }

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

        // Observe runtime degradation: external corruption can be detected after
        // init, and GameDataStore's persistenceState must track it to prevent
        // overwriting the malformed stored payload.
        gamesObserver.$isStoredValueMalformed
            .sink { [weak self] isMalformed in
                guard let self else { return }
                // Only transition healthy → degraded, never degrade → healthy.
                // Recovery must be explicit through authoriseLibraryRewrite().
                guard isMalformed, !self.persistenceState.isDegraded else { return }

                self.persistenceState = .unreadable
                self.log.error("""
                    Runtime corruption detected in stored game library. \
                    Persistence suspended to protect existing data.
                    """)

                // Back up the newly-detected malformed payload if possible.
                if let data = self.store.data(forKey: Self.libraryKey) {
                    self.recoveredPayloadURL = Self.backUpUnreadablePayload(data, log: self.log)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Loading

    private struct LoadResult {
        var games: [AnyGame]
        var state: PersistenceState
        var failureDescription: String?
        var rawPayload: Data?
    }

    private static func loadLibrary(from store: UserDefaults, log: Logger) -> LoadResult {
        guard let data = store.data(forKey: libraryKey) else {
            // A fresh installation legitimately has no library yet.
            return .init(games: [], state: .healthy, failureDescription: nil, rawPayload: nil)
        }

        do {
            let decoded = try GameLibraryCoder.decodeResilient(from: data)

            if decoded.isComplete {
                return .init(games: decoded.games, state: .healthy, failureDescription: nil, rawPayload: data)
            }

            let reasons = decoded.failures
                .prefix(3)
                .map(\.localizedDescription)
                .joined(separator: "; ")

            if decoded.games.isEmpty {
                log.error("No game records could be decoded (\(decoded.unreadableRecordCount, privacy: .public) present).")
                return .init(
                    games: [],
                    state: .unreadable,
                    failureDescription: reasons,
                    rawPayload: data
                )
            }

            log.error("""
                \(decoded.unreadableRecordCount, privacy: .public) game record(s) could not be decoded; \
                \(decoded.games.count, privacy: .public) recovered.
                """)
            return .init(
                games: decoded.games,
                state: .partiallyReadable(lostRecords: decoded.unreadableRecordCount),
                failureDescription: reasons,
                rawPayload: data
            )
        } catch {
            log.error("Stored game library is not readable: \(error.localizedDescription, privacy: .public)")
            return .init(
                games: [],
                state: .unreadable,
                failureDescription: error.localizedDescription,
                rawPayload: data
            )
        }
    }

    /// Copy an unreadable payload aside so it is recoverable by hand.
    private static func backUpUnreadablePayload(_ data: Data, log: Logger) -> URL? {
        guard let appHome = Bundle.appHome else { return nil }

        let directory = appHome.appending(path: "Recovered")
        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let destination = directory.appending(path: "games-\(stamp).plist")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            log.notice("Unreadable game library backed up to \(destination.prettyPath, privacy: .public)")
            return destination
        } catch {
            log.error("Unable to back up unreadable game library: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Persistence

    private func persistLibrary() {

        guard !isPersistenceSuspended else {
            /*
             Deliberate no-op. The stored payload holds records we could not
             decode; writing the decoded subset would delete them permanently.
             `authoriseLibraryRewrite()` is the explicit opt-in.
             */
            log.error("""
                Refusing to persist the game library while the stored payload is \
                not fully readable (\(String(describing: self.persistenceState), privacy: .public)).
                """)
            return
        }


        do {
            try store.encodeAndSet(
                library.map({ AnyGame($0) }),
                forKey: Self.libraryKey
            )
            persistenceFailureDescription = nil
        } catch {
            persistenceFailureDescription = error.localizedDescription
            log.error(
                "Unable to persist game library: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Explicitly allow the in-memory library to overwrite an unreadable payload.
    ///
    /// Only call this from a user-initiated recovery action, and only after the
    /// payload has been backed up — records that failed to decode are dropped.
    func authoriseLibraryRewrite() {
        guard isPersistenceSuspended else { return }

        log.notice("""
            Library rewrite authorised; \
            \(String(describing: self.persistenceState), privacy: .public) payload will be replaced.
            """)
        persistenceState = .healthy
        persistLibrary()
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

    // MARK: - Bindings

    /// Creates a binding to a game in the library by its ID.
    /// Changes to the binding will update the actual game in the library and trigger persistence.
    func binding(for gameID: String) -> Binding<Game>? {
        guard let game = library.first(where: { $0.id == gameID }) else {
            return nil
        }

        return Binding(
            get: {
                self.library.first(where: { $0.id == gameID })!
            },
            set: { updatedGame in
                self.library.remove(game)
                self.library.insert(updatedGame)
            }
        )
    }
}
