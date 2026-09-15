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

/// Filesystem locations belonging to a concrete Wine runtime.
///
/// This type is deliberately data-only. Runtime discovery and installation are
/// handled by `Engine`; this type only carries resolved executable locations to
/// the process-launch layer.
struct WineRuntime: Equatable, Sendable {
    let id: RuntimeID
    let rootDirectory: URL
    let wineExecutable: URL
    let wineserverExecutable: URL
}

extension Engine {
    /// Stable runtime identity represented by the existing Engine 2 implementation.
    static let runtimeID: RuntimeID = .mythicEngine

    /// Root directory reserved for runtimes managed independently from the
    /// monolithic Engine 2 installation. Keeping this outside `Engine.directory`
    /// prevents Engine 2 install/update/remove operations from deleting Engine 3.
    static let runtimeDirectory = Bundle.appHome!.appending(path: "Runtimes")

    /// Resolves the executable layout for a runtime without changing or touching it.
    ///
    /// Engine 2 retains its existing `wine64` path. Engine 3 uses Wine 11's
    /// unified `wine` loader and therefore deliberately does not reuse the
    /// legacy `wine64` path.
    static func wineRuntime(for runtimeID: RuntimeID) -> WineRuntime {
        switch runtimeID {
        case .mythicEngine:
            return .init(
                id: .mythicEngine,
                rootDirectory: directory,
                wineExecutable: directory.appending(path: "wine/bin/wine64"),
                wineserverExecutable: directory.appending(path: "wine/bin/wineserver")
            )
        case .wine11:
            let rootDirectory = runtimeDirectory.appending(path: "wine11")
            return .init(
                id: .wine11,
                rootDirectory: rootDirectory,
                wineExecutable: rootDirectory.appending(path: "bin/wine"),
                wineserverExecutable: rootDirectory.appending(path: "bin/wineserver")
            )
        }
    }

    /// Returns whether the runtime's primary loader is present on disk.
    static func isRuntimeInstalled(_ runtimeID: RuntimeID) -> Bool {
        FileManager.default.fileExists(atPath: wineRuntime(for: runtimeID).wineExecutable.path)
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
    /// Resolves the Wine version for a specific runtime without changing the
    /// legacy Engine 2 `retrieveVersion()` API.
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
    ///
    /// The existing two-argument overload is intentionally untouched so Engine 2
    /// callers retain their exact behaviour. Engine 3 callers opt into this path
    /// explicitly through a `RuntimeID`.
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
            // Keep Wine 11 self-contained instead of allowing a system or other
            // runtime's wineserver to be selected accidentally.
            environment["WINESERVER"] = runtime.wineserverExecutable.path
            environment["WINELOADER"] = runtime.wineExecutable.path
        }

        process.environment = environment
    }
}
