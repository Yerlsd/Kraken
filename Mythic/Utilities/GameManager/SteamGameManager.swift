//
//  SteamGameManager.swift
//  Kraken
//
// Copyright © 2026 Kraken contributors
//

import Foundation
import AppKit
import OSLog

// MARK: - Steam App Manifest

/// Represents a parsed Valve Steam application manifest (`appmanifest_<appid>.acf`).
struct SteamAppManifest: Codable, Equatable, Sendable {
    let appId: String
    let name: String
    let installDir: String
    let stateFlags: Int
    let sizeOnDisk: Int64

    /// Parses an ACF (KeyValues) text format into a `SteamAppManifest`.
    static func parse(text: String) -> SteamAppManifest? {
        func extractValue(for key: String) -> String? {
            let pattern = "\"\(key)\"\\s+\"([^\"]*)\""
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }
            let nsText = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            guard let match = matches.first, match.numberOfRanges > 1 else { return nil }
            return nsText.substring(with: match.range(at: 1))
        }

        guard let appId = extractValue(for: "appid"), !appId.isEmpty,
              let name = extractValue(for: "name"), !name.isEmpty,
              let installDir = extractValue(for: "installdir"), !installDir.isEmpty else {
            return nil
        }

        let stateFlags = Int(extractValue(for: "StateFlags") ?? "4") ?? 4
        let sizeOnDisk = Int64(extractValue(for: "SizeOnDisk") ?? "0") ?? 0

        return SteamAppManifest(
            appId: appId,
            name: name,
            installDir: installDir,
            stateFlags: stateFlags,
            sizeOnDisk: sizeOnDisk
        )
    }

    /// Parses a manifest file at the given URL.
    static func parse(fileAt url: URL) -> SteamAppManifest? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return parse(text: text)
    }
}

// MARK: - Steam Discovery

/// Scans local filesystems and Wine containers to discover installed Steam games.
enum SteamDiscovery {
    private static let logger = Logger(subsystem: "com.yerlsd.kraken", category: "SteamDiscovery")

    /// Default candidates for Steam installations on macOS and within configured Wine containers.
    static func discoveryRoots() -> [URL] {
        var roots: [URL] = []
        let fm = FileManager.default

        // 1. Native macOS Steam
        let macSteam = fm.homeDirectoryForCurrentUser.appending(
            path: "Library/Application Support/Steam"
        )
        if fm.fileExists(atPath: macSteam.path) {
            roots.append(macSteam)
        }

        // 2. Wine containers registered in Kraken
        for container in Wine.containerObjects {
            let containerURL = container.url
            let x86Steam = containerURL.appending(path: "drive_c/Program Files (x86)/Steam")
            let x64Steam = containerURL.appending(path: "drive_c/Program Files/Steam")

            if fm.fileExists(atPath: x86Steam.path) {
                roots.append(x86Steam)
            }
            if fm.fileExists(atPath: x64Steam.path) {
                roots.append(x64Steam)
            }
        }

        return roots
    }

    /// Discovers all installed Steam games from known Steam roots and containers.
    static func discoverInstalledGames() -> [SteamGame] {
        var games: [SteamGame] = []
        let fm = FileManager.default

        for root in discoveryRoots() {
            let steamapps = root.appending(path: "steamapps")
            guard fm.fileExists(atPath: steamapps.path) else { continue }

            guard let contents = try? fm.contentsOfDirectory(atPath: steamapps.path) else { continue }

            for item in contents where item.hasPrefix("appmanifest_") && item.hasSuffix(".acf") {
                let manifestURL = steamapps.appending(path: item)
                guard let manifest = SteamAppManifest.parse(fileAt: manifestURL) else { continue }

                // Locate the game directory
                let commonDir = steamapps.appending(path: "common/\(manifest.installDir)")
                guard fm.fileExists(atPath: commonDir.path) else { continue }

                // Find executable in game directory
                guard let executableURL = findExecutable(in: commonDir, installDir: manifest.installDir) else {
                    continue
                }

                // Associate with the container if this root was inside a container
                let containerURL = Wine.containerObjects.first(where: {
                    root.path.hasPrefix($0.url.path)
                })?.url

                let isWindows = executableURL.pathExtension.lowercased() == "exe"
                let platform: Game.Platform = isWindows ? .windows : .macOS

                let game = SteamGame(
                    appId: manifest.appId,
                    title: manifest.name,
                    installationState: .installed(location: executableURL, platform: platform),
                    containerURL: containerURL
                )

                games.append(game)
                logger.info("Discovered Steam game '\(manifest.name)' (\(manifest.appId)) at \(executableURL.path)")
            }
        }

        return games
    }

