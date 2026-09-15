//
//  Runtime.swift
//  Mythic
//

// Copyright © 2026 Kraken contributors

import Foundation

/// Stable identity for a game runtime supported by Kraken.
enum RuntimeID: String, Codable, Equatable, Hashable, Sendable {
    /// The existing Mythic Engine 2 runtime.
    case mythicEngine = "mythic-engine"

    /// The side-by-side Wine 11 runtime used by Engine 3.
    case wine11 = "wine-11"
}

/// Data describing a runtime available to Kraken.
///
/// Runtime is intentionally data-only. It does not inspect the filesystem or
/// launch processes; those responsibilities belong to Engine/Wine runtime
/// services.
struct Runtime: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: RuntimeID
    let name: String

    static let mythicEngine = Runtime(id: .mythicEngine, name: "Mythic Engine")
    static let wine11 = Runtime(id: .wine11, name: "Wine 11")

    /// Existing behaviour remains the default until Engine 3 is installed and validated.
    static let current = mythicEngine
}

extension Engine {
    /// Stable runtime identity represented by the existing Engine 2 implementation.
    static let runtimeID: RuntimeID = .mythicEngine
}
