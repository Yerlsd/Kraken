//
//  WineRuntimeInstaller.swift
//  Mythic
//
// Copyright © 2026 Kraken contributors

import CryptoKit
import Foundation

/// Installs the pinned macOS Wine 11 runtime used by Engine 3.
///
/// The installer downloads and verifies the archive in a staging directory,
/// validates the Wine loader pair, then atomically replaces the active bundle.
/// Engine 2 is never modified by this type.
final class WineRuntimeInstaller {
    static let runtimeID: RuntimeID = .wine11

    static let archiveURL = URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz")!
    static let expectedSHA256 = "b50dc50ec7f41d58b115a6b685d4d1315ba3c797bd3aa0f49213f2703cb82388"

    private static var parentDirectory: URL { Engine.runtimeDirectory }
    private static var runtimeRoot: URL { Engine.wineRuntime(for: runtimeID).rootDirectory }

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
        try extract(archive: archiveFile, into: extractionDirectory)

        let extractedBundle = try findWineBundle(in: extractionDirectory)
        try validateWineBundle(at: extractedBundle)
        try validateWineVersion(at: extractedBundle)

        let stagedBundle = stagingDirectory.appending(path: "Wine Stable.app")
        try fileManager.moveItem(at: extractedBundle, to: stagedBundle)
        try validateWineBundle(at: stagedBundle)

        try fileManager.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)

        let installedBundle = runtimeRoot.appending(path: "Wine Stable.app")
        let backupBundle = runtimeRoot.appending(path: "Wine Stable.app.previous")

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

        try? fileManager.removeItem(at: backupBundle)
    }

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

    private static func extract(archive: URL, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/tar")
        process.arguments = ["-xJf", archive.path, "-C", directory.path]
        _ = try process.runWrapped()
        try process.checkTerminationStatus()
    }

    private static func findWineBundle(in directory: URL) throws -> URL {
        let direct = directory.appending(path: "Wine Stable.app")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw RuntimeInstallError.invalidArchive
        }

        while let url = enumerator.nextObject() as? URL {
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

    private static func validateWineVersion(at bundleURL: URL) throws {
        let process = Process()
        process.executableURL = bundleURL.appending(path: "Contents/Resources/wine/bin/wine")
        process.arguments = ["--version"]
        let result = try process.runWrapped()
        try process.checkTerminationStatus()

        guard result.standardOutput?.contains("11.0") == true else {
            throw RuntimeInstallError.unexpectedWineVersion(result.standardOutput ?? "")
        }
    }

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
