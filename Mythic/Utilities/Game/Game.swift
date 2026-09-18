//
//  Game.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 15/11/2025.
//

// Copyright © 2023-2025 vapidinfinity

import Foundation
import OSLog
import AppKit

/// Per-game configuration describing how the game should be launched.
///
/// This is intentionally data-only. Runtime and backend selection will be
/// introduced separately as Kraken's launcher architecture evolves.
/// Per-game configuration describing how the game should be launched.
///
/// Runtime selection has exactly two meanings, and they are kept distinct:
///
/// - **Automatic** (`runtimeOverride == nil`): the game runs on `defaultRuntimeID`.
///   This is the runtime the game was created with. Nothing but explicit intent
///   changes it — in particular, an Epic metadata refresh must not.
/// - **Manual** (`runtimeOverride != nil`): the game runs on `runtimeOverride`.
///   `defaultRuntimeID` is left untouched, so turning manual mode off always
///   restores the original automatic runtime.
///
/// `effectiveRuntimeID` is deliberately read-only. Runtime changes go through
/// `selectRuntime(_:)`, `clearRuntimeOverride()` or `setDefaultRuntime(_:)` so
/// that no caller can accidentally promote an override into the stored default.
struct LaunchProfile: Codable, Equatable, Sendable {
    /// Runtime used when the user has not made a manual choice.
    private(set) var defaultRuntimeID: RuntimeID

    /// The user's explicit manual runtime choice. `nil` means Automatic.
    private(set) var runtimeOverride: RuntimeID?

    var container: ContainerReference?
    var launchArguments: [String]

    /// Graphics backend selection for Wine 11 games.
    var graphicsBackend: GraphicsBackend

    /// Last backend that successfully launched this game.
    /// Used by automatic selection to prefer previously working backends.
    private(set) var lastSuccessfulBackend: GraphicsBackend?

    /// The runtime that will actually be used to launch this game.
    ///
    /// Read-only: a manual override takes precedence, otherwise the stored
    /// default is used. Mutate via the explicit runtime methods below.
    var effectiveRuntimeID: RuntimeID { runtimeOverride ?? defaultRuntimeID }

    /// `true` when the user has pinned this game to a specific runtime.
    var isManualRuntimeSelection: Bool { runtimeOverride != nil }

    /// Pin this game to `runtimeID`. Does not touch `defaultRuntimeID`.
    mutating func selectRuntime(_ runtimeID: RuntimeID) {
        runtimeOverride = runtimeID
    }

    /// Return to Automatic. `defaultRuntimeID` is restored unchanged.
    mutating func clearRuntimeOverride() {
        runtimeOverride = nil
    }

    /// Change the runtime used in Automatic mode. Explicit callers only.
    mutating func setDefaultRuntime(_ runtimeID: RuntimeID) {
        defaultRuntimeID = runtimeID
    }

    init(
        container: ContainerReference? = nil,
        defaultRuntimeID: RuntimeID = Runtime.current.id,
        runtimeOverride: RuntimeID? = nil,
        launchArguments: [String] = [],
        graphicsBackend: GraphicsBackend = .automatic,
        lastSuccessfulBackend: GraphicsBackend? = nil
    ) {
        self.container = container
        self.defaultRuntimeID = defaultRuntimeID
        self.runtimeOverride = runtimeOverride
        self.launchArguments = launchArguments
        self.graphicsBackend = graphicsBackend
        self.lastSuccessfulBackend = lastSuccessfulBackend
    }

    /// Select a specific graphics backend for this game.
    mutating func selectGraphicsBackend(_ backend: GraphicsBackend) {
        graphicsBackend = backend
    }

    /// Record that a backend successfully launched this game.
    mutating func recordSuccessfulLaunch(backend: GraphicsBackend) {
        lastSuccessfulBackend = backend
    }

