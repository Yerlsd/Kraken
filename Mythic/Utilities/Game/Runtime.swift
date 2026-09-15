//
//  Runtime.swift
//  Mythic
//

// Copyright © 2026 Kraken contributors

import Foundation
import SemanticVersion

/// Stable identity for a game runtime supported by Kraken.
enum RuntimeID: String, Codable, Equatable, Hashable, Sendable {
    /// The existing Mythic Engine 2 runtime.
    case mythicEngine = "mythic-engine"

    /// The side-by-side Wine 11 runtime used by Engine 3.
    case wine11 = "wine-11"
}

/// Data describing a runtime available to Kraken.
struct Runtime: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: RuntimeID
    let name: String

    static let mythicEngine = Runtime(id: .mythicEngine, name: "Mythic Engine")
    static let wine11 = Runtime(id: .wine11, name: "Wine 11")

    /// Existing behaviour remains the default until Engine 3 is installed and validated.
    static let current = mythicEngine
}

/// Filesystem locations belonging to a concrete Wine runtime.
struct WineRuntime: Equatable, Sendable {
    let id: RuntimeID
    let rootDirectory: URL
    let wineBundleURL: URL?
    let wineExecutable: URL
    let wineserverExecutable: URL
}

extension Engine {
    static let runtimeID: RuntimeID = .mythicEngine

    /// Runtime storage is kept outside the monolithic Engine 2 directory because
    /// Engine 2 installation/update/removal replaces that directory wholesale.
    static let runtimeDirectory = Bundle.appHome!.appending(path: "Runtimes")

    static func wineRuntime(for runtimeID: RuntimeID) -> WineRuntime {
        switch runtimeID {
        case .mythicEngine:
            return .init(
                id: .mythicEngine,
                rootDirectory: directory,
                wineBundleURL: nil,
                wineExecutable: directory.appending(path: "wine/bin/wine64"),
                wineserverExecutable: directory.appending(path: "wine/bin/wineserver")
            )
        case .wine11:
            let rootDirectory = runtimeDirectory.appending(path: "wine11")
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

    static func isRuntimeInstalled(_ runtimeID: RuntimeID) -> Bool {
        let runtime = wineRuntime(for: runtimeID)
        return FileManager.default.fileExists(atPath: runtime.wineExecutable.path)
            && FileManager.default.fileExists(atPath: runtime.wineserverExecutable.path)
    }

    /// Install the first Engine 3 runtime without touching the existing Engine 2 installation.
    static func installWine11Runtime() async throws {
        try await WineRuntimeInstaller.install()
    }

    struct RuntimeNotInstalledError: LocalizedError {
        let runtimeID: RuntimeID

        var errorDescription: String? {
            switch runtimeID {
            case .mythicEngine:
                return String(localized: "Mythic Engine is not installed.")
            case .wine11:
                return String(localized: "Wine 11 runtime is not installed.")
            }
        }
    }
}

extension Wine {
    /// Resolves the Wine version for a specific runtime.
    static func retrieveVersion(for runtimeID: RuntimeID) -> SemanticVersion? {
        guard Engine.isRuntimeInstalled(runtimeID) else { return nil }

        let process: Process = .init()
        process.arguments = ["--version"]
        process.executableURL = Engine.wineRuntime(for: runtimeID).wineExecutable

        let result = try? process.runWrapped()
        guard let standardOutput = result?.standardOutput,
              let match = try? Regex(#"wine-(\S+)"#).firstMatch(in: standardOutput),
              let extractedVersion = match.last?.substring else {
            return nil
        }

        return SemanticVersion(fromRelaxedString: .init(extractedVersion))
    }

    /// Runtime-aware replacement for the legacy Engine 2 process transformation.
    static func transformProcess(
        _ process: Process,
        containerURL: URL,
        runtimeID: RuntimeID
    ) throws {
        guard Engine.isRuntimeInstalled(runtimeID) else {
            throw Engine.RuntimeNotInstalledError(runtimeID: runtimeID)
        }

        let runtime = Engine.wineRuntime(for: runtimeID)
        process.executableURL = runtime.wineExecutable

        var environment = process.environment ?? [:]
        environment["WINEPREFIX"] = containerURL.path

        if runtimeID == .wine11 {
            environment["WINESERVER"] = runtime.wineserverExecutable.path
            environment["WINELOADER"] = runtime.wineExecutable.path
            environment["WINE"] = runtime.wineExecutable.path
            environment["WINE64"] = runtime.wineExecutable.path
            if let bundleURL = runtime.wineBundleURL {
                environment["WINE_APP_BUNDLE"] = bundleURL.path
            }
        }

        process.environment = environment
    }
}
