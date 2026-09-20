//
//  GraphicsBackendDetector.swift
//  Kraken
//
// Copyright © 2026 Kraken contributors

import Foundation

/// Detects which graphics backends are available for a runtime.
struct GraphicsBackendDetector {
    /// Determine which backends can be used with the given runtime.
    static func availableBackends(for runtimeID: RuntimeID) -> Set<GraphicsBackend> {
        var available: Set<GraphicsBackend> = [.wined3d] // Always available
        let capabilities = RuntimeRegistry.shared.descriptor(for: runtimeID)?.capabilities ?? []

        // Check DXVK availability
        if isDXVKAvailable(for: runtimeID, capabilities: capabilities) {
            available.insert(.dxvk)
        }

        // Check D3DMetal availability
        if isD3DMetalAvailable(for: runtimeID, capabilities: capabilities) {
            available.insert(.d3dmetal)
        }

        // Check DXMT availability
        if isDXMTAvailable(for: runtimeID, capabilities: capabilities) {
            available.insert(.dxmt)
        }

        return available
    }

    /// Check if DXVK is available for this runtime.
    private static func isDXVKAvailable(for runtimeID: RuntimeID, capabilities: RuntimeCapabilities) -> Bool {
        capabilities.contains(.providesDXVK)
    }

    /// Check if D3DMetal is available.
    private static func isD3DMetalAvailable(for runtimeID: RuntimeID, capabilities: RuntimeCapabilities) -> Bool {
        guard capabilities.contains(.providesD3DMetal) else { return false }
        return GPTKInstaller.isInstalled(for: runtimeID)
    }

    /// Check if DXMT is available.
    private static func isDXMTAvailable(for runtimeID: RuntimeID, capabilities: RuntimeCapabilities) -> Bool {
        // DXMT is currently not packaged in Wine 11
        return false
    }
}
