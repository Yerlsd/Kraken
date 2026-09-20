//
//  GraphicsBackendResolver.swift
//  Kraken
//
// Copyright © 2026 Kraken contributors

import Foundation

/// Resolves which graphics backend to use for a game launch.
struct GraphicsBackendResolver {
    /// Resolve the backend to use for this launch.
    ///
    /// Resolution order:
    /// 1. Explicit user choice (must be available or fail)
    /// 2. Previously successful backend (if still available)
    /// 3. Capability-based selection
    /// 4. WineD3D fallback
    static func resolve(
        profile: LaunchProfile,
        runtimeID: RuntimeID
    ) throws -> GraphicsBackend {
        let available = GraphicsBackendDetector.availableBackends(for: runtimeID)

        // Tier 1: Explicit user choice
        if profile.graphicsBackend != .automatic {
            let requested = profile.graphicsBackend
            guard available.contains(requested) else {
                throw BackendUnavailableError(
                    backend: requested,
                    runtimeID: runtimeID,
                    available: available
                )
            }
            return requested
        }

        // Tier 2: Previously successful backend
        if let last = profile.lastSuccessfulBackend, available.contains(last) {
            return last
        }

        // Tier 3: Capability-based selection
        let ranked = rankBackends(available, for: runtimeID)
        if let best = ranked.first {
            return best
        }

        // Tier 4: Safe fallback
        return .wined3d
    }

    /// Rank available backends by preference for this runtime.
    private static func rankBackends(
        _ available: Set<GraphicsBackend>,
        for runtimeID: RuntimeID
    ) -> [GraphicsBackend] {
        var ranked: [GraphicsBackend] = []

        switch runtimeID {
        case .gptk:
            // GPTK runtime prefers D3DMetal with WineD3D fallback
            if available.contains(.d3dmetal) { ranked.append(.d3dmetal) }
            if available.contains(.wined3d) { ranked.append(.wined3d) }

        case .mythicEngine:
            // Engine 2 prefers DXVK with WineD3D fallback
            if available.contains(.dxvk) { ranked.append(.dxvk) }
            if available.contains(.wined3d) { ranked.append(.wined3d) }

        case .wine11:
            // Wine 11 prefers DXMT -> DXVK -> WineD3D
            if available.contains(.dxmt) { ranked.append(.dxmt) }
            if available.contains(.dxvk) { ranked.append(.dxvk) }
            if available.contains(.wined3d) { ranked.append(.wined3d) }
        }

        return ranked
    }

    /// Error when a requested backend is not available.
    struct BackendUnavailableError: LocalizedError {
        let backend: GraphicsBackend
        let runtimeID: RuntimeID
        let available: Set<GraphicsBackend>

        var errorDescription: String? {
            let availableNames = available.map(\.displayName).sorted().joined(separator: ", ")
            return String(localized: """
                \(backend.displayName) is not available for \(Runtime.displayName(for: runtimeID)). \
                Available backends: \(availableNames).
                """)
        }

        var recoverySuggestion: String? {
            return String(localized: "Select a different graphics backend or use Automatic.")
        }
    }
}