    /// Merge two argument lists preserving first-occurrence order.
    ///
    /// A command line is ordered, so `Set` must never be used here; deduplication
    /// is only applied where it cannot move an argument relative to its neighbours.
    static func mergeLaunchArguments(_ current: [String], _ new: [String]) -> [String] {
        var seen: Set<String> = .init()
        var merged: [String] = []
        merged.reserveCapacity(current.count + new.count)

        for argument in current + new where seen.insert(argument).inserted {
            merged.append(argument)
        }

        return merged
    }

    // On-disk format is unchanged: `runtimeID` still stores the automatic
    // runtime, so existing libraries decode without migration.
    private enum CodingKeys: String, CodingKey {
        case container
        case containerURL
        case runtimeID
        case runtimeOverride
        case launchArguments
        case graphicsBackend
        case lastSuccessfulBackend
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.container = try container.decodeIfPresent(ContainerReference.self, forKey: .container)
            ?? container.decodeIfPresent(URL.self, forKey: .containerURL).map(ContainerReference.init(url:))
        self.defaultRuntimeID = try container.decodeIfPresent(RuntimeID.self, forKey: .runtimeID) ?? .mythicEngine
        self.runtimeOverride = try container.decodeIfPresent(RuntimeID.self, forKey: .runtimeOverride)
        // Lenient: a profile written before launch arguments existed must still
        // decode rather than failing the whole library.
        self.launchArguments = try container.decodeIfPresent([String].self, forKey: .launchArguments) ?? []
        self.graphicsBackend = try container.decodeIfPresent(GraphicsBackend.self, forKey: .graphicsBackend) ?? .automatic
        self.lastSuccessfulBackend = try container.decodeIfPresent(GraphicsBackend.self, forKey: .lastSuccessfulBackend)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.container, forKey: .container)
        try container.encode(defaultRuntimeID, forKey: .runtimeID)
        try container.encodeIfPresent(runtimeOverride, forKey: .runtimeOverride)
        try container.encode(launchArguments, forKey: .launchArguments)
        try container.encode(graphicsBackend, forKey: .graphicsBackend)
        try container.encodeIfPresent(lastSuccessfulBackend, forKey: .lastSuccessfulBackend)
    }
}

@Observable class Game: Codable, Identifiable {
    @MainActor static let operationManager: GameOperationManager = .shared

    let id: String
    var title: String
    var installationState: InstallationState

    var storefront: Storefront? {
        assertionFailure("Storefront must always be populated by subclasses, when accessed.")
        return nil
    }

    /// Canonical per-game launch configuration.
    var launchProfile: LaunchProfile

    /// Transitional compatibility accessor. `launchProfile.container` is the canonical source of truth.
    final var containerURL: URL? {
        get { launchProfile.container?.url }
        set { launchProfile.container = newValue.map(ContainerReference.init(url:)) }
    }

    var isUpdateAvailable: Bool? { nil } // override in subclass

    // swiftlint:disable:next identifier_name
    internal var _verticalImageURL: URL? // underlying storage for custom images
    var verticalImageURL: URL? { _verticalImageURL ?? computedVerticalImageURL }
    internal var computedVerticalImageURL: URL? { nil } // override in subclass — Auto-synthesized (default) image URL

    // swiftlint:disable:next identifier_name
    internal var _horizontalImageURL: URL? // underlying storage for custom images
    var horizontalImageURL: URL? { _horizontalImageURL ?? computedHorizontalImageURL }
    internal var computedHorizontalImageURL: URL? { nil } // override in subclass — Auto-synthesized (default) image URL

    /// Transitional compatibility accessor. `launchProfile` is the canonical source of truth.
    var launchArguments: [String] {
        get { launchProfile.launchArguments }
        set { launchProfile.launchArguments = newValue }
    }
    final var isFavourited: Bool = false
    final var lastLaunched: Date?

    // override in subclass
    func getSupportedPlatforms() -> Set<Game.Platform>? { return nil }

