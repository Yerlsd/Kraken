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

/// Downloads and installs the pinned macOS Wine 11 runtime into a private staging
/// directory before replacing the active runtime.
private final class WineRuntimeInstaller {
    private static let runtimeID: RuntimeID = .wine11
    private static let archiveURL = URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz")!
    private static let expectedSHA256 = "b50dc50ec7f41d58b115a6b685d4d1315ba3c797bd3aa0f49213f2703cb82388"

    private static var parentDirectory: URL { Engine.runtimeDirectory }
    private static var runtimeRoot: URL { Engine.wineRuntime(for: runtimeID).rootDirectory }

    private static func verifySHA256(of fileURL: URL) throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }

        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
            throw RuntimeInstallError.checksumMismatch(expected: expectedSHA256, actual: digest)
        }
    }

    private static func findWineBundle(in stagingDirectory: URL) throws -> URL {
        let direct = stagingDirectory.appending(path: "Wine Stable.app")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }

        let enumerator = FileManager.default.enumerator(
            at: stagingDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == "Wine Stable.app" { return url }
        }

        throw RuntimeInstallError.invalidArchive
    }

    private static func validateWineBundle(at bundleURL: URL) throws {
        let wine = bundleURL.appending(path: "Contents/Resources/wine/bin/wine")
        let wineserver = bundleURL.appending(path: "Contents/Resources/wine/bin/wineserver")
        guard FileManager.default.isExecutableFile(atPath: wine.path),
              FileManager.default.isExecutableFile(atPath: wineserver.path) else {
            throw RuntimeInstallError.missingRuntimeFiles
        }
    }

    static func install() async throws {
        #if arch(arm64)
        guard Rosetta.exists else { throw RuntimeInstallError.rosettaRequired }
        #endif

        if Engine.isRuntimeInstalled(runtimeID), Wine.retrieveVersion(for: runtimeID) != nil {
            return
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        let stagingDirectory = try fileManager.url(
            for: .itemReplacementDirectory,
            in: parentDirectory,
            appropriateFor: parentDirectory,
            create: true
        )
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        let archiveFile = stagingDirectory.appending(path: "wine-stable-11.0_1-osx64.tar.xz")
        let extractionDirectory = stagingDirectory.appending(path: "extracted")
        try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)

        let (downloadURL, response) = try await URLSession.shared.download(from: archiveURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        try fileManager.moveItem(at: downloadURL, to: archiveFile)

        try verifySHA256(of: archiveFile)

        let extractProcess = Process()
        extractProcess.executableURL = URL(filePath: "/usr/bin/tar")
        extractProcess.arguments = ["-xJf", archiveFile.path, "-C", extractionDirectory.path]
        _ = try await extractProcess.runWrapped()
        try extractProcess.checkTerminationStatus()

        let bundleURL = try findWineBundle(in: extractionDirectory)
        try validateWineBundle(at: bundleURL)

        let validationProcess = Process()
        validationProcess.executableURL = bundleURL.appending(path: "Contents/Resources/wine/bin/wine")
        validationProcess.arguments = ["--version"]
        let result = try await validationProcess.runWrapped()
        try validationProcess.checkTerminationStatus()
        guard result.standardOutput?.contains("11.0") == true else {
            throw RuntimeInstallError.unexpectedWineVersion(result.standardOutput ?? "")
        }

        let stagedBundle = stagingDirectory.appending(path: "Wine Stable.app")
        try fileManager.moveItem(at: bundleURL, to: stagedBundle)
        try validateWineBundle(at: stagedBundle)

        let installedBundle = runtimeRoot.appending(path: "Wine Stable.app")
        let backupBundle = runtimeRoot.appending(path: "Wine Stable.app.previous")
        try fileManager.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: backupBundle.path) {
            try fileManager.removeItem(at: backupBundle)
        }
        if fileManager.fileExists(atPath: installedBundle.path) {
            try fileManager.moveItem(at: installedBundle, to: backupBundle)
        }

        do {
            try fileManager.moveItem(at: stagedBundle, to: installedBundle)
            try validateWineBundle(at: installedBundle)
        } catch {
            try? fileManager.removeItem(at: installedBundle)
            if fileManager.fileExists(atPath: backupBundle.path) {
                try? fileManager.moveItem(at: backupBundle, to: installedBundle)
            }
            throw error
        }

        if fileManager.fileExists(atPath: backupBundle.path) {
            try fileManager.removeItem(at: backupBundle)
        }
    }

    private enum RuntimeInstallError: LocalizedError {
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
