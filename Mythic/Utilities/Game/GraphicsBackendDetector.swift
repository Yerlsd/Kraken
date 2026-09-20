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

        // Check DXVK availability
        if isDXVKAvailable(for: runtimeID) {
            available.insert(.dxvk)
        }

        // Check D3DMetal availability
        if isD3DMetalAvailable(for: runtimeID) {
            available.insert(.d3dmetal)
        }

        // Check DXMT availability
        if isDXMTAvailable(for: runtimeID) {
            available.insert(.dxmt)
        }

        return available
    }

    /// Check if DXVK is available for this runtime.
    private static func isDXVKAvailable(for runtimeID: RuntimeID) -> Bool {
        switch runtimeID {
        case .mythicEngine, .wine11:
            return runtimeID.providesDXVK

        case .gptk:
            return false
        }
    }

    /// Check if D3DMetal is available.
    private static func isD3DMetalAvailable(for runtimeID: RuntimeID) -> Bool {
        switch runtimeID {
        case .mythicEngine, .wine11:
            // Stock Wine 11 and Engine 2 default do not provide D3DMetal
            return false

        case .gptk:
            return GPTKInstaller.isInstalled(for: runtimeID)
        }
    }

    /// Check if DXMT is available.
    private static func isDXMTAvailable(for runtimeID: RuntimeID) -> Bool {
        switch runtimeID {
        case .mythicEngine, .gptk:
            return false

        case .wine11:
            // DXMT is currently not packaged in Wine 11
            return false
        }
    }
}