    /// Finds the primary executable inside a Steam game directory.
    static func findExecutable(in directoryURL: URL, installDir: String) -> URL? {
        let fm = FileManager.default

        // 1. Direct match: <installDir>.exe
        let directExe = directoryURL.appending(path: "\(installDir).exe")
        if fm.fileExists(atPath: directExe.path) {
            return directExe
        }

        // 2. Direct macOS app match: <installDir>.app
        let directApp = directoryURL.appending(path: "\(installDir).app")
        if fm.fileExists(atPath: directApp.path) {
            return directApp
        }

        // 3. Top-level executables
        guard let contents = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isExecutableKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let exes = contents.filter { $0.pathExtension.lowercased() == "exe" }
        if let firstExe = exes.first {
            return firstExe
        }

        let apps = contents.filter { $0.pathExtension.lowercased() == "app" }
        if let firstApp = apps.first {
            return firstApp
        }

        return nil
    }
}

// MARK: - Steam Game Manager

/// Manages lifecycle, launching, and operations for Steam games.
///
/// Follows the single launch architecture:
/// Game → LaunchProfile → LaunchPlan → LaunchSession
class SteamGameManager: GameManager {
    static var log: Logger { .custom(category: "SteamGameManager") }

    @MainActor static func launch(game: Game) async throws -> GameOperation {
        guard case .steam = game.storefront,
              let castGame = game as? SteamGame else {
            throw CocoaError(.coderInvalidValue)
        }
        return try await launch(game: castGame)
    }

    @MainActor static func move(game: Game, to newLocation: URL) async throws -> GameOperation {
        guard case .steam = game.storefront,
              let castGame = game as? SteamGame else {
            throw CocoaError(.coderInvalidValue)
        }
        return try await move(game: castGame, to: newLocation)
    }

    @MainActor static func uninstall(game: Game, persistFiles: Bool) async throws -> GameOperation {
        guard case .steam = game.storefront,
              let castGame = game as? SteamGame else {
            throw CocoaError(.coderInvalidValue)
        }
        return try await uninstall(game: castGame, persistFiles: persistFiles)
    }

    // MARK: - Concrete Implementation

