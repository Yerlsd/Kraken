//
//  ContainerReference.swift
//  Mythic
//
// Copyright © 2026 Kraken contributors

import Foundation

/// Lightweight reference from a game launch profile to an existing Wine prefix.
///
/// The physical prefix URL remains the canonical identity for this milestone.
/// The existing `Wine.Container` implementation continues to own metadata
/// and container settings.
struct ContainerReference: Codable, Equatable, Hashable, Sendable {
    let url: URL

    init(url: URL) {
        self.url = url
    }
}
