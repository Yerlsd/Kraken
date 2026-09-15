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

    /// Runtime-aware process transformation. Existing Engine 2 callers continue
    /// to use WineInterface's legacy overload unchanged.
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

// MARK: - Engine 3 runtime-aware Wine operations

extension Wine {
    struct RuntimeContainerMismatchError: LocalizedError {
        let expected: RuntimeID
        let actual: RuntimeID

        var errorDescription: String? {
            "Container belongs to runtime \(actual.rawValue), but runtime \(expected.rawValue) was requested."
        }
    }

    static func tasklist(for containerURL: URL, runtimeID: RuntimeID) async throws -> [Container.Process] {
        var list: [Container.Process] = []
        let process = Process()
        process.arguments = ["tasklist"]
        try transformProcess(process, containerURL: containerURL, runtimeID: runtimeID)

        let commandResult = try await process.runWrapped()
        guard let standardOutput = commandResult.standardOutput else { return list }

        let major = retrieveVersion(for: runtimeID)?.major ?? 0
        let tasklistRegex: Regex<AnyRegexOutput>?
        // Wine 8+ uses the newer tasklist format. Keep the legacy parser for Engine 2/Wine 7.
        if major > 7 {
            tasklistRegex = try Regex(#"^\s*(?<ImageName>.+?)\s+(?<PID>\d+)\s+(?<SessionName>\S+)\s+(?<SessionNum>\d+)\s+(?<MemUsage>[\d,]+ K)$"#)
        } else {
            tasklistRegex = try Regex(#"(?P<ImageName>[^,]+?),(?P<PID>\d+)"#)
        }

        for line in standardOutput.split(whereSeparator: \.isNewline) {
            guard let match = try tasklistRegex?.wholeMatch(in: line),
                  let extractedImageName = match["ImageName"]?.substring,
                  let extractedPID = match["PID"]?.substring,
                  let castPID = Int(extractedPID) else { continue }

            list.append(.init(
                imageName: String(extractedImageName),
                pid: castPID,
                sessionName: match["SessionName"]?.substring.flatMap(String.init),
                sessionNumber: match["SessionNum"]?.substring.flatMap { Int($0) },
                memoryUsage: match["MemUsage"]?.substring.flatMap { Int($0) }
            ))
        }
        return list
    }

    @discardableResult
    static func boot(
        at containerURL: URL,
        runtimeID: RuntimeID,
        parameters: BootParameter...
    ) async throws -> Process.CommandResult {
        let process = Process()
        process.arguments = ["wineboot"] + parameters.map(\.rawValue)
        try transformProcess(process, containerURL: containerURL, runtimeID: runtimeID)

        let result = try await process.runWrapped()
        try process.checkTerminationStatus()
        return result
    }

    @discardableResult
    static func createContainer(
        baseURL: URL? = containersDirectory,
        name: String,
        settings: Container.Settings = .init(),
        runtimeID: RuntimeID
    ) async throws -> Container {
        guard let baseURL, FileManager.default.fileExists(atPath: baseURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard FileLocations.isWritableFolder(url: baseURL) else { throw CocoaError(.fileWriteUnknown) }
        guard Engine.isRuntimeInstalled(runtimeID) else {
            throw Engine.RuntimeNotInstalledError(runtimeID: runtimeID)
        }

        let url = baseURL.appending(path: name)
        let targetAlreadyExisted = FileManager.default.fileExists(atPath: url.path)

        if targetAlreadyExisted {
            if containerExists(at: url) {
                log.notice("Container already exists at \(url.prettyPath)")
                let container = try Container(knownURL: url)
                guard container.runtimeID == runtimeID else {
                    throw RuntimeContainerMismatchError(expected: runtimeID, actual: container.runtimeID)
                }
                containerURLs.insert(url)
                return container
            }

            throw Container.AlreadyExistsError()
        }

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        defer {
            Task { @MainActor in
                VariableManager.shared.setVariable("booting", value: false)
            }
        }

        await MainActor.run {
            VariableManager.shared.setVariable("booting", value: true)
        }

        do {
            let newContainer = Container(name: name, url: url, settings: settings, runtimeID: runtimeID)
            _ = try await boot(at: url, runtimeID: runtimeID, parameters: .prefixInit)

            containerURLs.insert(url)

            try await toggleRetinaMode(containerURL: url, toggle: settings.retinaMode, runtimeID: runtimeID)
            try await setWindowsVersion(containerURL: url, version: settings.windowsVersion, runtimeID: runtimeID)
            try await setDisplayScaling(containerURL: url, dpi: settings.scaling, runtimeID: runtimeID)

            log.info("\(formatLog(containerURL: url, description: "Created \(runtimeID.rawValue) container"))")
            return newContainer
        } catch {
            containerURLs.remove(url)
            try? FileManager.default.removeItem(at: url)

            log.error("\(formatLog(containerURL: url, description: "Unable to create container", error: error))")
            throw error
        }
    }

    private static func addRegistryKey(
        containerURL: URL,
        key: String,
        name: String,
        data: String,
        type: RegistryType,
        runtimeID: RuntimeID
    ) async throws {
        guard containerExists(at: containerURL) else { throw Container.DoesNotExistError() }
        let process = Process()
        process.arguments = ["reg", "add", key, "-v", name, "-t", type.rawValue, "-d", data, "-f"]
        try transformProcess(process, containerURL: containerURL, runtimeID: runtimeID)
        try process.run()
        process.waitUntilExit()
        try process.checkTerminationStatus()
    }

    static func queryRegistryKey(
        containerURL: URL,
        key: String,
        name: String,
        type: RegistryType,
        runtimeID: RuntimeID
    ) async throws -> String {
        let process = Process()
        process.arguments = ["reg", "query", key, "-v", name]
        try transformProcess(process, containerURL: containerURL, runtimeID: runtimeID)
        let commandResult = try await process.runWrapped()
        try process.checkTerminationStatus()

        if let last = commandResult.standardOutput?
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
            .last {
            return last
        }
        throw UnableToQueryRegistryError()
    }

    static func toggleRetinaMode(containerURL: URL, toggle: Bool, runtimeID: RuntimeID) async throws {
        do {
            try await addRegistryKey(containerURL: containerURL,
                                     key: RegistryKey.macDriver.rawValue,
                                     name: "RetinaMode",
                                     data: toggle ? "y" : "n",
                                     type: .string,
                                     runtimeID: runtimeID)
            try await setDisplayScaling(containerURL: containerURL, dpi: toggle ? 192 : 96, runtimeID: runtimeID)
        } catch {
            log.error("\(formatLog(containerURL: containerURL, description: "Unable to toggle retina mode \(toggle)", error: error))")
            throw error
        }
    }

    static func getRetinaMode(containerURL: URL, runtimeID: RuntimeID) async throws -> Bool {
        let result = try await queryRegistryKey(containerURL: containerURL,
                                                 key: RegistryKey.macDriver.rawValue,
                                                 name: "RetinaMode",
                                                 type: .string,
                                                 runtimeID: runtimeID)
        return result == "y"
    }

    static func getWindowsVersion(containerURL: URL, runtimeID: RuntimeID) async throws -> WindowsVersion? {
        do {
            let process = Process()
            process.arguments = ["winecfg", "-v"]
            try transformProcess(process, containerURL: containerURL, runtimeID: runtimeID)
            let commandResult = try await process.runWrapped()
            try process.checkTerminationStatus()

            let currentVersion: String?
            if retrieveVersion(for: runtimeID)?.major ?? 0 > 7 {
                currentVersion = commandResult.standardError?
                    .split(whereSeparator: \.isNewline)
                    .last.map(String.init)
            } else {
                currentVersion = commandResult.standardOutput?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return WindowsVersion.allCases.first(where: { String(describing: $0) == currentVersion })
        } catch {
            log.error("\(formatLog(containerURL: containerURL, description: "Unable to get windows version", error: error))")
            throw error
        }
    }

    static func setWindowsVersion(containerURL: URL, version: WindowsVersion, runtimeID: RuntimeID) async throws {
        do {
            let process = Process()
            process.arguments = ["winecfg", "-v", String(describing: version)]
            try transformProcess(process, containerURL: containerURL, runtimeID: runtimeID)
            try process.run()
            process.waitUntilExit()
            try process.checkTerminationStatus()
        } catch {
            log.error("\(formatLog(containerURL: containerURL, description: "Unable to set windows version", error: error))")
            throw error
        }
    }

    static func getDisplayScaling(containerURL: URL, runtimeID: RuntimeID) async throws -> Int {
        let result = try await queryRegistryKey(containerURL: containerURL,
                                                 key: RegistryKey.desktop.rawValue,
                                                 name: "LogPixels",
                                                 type: .dword,
                                                 runtimeID: runtimeID)
        return Int(result.trimmingPrefix("0x"), radix: 16) ?? -1
    }

    static func setDisplayScaling(containerURL: URL, dpi: Int, runtimeID: RuntimeID) async throws {
        guard (96...480).contains(dpi) else { return }
        do {
            try await addRegistryKey(containerURL: containerURL,
                                     key: RegistryKey.desktop.rawValue,
                                     name: "LogPixels",
                                     data: String(dpi),
                                     type: .dword,
                                     runtimeID: runtimeID)
        } catch {
            log.error("\(formatLog(containerURL: containerURL, description: "Unable to set display scaling value", error: error))")
            throw error
        }
    }

    static func killAll(runtimeID: RuntimeID, at urls: URL...) throws {
        let urls = urls.isEmpty ? Array(containerURLs) : urls
        let runtime = Engine.wineRuntime(for: runtimeID)

        guard Engine.isRuntimeInstalled(runtimeID) else {
            throw Engine.RuntimeNotInstalledError(runtimeID: runtimeID)
        }

        for url in urls {
            let process = Process()
            process.executableURL = runtime.wineserverExecutable
            process.arguments = ["-k"]
            process.environment = ["WINEPREFIX": url.path]
            process.qualityOfService = .utility
            try process.run()
        }
    }

    static func runWinetricks(
        containerURL: URL,
        verb: String,
        runtimeID: RuntimeID,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws {
        guard containerExists(at: containerURL) else { throw Container.DoesNotExistError() }
        guard Engine.isRuntimeInstalled(runtimeID) else {
            throw Engine.RuntimeNotInstalledError(runtimeID: runtimeID)
        }

        let bundledWinetricksURL = Engine.directory.appending(path: "winetricks")
        let winetricksURL: URL
        if FileManager.default.fileExists(atPath: bundledWinetricksURL.path) {
            winetricksURL = bundledWinetricksURL
        } else {
            let possiblePaths = [
                "/usr/local/bin/winetricks",
                "/opt/homebrew/bin/winetricks",
                "/usr/bin/winetricks"
            ]
            guard let foundPath = possiblePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                throw WinetricksNotFoundError()
            }
            winetricksURL = URL(filePath: foundPath)
        }

        let runtime = Engine.wineRuntime(for: runtimeID)
        let wineBinDirectory = runtime.wineExecutable.deletingLastPathComponent()
        let wineLibDirectory = wineBinDirectory.deletingLastPathComponent().appending(path: "lib")
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.path
            ?? "\(homeDirectory)/Library/Caches"

        let process = Process()
        process.executableURL = winetricksURL
        process.arguments = ["--force", verb]
        process.currentDirectoryURL = containerURL
        process.environment = [
            "HOME": homeDirectory,
            "USER": NSUserName(),
            "XDG_CACHE_HOME": cacheDirectory,
            "WINEPREFIX": containerURL.path,
            "WINE": runtime.wineExecutable.path,
            "WINE64": runtime.wineExecutable.path,
            "WINESERVER": runtime.wineserverExecutable.path,
            "WINEARCH": "win64",
            "PATH": "\(wineBinDirectory.path):/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin",
            "DYLD_FALLBACK_LIBRARY_PATH": "\(wineLibDirectory.path):/usr/lib",
            "WINETRICKS_WINE_IS_64BIT": "true",
            "DISPLAY": "",
            "TERM": "xterm-256color"
        ]

        if let onOutput {
            try await process.runStreamed(throwsOnChunkError: false) { chunk in
                onOutput(chunk.output)
                return nil
            }
        } else {
            _ = try await process.runWrapped()
        }

        guard process.terminationStatus == 0 else {
            throw WinetricksExecutionError(verb: verb, exitCode: process.terminationStatus)
        }
    }
}

// MARK: - Wine 11 runtime installer

/// Installs the pinned macOS Wine 11 runtime used by Engine 3.
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
            in: .userDomainMask,
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