    init(id: String,
         title: String,
         installationState: InstallationState,
         containerURL: URL? = nil) {
        self.id = id
        self.title = title
        self.installationState = installationState

        self.launchProfile = .init(
            container: containerURL.map(ContainerReference.init(url:))
        )
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.installationState = try container.decode(InstallationState.self, forKey: .installationState)
        self._verticalImageURL = try container.decodeIfPresent(URL.self, forKey: ._verticalImageURL)
        self._horizontalImageURL = try container.decodeIfPresent(URL.self, forKey: ._horizontalImageURL)

        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let legacyContainerURL = try legacyContainer.decodeIfPresent(URL.self, forKey: ._containerURL)
        let legacyLaunchArguments = try legacyContainer.decodeIfPresent([String].self, forKey: .launchArguments)

        self.launchProfile = try container.decodeIfPresent(LaunchProfile.self, forKey: .launchProfile)
            ?? .init(
                container: legacyContainerURL.map(ContainerReference.init(url:)),
                defaultRuntimeID: .mythicEngine,
                launchArguments: legacyLaunchArguments ?? []
            )
        self.isFavourited = try container.decodeIfPresent(Bool.self, forKey: .isFavourited) ?? false
        self.lastLaunched = try container.decodeIfPresent(Date.self, forKey: .lastLaunched)
    }

    final var isFallbackImageAvailable: Bool {
        guard case .installed(_, let platform) = installationState else {
            return false
        }

        switch platform {
        case .macOS:    return true
        case .windows:  return false
        }
    }

    // MARK: Actions
    @MainActor final var isOperating: Bool {
        Game.operationManager.queue.first(where: {
            $0.game == self && $0.isExecuting
        }) != nil
    }

    final func checkIfGameIsRunning() -> Bool {
        guard case .installed(let location, let platform) = installationState else { return false }
        return _checkIfGameIsRunning(location: location, platform: platform)
    }

    /// Launch the underlying game.
    @MainActor final func launch() async throws {
        guard case .installed = installationState else {
            throw CocoaError(.fileNoSuchFile)
        }

        lastLaunched = .now
        try await _launch()
    }

    @MainActor final func update() async throws {
        guard case .installed = installationState else {
            throw CocoaError(.fileNoSuchFile)
        }

        guard isUpdateAvailable == true else { return }

        try await _update()
    }

    /// Move the underlying game to a specified `URL`.
    @MainActor final func move(to newLocation: URL) async throws {
        guard case .installed(let currentLocation, _) = installationState else {
            throw CocoaError(.fileNoSuchFile)
        }

        try await _move(from: currentLocation,
                        to: newLocation)
    }

    /// Verify the file integrity of the game (if it's installed)
    @MainActor final func verifyInstallation() async throws {
        guard case .installed = installationState else {
            throw CocoaError(.fileNoSuchFile)
        }

        try await _verifyInstallation()
    }

    // MARK: Overrideable Actions

    // override in subclass
    func _checkIfGameIsRunning(location: URL, platform: Platform) -> Bool {
        // swiftlint:disable:previous identifier_name
        Logger.app.warning("""
            _checkIfGameIsRunning() called on \(self).
            This means that the subclass calling this method does not have an override,
            Or that this method was called from the `Game` base class.
            This is not intended behaviour, and thus, a basic fallback will be used.
            """)

        if case .macOS = platform {
            return NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL == location })
        }

        return false
    }

    // override in subclass
    @MainActor internal func _launch() async throws {
        // swiftlint:disable:previous identifier_name
        fatalError("Subclasses must implement _launch()")
    }

    // override in subclass
    @MainActor internal func _update() async throws {
        // swiftlint:disable:previous identifier_name
        fatalError("Subclasses must implement _update()")
    }

    // override in subclass
    @MainActor internal func _move(from currentLocation: URL, // swiftlint:disable:this identifier_name
                                   to newLocation: URL) async throws {
        fatalError("Subclasses must implement _move(to:)")
    }

    // override in subclass
    @MainActor internal func _verifyInstallation() async throws {
        // swiftlint:disable:previous identifier_name
        assertionFailure("Subclasses should implement _verifyInstallation()")
    }
}

extension Game: Equatable {
    public static func == (lhs: Game, rhs: Game) -> Bool {
        return lhs.id == rhs.id
    }
}