    @discardableResult
    @MainActor static func launch(game: SteamGame) async throws -> GameOperation {
        guard case .installed(let location, let platform) = game.installationState else {
            throw CocoaError(.fileNoSuchFile)
        }

        let launchProfile: LaunchProfile = game.launchProfile

        let operation: GameOperation = .init(game: game, type: .launch) { _ in
            switch platform {
            case .macOS:
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.arguments = launchProfile.launchArguments

                let application = try await NSWorkspace.shared.openApplication(
                    at: location,
                    configuration: configuration
                )

                try await withTaskCancellationHandler {
                    await withCheckedContinuation { continuation in
                        var observer: NSObjectProtocol?
                        observer = NSWorkspace.shared.notificationCenter.addObserver(
                            forName: NSWorkspace.didTerminateApplicationNotification,
                            object: nil,
                            queue: .main
                        ) { notification in
                            guard let observed = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                                  observed == application else { return }
                            if let observer {
                                NSWorkspace.shared.notificationCenter.removeObserver(observer)
                            }
                            continuation.resume()
                        }
                        if application.isTerminated {
                            if let observer {
                                NSWorkspace.shared.notificationCenter.removeObserver(observer)
                            }
                            continuation.resume()
                        }
                    }
                    try Task.checkCancellation()
                } onCancel: {
                    application.terminate()
                }

            case .windows:
                // Single runtime authority, sourceProvider: .steam
                let plan = try RuntimeResolver.plan(
                    for: launchProfile,
                    gameId: game.id,
                    gameTitle: game.title,
                    executableURL: location,
                    sourceProvider: .steam
                )
                let session = LaunchSession(plan: plan)
                session.transitionToResolving()
                session.transitionToProvisioning()

                let target: RuntimeResolver.ResolvedLaunchTarget
                do {
                    target = try RuntimeResolver.resolve(profile: launchProfile, executableURL: location)
                } catch {
                    session.recordFailure(stage: .resolutionFailure, message: error.localizedDescription)
                    throw error
                }

                session.transitionToStartingRuntime()
                session.transitionToStartingProcess()

                // Preflight storage readiness
                let storageResult = GameStoragePreflight.inspect(at: location)
                if storageResult.datalessFileCount > 0 {
                    Self.log.warning("Steam assets contain \(storageResult.datalessFileCount, privacy: .public) dataless files offloaded to iCloud. Triggering background materialization.")
                    GameStoragePreflight.materializeDatalessFiles(in: location)
                }

                let process = Process()
                process.currentDirectoryURL = location.deletingLastPathComponent()
                process.arguments = [location.path] + target.launchArguments
                RuntimeResolver.configure(process, for: target)

                // Inject Steam environment variables
                var env = process.environment ?? [:]
                env["SteamAppId"] = game.appId
                env["SteamGameId"] = game.appId
                env["STEAM_COMPAT_CLIENT_INSTALL_PATH"] = location.deletingLastPathComponent().path
                process.environment = env

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    for line in text.split(whereSeparator: \.isNewline) {
                        Self.log.info("[Steam Wine stdout] \(line, privacy: .public)")
                    }
                }

                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    for line in text.split(whereSeparator: \.isNewline) {
                        Self.log.notice("[Steam Wine stderr] \(line, privacy: .public)")
                    }
                }

                final class ProcessBox: @unchecked Sendable {
                    let value: Process
                    init(_ value: Process) { self.value = value }
                }
                let processBox = ProcessBox(process)

                do {
                    try process.run()
                } catch {
                    session.recordFailure(stage: .processCreationFailure, message: error.localizedDescription)
                    throw error
                }

                session.recordProcessCreated(pid: process.processIdentifier, processName: "wine64")
                ProcessMonitor.shared.register(session: session)

                await MainActor.run {
                    game.launchProfile.recordSuccessfulLaunch(backend: target.graphicsBackend)
                }

                try await withTaskCancellationHandler {
                    await withCheckedContinuation { continuation in
                        final class ContinuationState: @unchecked Sendable {
                            private var resumed = false
                            private let lock = NSLock()
                            func resumeOnce(_ continuation: CheckedContinuation<Void, Never>) {
                                lock.lock()
                                defer { lock.unlock() }
                                guard !resumed else { return }
                                resumed = true
                                continuation.resume()
                            }
                        }
                        let state = ContinuationState()

                        processBox.value.terminationHandler = { terminatedProcess in
                            let exitCode = terminatedProcess.terminationStatus
                            let reason: ProcessTerminationReason = (terminatedProcess.terminationReason == .exit) ? .normalExit : .uncaughtSignal
                            session.recordTermination(exitCode: exitCode, reason: reason)
                            ProcessMonitor.shared.unregister(sessionId: session.id)

                            outputPipe.fileHandleForReading.readabilityHandler = nil
                            errorPipe.fileHandleForReading.readabilityHandler = nil
                            state.resumeOnce(continuation)
                        }

                        if !processBox.value.isRunning {
                            outputPipe.fileHandleForReading.readabilityHandler = nil
                            errorPipe.fileHandleForReading.readabilityHandler = nil
                            state.resumeOnce(continuation)
                        }
                    }
                    try Task.checkCancellation()
                } onCancel: {
                    if processBox.value.isRunning {
                        session.transitionToTerminating()
                        processBox.value.terminate()
                    }
                }
            }
        }

        Game.operationManager.queueOperation(operation)
        return operation
    }

    @discardableResult
    @MainActor static func move(game: SteamGame, to newLocation: URL) async throws -> GameOperation {
        guard case .installed(let currentLocation, let platform) = game.installationState else {
            throw CocoaError(.fileNoSuchFile)
        }

        let operation: GameOperation = .init(game: game, type: .move) { _ in
            try FileManager.default.moveItem(at: currentLocation, to: newLocation)
            await MainActor.run {
                game.installationState = .installed(location: newLocation, platform: platform)
            }
        }

        Game.operationManager.queueOperation(operation)
        return operation
    }

    @discardableResult
    @MainActor static func uninstall(game: SteamGame, persistFiles: Bool) async throws -> GameOperation {
        guard case .installed(let location, _) = game.installationState else {
            throw CocoaError(.fileNoSuchFile)
        }

        let operation: GameOperation = .init(game: game, type: .uninstall) { _ in
            if !persistFiles {
                try FileManager.default.removeItem(at: location)
            }
            game.installationState = .uninstalled
            if GameDataStore.shared.library.contains(game) {
                GameDataStore.shared.library.remove(game)
            }
        }

        Game.operationManager.queueOperation(operation)
        return operation
    }

    /// Imports a Steam game from an executable and manifest information.
    @discardableResult
    @MainActor static func importGame(
        appId: String,
        title: String,
        executableURL: URL,
        platform: Game.Platform,
        containerURL: URL? = nil
    ) -> SteamGame {
        let game = SteamGame(
            appId: appId,
            title: title,
            installationState: .installed(location: executableURL, platform: platform),
            containerURL: containerURL
        )
        GameDataStore.shared.library.insert(game)
        return game
    }
}
