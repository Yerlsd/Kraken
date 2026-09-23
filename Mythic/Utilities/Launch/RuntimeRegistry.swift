//
//  RuntimeRegistry.swift
//  Kraken
//
// Copyright © 2026 Kraken contributors
//

import Foundation

/// Defines the architectural family to which a runtime belongs.
enum RuntimeFamily: String, Codable, Equatable, Hashable, Sendable {
    case mythicEngine = "mythic-engine"
    case wine11 = "wine-11"
    case gptk = "gptk"
}

/// Declares the technical capabilities provided by a runtime.
struct RuntimeCapabilities: OptionSet, Codable, Equatable, Hashable, Sendable {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let providesDXVK = RuntimeCapabilities(rawValue: 1 << 0)
    static let providesD3DMetal = RuntimeCapabilities(rawValue: 1 << 1)
    static let providesWineD3D = RuntimeCapabilities(rawValue: 1 << 2)
    static let providesDXMT = RuntimeCapabilities(rawValue: 1 << 3)
    static let requiresExplicitLoader = RuntimeCapabilities(rawValue: 1 << 4)
}

/// Immutable descriptor providing identity, metadata, and structural layout for a runtime.
struct RuntimeDescriptor: Equatable, Hashable, Sendable, Identifiable {
    let id: RuntimeID
    let family: RuntimeFamily
    let displayName: String
    let technicalName: String
    let capabilities: RuntimeCapabilities
    let baseDirectory: URL

    init(
        id: RuntimeID,
        family: RuntimeFamily,
        displayName: String,
        technicalName: String,
        capabilities: RuntimeCapabilities,
        baseDirectory: URL
    ) {
        self.id = id
        self.family = family
        self.displayName = displayName
        self.technicalName = technicalName
        self.capabilities = capabilities
        self.baseDirectory = baseDirectory
    }
}

/// Verification result for a runtime installation.
enum RuntimeVerificationStatus: Equatable, Hashable, Sendable {
    case verified
    case notInstalled
    case missingComponents([String])
    case architectureIncompatible(String)
}

struct RuntimeVerificationResult: Equatable, Hashable, Sendable {
    let runtimeID: RuntimeID
    let status: RuntimeVerificationStatus
    let baseDirectory: URL
    let missingPaths: [String]

    var isReady: Bool {
        status == .verified
    }
}

/// Manifest defining the structure, version, and required components of a runtime package.
struct RuntimeManifest: Equatable, Hashable, Sendable {
    let id: RuntimeID
    let family: RuntimeFamily
    let technicalVersion: String
    let requiredRelativePaths: [String]
    let supportedGraphicsBackends: [GraphicsBackend]

    init(
        id: RuntimeID,
        family: RuntimeFamily,
        technicalVersion: String,
        requiredRelativePaths: [String],
        supportedGraphicsBackends: [GraphicsBackend]
    ) {
        self.id = id
        self.family = family
        self.technicalVersion = technicalVersion
        self.requiredRelativePaths = requiredRelativePaths
        self.supportedGraphicsBackends = supportedGraphicsBackends
    }

    /// Verification against a given base directory.
    func verify(at baseDirectory: URL) -> RuntimeVerificationResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: baseDirectory.path) else {
            return RuntimeVerificationResult(
                runtimeID: id,
                status: .notInstalled,
                baseDirectory: baseDirectory,
                missingPaths: [baseDirectory.path]
            )
        }

        var missing: [String] = []
        for relPath in requiredRelativePaths {
            let fullPath = baseDirectory.appending(path: relPath).path
            if !fm.fileExists(atPath: fullPath) {
                missing.append(relPath)
            }
        }

        if missing.isEmpty {
            return RuntimeVerificationResult(
                runtimeID: id,
                status: .verified,
                baseDirectory: baseDirectory,
                missingPaths: []
            )
        } else {
            return RuntimeVerificationResult(
                runtimeID: id,
                status: .missingComponents(missing),
                baseDirectory: baseDirectory,
                missingPaths: missing
            )
        }
    }
}

/// Protocol implemented by providers responsible for resolving and probing concrete runtimes.
protocol RuntimeProvider: Sendable {
    var id: RuntimeID { get }
    var descriptor: RuntimeDescriptor { get }
    var manifest: RuntimeManifest { get }
    func isInstalled() -> Bool
    func verify() -> RuntimeVerificationResult
    func resolveRuntime() -> WineRuntime
}

extension RuntimeProvider {
    func verify() -> RuntimeVerificationResult {
        manifest.verify(at: descriptor.baseDirectory)
    }
}

// MARK: - Concrete Providers

/// Provider for the legacy Mythic Engine 2 (Wine 7.7) runtime.
struct MythicEngineRuntimeProvider: RuntimeProvider {
    let id: RuntimeID = .mythicEngine
    let rootDirectory: URL

