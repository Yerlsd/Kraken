//
//  Runtime.swift
//  Mythic
//

// Copyright © 2026 Kraken contributors

import CryptoKit
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
    let wineBundleURL: URL?
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
    /// Engine 2 retains its existing `wine64` path. The Engine 3 Wine 11 package
    /// is distributed as a Wine Stable.app bundle and uses Wine's unified `wine`
    /// loader inside the bundle resources.
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

    /// Returns whether the runtime has the complete loader pair needed for
    /// normal Wine execution.
    static func isRuntimeInstalled(_ runtimeID: RuntimeID) -> Bool {
        let runtime = wineRuntime(for: runtimeID)
        return FileManager.default.fileExists(atPath: runtime.wineExecutable.path)
            && FileManager.default.fileExists(atPath: runtime.wineserverExecutable.path)
    }

    /// Installs the first Engine 3 runtime: the verified macOS Wine 11.0_1 build.
    ///
    /// This deliberately does not modify Engine 2, does not create or migrate
    /// prefixes, and does not change the active runtime for any game.
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
            if let wineBundleURL = runtime.wineBundleURL {
                environment["WINE"] = runtime.wineExecutable.path
                environment["WINE64"] = runtime.wineExecutable.path
                environment["WINE_APP_BUNDLE"] = wineBundleURL.path
            }
        }

        process.environment = environment
    }
}

/// Downloads and installs the Engine 3 Wine 11 runtime into a private staging
/// directory before replacing the active runtime atomically.
final class WineRuntimeInstaller {
    private static let runtimeID: RuntimeID = .wine11
    private static let version = "11.0_1"
    private static let archiveURL = URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz")!
    private static let expectedSHA256 = "b50dc50ec7f41d58b115a6b685d4d1315ba3c797bd3aa0f49213f2703cb82388"

    private static var runtimeRoot: URL {
        Engine.wineRuntime(for: runtimeID).rootDirectory
    }

    private static var parentDirectory: URL {
        Engine.runtimeDirectory
    }

    private static func verifySHA256(of fileURL: URL) throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }

        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
            throw RuntimeInstallError.checksumMismatch(expected: expectedSHA256, actual: digest)
        }
    }

    private static func findWineBundle(in stagingDirectory: URL) throws -> URL {
        let expected = stagingDirectory.appending(path: "Wine Stable.app")
        if FileManager.default.fileExists(atPath: expected.path) {
            return expected
        }

        let enumerator = FileManager.default.enumerator(
            at: stagingDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == "Wine Stable.app" {
                return url
            }
        }

        throw RuntimeInstallError.invalidArchive
    }

    private static func validateWineBundle(at bundleURL: URL) throws {
        let wineExecutable = bundleURL.appending(path: "Contents/Resources/wine/bin/wine")
        let wineserverExecutable = bundleURL.appending(path: "Contents/Resources/wine/bin/wineserver")

        guard FileManager.default.fileExists(atPath: wineExecutable.path),
              FileManager.default.fileExists(atPath: wineserverExecutable.path) else {
            throw RuntimeInstallError.missingRuntimeFiles
        }
    }

    private static func removeItemIfExists(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func install() async throws {
        #if arch(arm64)
        guard Rosetta.exists else { throw RuntimeInstallError.rosettaRequired }
        #endif

        let runtime = Engine.wineRuntime(for: runtimeID)
        if Engine.isRuntimeInstalled(runtimeID), Wine.retrieveVersion(for: runtimeID) != nil {
            return
        }

        let fileManager = FileManager.default
        let temporaryDirectory = try fileManager.url(
            for: .itemReplacementDirectory,
            in: parentDirectory,
            appropriateFor: parentDirectory,
            create: true
        )
        let archiveURL = temporaryDirectory.appending(path: "wine-stable-11.0_1-osx64.tar.xz")
        let extractionDirectory = temporaryDirectory.appending(path: "extracted")
        let installedBundleTarget = runtimeRoot.appending(path: "Wine Stable.app")

        defer {
            try? fileManager.removeItem(at: temporaryDirectory)
        }

        try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runtime.parentDirectory, withIntermediateDirectories: true)

        let (downloadedURL, response) = try await URLSession.shared.download(from: archiveURLURL)
        _ = response
        try fileManager.moveItem(at: downloadedURL, to: archiveURL)

        try verifySHA256(of: archiveURL)

        let extractProcess: Process = .init()
        extractProcess.executableURL = URL(filePath: "/usr/bin/tar")
        extractProcess.arguments = ["-xJf", archiveURL.path, "-C", extractionDirectory.path]
        _ = try await extractProcess.runWrapped()
        try extractProcess.checkTerminationStatus()

        let bundleURL = try findWineBundle(in: extractionDirectory)
        try validateWineBundle(at: bundleURL)

        let validationProcess: Process = .init()
        validationProcess.arguments = ["--version"]
        validationProcess.executableURL = bundleURL.appending(path: "Contents/Resources/wine/bin/wine")
        let validationResult = try await validationProcess.runWrapped()
        try validationProcess.checkTerminationStatus()
        guard validationResult.standardOutput?.contains("11.0") == true else {
            throw RuntimeInstallError.unexpectedWineVersion(validationResult.standardOutput ?? "")
        }

        let stagingBundle = temporaryDirectory.appending(path: "Wine Stable.app")
        try fileManager.moveItem(at: bundleURL, to: stagingBundle)
        try validateWineBundle(at: stagingBundle)

        let backupBundle = runtimeRoot.appending(path: "Wine Stable.app.previous")
        try fileManager.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        try removeItemIfExists(backupBundle)

        if fileManager.fileExists(atPath: installedBundleTarget.path) {
            try fileManager.moveItem(at: installedBundleTarget, to: backupBundle)
        }

        do {
            try fileManager.moveItem(at: stagingBundle, to: installedBundleTarget)
            try validateWineBundle(at: installedBundleTarget)
        } catch {
            try? removeItemIfExists(installedBundleTarget)
            if fileManager.fileExists(atPath: backupBundle.path) {
                try? fileManager.moveItem(at: backupBundle, to: installedBundleTarget)
            }
            throw error
        }

        try? removeItemIfExists(backupBundle)
        _ = version
    }

    private static let archiveURLURL = archiveURL

    enum RuntimeInstallError: LocalizedError {
        case rosettaRequired
        case checksumMismatch(expected: String, actual: String)
        case invalidArchive
        case missingRuntimeFiles
        case unexpectedWineVersion(String)

        var errorDescription: String? {
            switch self {
            case .rosettaRequired:
                return String(localized: "Wine 11 requires Rosetta 2 on Apple silicon. Install Rosetta 2 before installing this runtime.")
            case let .checksumMismatch(expected, actual):
                return String(localized: "Wine 11 runtime checksum verification failed. Expected \(expected), received \(actual).")
            case .invalidArchive:
                return String(localized: "The Wine 11 runtime archive did not contain a Wine Stable application bundle.")
            case .missingRuntimeFiles:
                return String(localized: "The Wine 11 runtime archive is missing its Wine loader or wineserver.")
            case let .unexpectedWineVersion(output):
                return String(localized: "The downloaded runtime did not report Wine 11.0. Output: \(output)")
            }
        }
    }
}
