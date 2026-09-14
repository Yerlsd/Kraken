//
//  Runtime.swift
//  Mythic
//

// Copyright © 2026 Kraken contributors

import Foundation

/// Stable identity for a game runtime supported by Kraken.
enum RuntimeID: String, Codable, Equatable, Hashable, Sendable {
    case mythicEngine = "mythic-engine"
}

/// Data describing a runtime available to Kraken.
///
/// Runtime is intentionally data-only. The existing Mythic Engine remains
/// the implementation associated with `RuntimeID.mythicEngine`.
struct Runtime: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: RuntimeID
    let name: String

    static let mythicEngine = Runtime(id: .mythicEngine, name: "Mythic Engine")
    static let current = mythicEngine
}

extension Engine {
    /// Stable runtime identity represented by the existing Engine implementation.
    static let runtimeID: RuntimeID = .mythicEngine
}