    init(rootDirectory: URL = Engine.directory) {
        self.rootDirectory = rootDirectory
    }

    var descriptor: RuntimeDescriptor {
        .init(
            id: .mythicEngine,
            family: .mythicEngine,
            displayName: RuntimeID.mythicEngine.displayName,
            technicalName: "Engine 2 · Legacy",
            capabilities: [.providesDXVK, .providesWineD3D],
            baseDirectory: rootDirectory
        )
    }

    var manifest: RuntimeManifest {
        .init(
            id: .mythicEngine,
            family: .mythicEngine,
            technicalVersion: "7.7-mythic",
            requiredRelativePaths: [
                "wine/bin/wine64",
                "wine/bin/wineserver"
            ],
            supportedGraphicsBackends: [.dxvk, .wined3d]
        )
    }

    func isInstalled() -> Bool {
        let runtime = resolveRuntime()
        let fm = FileManager.default
        return fm.fileExists(atPath: runtime.wineExecutable.path) &&
               fm.fileExists(atPath: runtime.wineserverExecutable.path)
    }

    func resolveRuntime() -> WineRuntime {
        .init(
            id: .mythicEngine,
            rootDirectory: rootDirectory,
            wineBundleURL: nil,
            wineExecutable: rootDirectory.appending(path: "wine/bin/wine64"),
            wineserverExecutable: rootDirectory.appending(path: "wine/bin/wineserver")
        )
    }
}

/// Provider for the side-by-side Wine 11 runtime (Engine 3).
struct Wine11RuntimeProvider: RuntimeProvider {
    let id: RuntimeID = .wine11
    let rootDirectory: URL

    init(rootDirectory: URL = Engine.runtimeDirectory.appending(path: "wine11")) {
        self.rootDirectory = rootDirectory
    }

    var descriptor: RuntimeDescriptor {
        .init(
            id: .wine11,
            family: .wine11,
            displayName: "Wine 11",
            technicalName: "Engine 3 · Modern",
            capabilities: [.providesDXVK, .providesWineD3D, .providesD3DMetal, .providesDXMT, .requiresExplicitLoader],
            baseDirectory: rootDirectory
        )
    }

    var manifest: RuntimeManifest {
        .init(
            id: .wine11,
            family: .wine11,
            technicalVersion: "11.0_1",
            requiredRelativePaths: [
                "Wine Stable.app/Contents/Resources/wine/bin/wine",
                "Wine Stable.app/Contents/Resources/wine/bin/wineserver",
                "Wine Stable.app/Contents/Resources/wine/bin/wineboot",
                "Wine Stable.app/Contents/Resources/wine/lib/wine/x86_64-unix/ntdll.so",
                "Wine Stable.app/Contents/Resources/wine/lib/wine/x86_64-windows/wined3d.dll"
            ],
            supportedGraphicsBackends: [.dxvk, .wined3d, .d3dmetal, .dxmt]
        )
    }

    func isInstalled() -> Bool {
        let runtime = resolveRuntime()
        let fm = FileManager.default
        guard fm.fileExists(atPath: runtime.wineExecutable.path),
              fm.fileExists(atPath: runtime.wineserverExecutable.path),
              let bundleURL = runtime.wineBundleURL else {
            return false
        }
        let wineRoot = bundleURL.appending(path: "Contents/Resources/wine")
        let requiredPaths = [
            wineRoot.appending(path: "bin/wineboot"),
            wineRoot.appending(path: "lib/wine/x86_64-unix/ntdll.so"),
            wineRoot.appending(path: "lib/wine/x86_64-windows/wined3d.dll")
        ]
        return requiredPaths.allSatisfy { fm.fileExists(atPath: $0.path) }
    }

    func resolveRuntime() -> WineRuntime {
        let wineBundleURL = rootDirectory.appending(path: "Wine Stable.app")
        let wineRoot = wineBundleURL.appending(path: "Contents/Resources/wine")
        return .init(
            id: .wine11,
            rootDirectory: rootDirectory,
            wineBundleURL: wineBundleURL,
            wineExecutable: wineRoot.appending(path: "bin/wine"),
            wineserverExecutable: wineRoot.appending(path: "bin/wineserver")
        )
    }
}

/// Provider for the isolated GPTK 4 runtime.
struct GPTKRuntimeProvider: RuntimeProvider {
    let id: RuntimeID = .gptk
    let rootDirectory: URL

    init(rootDirectory: URL = Engine.runtimeDirectory.appending(path: "gptk")) {
        self.rootDirectory = rootDirectory
    }