extension Game: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Game: CustomStringConvertible {
    var description: String { "\"\(title)\"" }
    var debugDescription: String { "\(description) (\(installationState), \(id))" }
}

// MARK: - Codable Polymorphism Support
extension Game {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id,
             title,
             installationState
        case storefront
        // swiftlint:disable identifier_name
        case _verticalImageURL,
             _horizontalImageURL
        // swiftlint:enable identifier_name
        case launchProfile,
             isFavourited,
             lastLaunched
    }

    private enum LegacyCodingKeys: String, CodingKey {
        // swiftlint:disable identifier_name
        case _containerURL
        // swiftlint:enable identifier_name
        case launchArguments
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(installationState, forKey: .installationState)
        try container.encodeIfPresent(storefront, forKey: .storefront)
        try container.encodeIfPresent(_verticalImageURL, forKey: ._verticalImageURL)
        try container.encodeIfPresent(_horizontalImageURL, forKey: ._horizontalImageURL)
        try container.encode(launchProfile, forKey: .launchProfile)
        try container.encode(isFavourited, forKey: .isFavourited)
        try container.encodeIfPresent(lastLaunched, forKey: .lastLaunched)
    }
}

// note that merges should only be performed with the `identicalIgnoredKeys` requirement enforced.
extension Game: Mergeable {
    typealias MergeKeys = CodingKeys
    
    static var ignoredMergeKeys: Set<CodingKeys> {
        [.id, .title, .storefront]
    }
    
    var mergeRules: [AnyMergeRule] {[
        .init(\Game.installationState, forCodingKey: .installationState, strategy: { max($0, $1) }),
        .init(\Game._verticalImageURL, forCodingKey: ._verticalImageURL, strategy: { $1 ?? $0 }),
        .init(\Game._horizontalImageURL, forCodingKey: ._horizontalImageURL, strategy: { $1 ?? $0 }),
        .init(\Game.launchProfile, forCodingKey: .launchProfile, strategy: { current, new in
            /*
             A storefront refresh carries no runtime opinion, so every runtime
             decision is taken verbatim from `current`. Reading the effective
             runtime here (as this rule previously did) promoted a manual
             override into `defaultRuntimeID`, which permanently stranded the
             game on that runtime once the override was switched off.
             Refreshes are therefore idempotent with respect to runtime state.
             */
            .init(container: current.container ?? new.container,
                  defaultRuntimeID: current.defaultRuntimeID,
                  runtimeOverride: current.runtimeOverride,
                  launchArguments: LaunchProfile.mergeLaunchArguments(
                      current.launchArguments,
                      new.launchArguments
                  ))
        }),
        .init(\Game.isFavourited, forCodingKey: .isFavourited, strategy: { $0 || $1 }),
        AnyMergeRule(\Game.lastLaunched, forCodingKey: .lastLaunched) { current, new in
            guard current != nil || new != nil else { return current }
            return max(current ??  .distantPast, new ?? .distantPast)
        }
    ]}
}

struct AnyGame: Codable, Equatable {
    let base: Game

    init(_ base: Game) {
        self.base = base
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Game.CodingKeys.self)
        let storefront = try container.decodeIfPresent(Game.Storefront.self, forKey: .storefront)

        self.base = try {
            switch storefront {
            case .epicGames:    try EpicGamesGame(from: decoder)
            case .local:        try LocalGame(from: decoder)
            case nil:           try Game(from: decoder)
            }
        }()
    }

    func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
    }
}

@MainActor func placeholderGame<T: Game>(type: T.Type) -> T {
    if type is EpicGamesGame.Type, !Legendary.isSignedIn {
        assertionFailure("""
            You must sign in through a live instance of the app before calling placeholderGame(type:).
            """)
    }

    guard let game = GameDataStore.shared.library.first(where: { ($0 as? T) != nil }) as? T else {
        fatalError("""
            No games are in your library of type \(T.self) to populate placeholderGame.
            """)
    }

    return game as T
}
