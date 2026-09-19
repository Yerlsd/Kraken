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
        case .mythicEngine:
            // Engine 2 bundles DXVK
            return runtimeID.providesDXVK

        case .wine11:
            // Wine 11: check if DXVK DLLs are installed
            let runtime = Engine.wineRuntime(for: runtimeID)
            guard let bundleURL = runtime.wineBundleURL else { return false }

            let dxvkPath = bundleURL.appending(path: "Contents/Resources/wine/lib/wine/x86_64-windows/d3d11.dll")

            // Check if it's a DXVK DLL (different size/signature than Wine's built-in)
            guard FileManager.default.fileExists(atPath: dxvkPath.path) else { return false }

            // TODO: Distinguish DXVK DLL from Wine's built-in d3d11.dll
            // For now, assume Wine 11 does not bundle DXVK
            return false
        }
    }

    /// Check if D3DMetal is available.
    private static func isD3DMetalAvailable(for runtimeID: RuntimeID) -> Bool {
        switch runtimeID {
        case .mythicEngine:
            // Engine 2 does not use D3DMetal
            return false

        case .wine11:
            // Check for D3DMetal.framework in Wine 11 runtime
            let runtime = Engine.wineRuntime(for: runtimeID)
            guard let bundleURL = runtime.wineBundleURL else { return false }

            let frameworkPath = bundleURL.appending(
                path: "Contents/Resources/wine/lib/external/D3DMetal.framework"
            )

            return FileManager.default.fileExists(atPath: frameworkPath.path)
        }
    }

    /// Check if DXMT is available.
    private static func isDXMTAvailable(for runtimeID: RuntimeID) -> Bool {
        switch runtimeID {
        case .mythicEngine:
            // Engine 2 does not use DXMT
            return false

        case .wine11:
            // Check for DXMT .so files in Wine 11 runtime
            let runtime = Engine.wineRuntime(for: runtimeID)
            guard let bundleURL = runtime.wineBundleURL else { return false }

            let dxmtPath = bundleURL.appending(
                path: "Contents/Resources/wine/lib/wine/x86_64-unix/d3d11.so"
            )

            return FileManager.default.fileExists(atPath: dxmtPath.path)
        }
    }
}