    var descriptor: RuntimeDescriptor {
        .init(
            id: .gptk,
            family: .gptk,
            displayName: "GPTK 4",
            technicalName: "Game Porting Toolkit 4",
            capabilities: [.providesD3DMetal, .providesWineD3D],
            baseDirectory: rootDirectory
        )
    }

    var manifest: RuntimeManifest {
        .init(
            id: .gptk,
            family: .gptk,
            technicalVersion: "4.0-beta2",
            requiredRelativePaths: [
                "wine/bin/wine64",
                "wine/bin/wineserver"
            ],
            supportedGraphicsBackends: [.d3dmetal, .wined3d]
        )
    }

    func isInstalled() -> Bool {
        let runtime = resolveRuntime()
        let fm = FileManager.default
        return fm.fileExists(atPath: runtime.wineExecutable.path) &&
               fm.fileExists(atPath: runtime.wineserverExecutable.path)
    }

    func resolveRuntime() -> WineRuntime {
        .init(
            id: .gptk,
            rootDirectory: rootDirectory,
            wineBundleURL: nil,
            wineExecutable: rootDirectory.appending(path: "wine/bin/wine64"),
            wineserverExecutable: rootDirectory.appending(path: "wine/bin/wineserver")
        )
    }
}

// MARK: - Mock Provider for Unit Testing

/// Mock provider that allows unit tests to simulate runtime installation and resolution without disk dependencies.
struct MockRuntimeProvider: RuntimeProvider {
    let id: RuntimeID
    let descriptor: RuntimeDescriptor
    var installed: Bool
    var customRuntime: WineRuntime

    init(
        id: RuntimeID,
        displayName: String = "Mock Runtime",
        installed: Bool = true,
        rootDirectory: URL = URL(fileURLWithPath: "/tmp/mock_runtime")
    ) {
        self.id = id
        self.installed = installed
        self.descriptor = .init(
            id: id,
            family: .mythicEngine,
            displayName: displayName,
            technicalName: "Mock",
            capabilities: [.providesDXVK, .providesWineD3D],
            baseDirectory: rootDirectory
        )
        self.customRuntime = .init(
            id: id,
            rootDirectory: rootDirectory,
            wineBundleURL: nil,
            wineExecutable: rootDirectory.appending(path: "wine/bin/wine64"),
            wineserverExecutable: rootDirectory.appending(path: "wine/bin/wineserver")
        )
    }

    var manifest: RuntimeManifest {
        .init(
            id: id,
            family: descriptor.family,
            technicalVersion: "mock-1.0",
            requiredRelativePaths: [],
            supportedGraphicsBackends: [.dxvk, .wined3d]
        )
    }

    func isInstalled() -> Bool {
        installed
    }

    func verify() -> RuntimeVerificationResult {
        RuntimeVerificationResult(
            runtimeID: id,
            status: installed ? .verified : .notInstalled,
            baseDirectory: descriptor.baseDirectory,
            missingPaths: []
        )
    }

    func resolveRuntime() -> WineRuntime {
        customRuntime
    }
}

// MARK: - Central Runtime Registry

/// Central registry managing runtime providers and offering deterministic lookup.
struct RuntimeRegistry: Sendable {
    static let shared = RuntimeRegistry()

    private let providers: [RuntimeID: any RuntimeProvider]

    init(providers: [any RuntimeProvider] = [
        MythicEngineRuntimeProvider(),
        Wine11RuntimeProvider(),
        GPTKRuntimeProvider()
    ]) {
        var map: [RuntimeID: any RuntimeProvider] = [:]
        for provider in providers {
            map[provider.id] = provider
        }
        self.providers = map
    }

    func provider(for id: RuntimeID) -> (any RuntimeProvider)? {
        providers[id]
    }

    func descriptor(for id: RuntimeID) -> RuntimeDescriptor? {
        providers[id]?.descriptor
    }

    func manifest(for id: RuntimeID) -> RuntimeManifest? {
        providers[id]?.manifest
    }

    func verify(for id: RuntimeID) -> RuntimeVerificationResult {
        guard let provider = providers[id] else {
            return RuntimeVerificationResult(
                runtimeID: id,
                status: .notInstalled,
                baseDirectory: URL(fileURLWithPath: "/"),
                missingPaths: ["unregistered provider"]
            )
        }
        return provider.verify()
    }

    func resolveRuntime(for id: RuntimeID) -> WineRuntime {
        guard let provider = providers[id] else {
            return MythicEngineRuntimeProvider().resolveRuntime()
        }
        return provider.resolveRuntime()
    }

    func isInstalled(_ id: RuntimeID) -> Bool {
        providers[id]?.isInstalled() ?? false
    }

    var allDescriptors: [RuntimeDescriptor] {
        RuntimeID.allCases.compactMap { descriptor(for: $0) }
    }
}
