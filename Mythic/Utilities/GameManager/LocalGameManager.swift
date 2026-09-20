//
//  LocalGameManager.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 16/11/2025.
//

// Copyright © 2023-2025 vapidinfinity

import Foundation
import AppKit
import OSLog

extension LocalGameManager: GameManager {
    @MainActor static func launch(game: Game) async throws -> GameOperation {
        guard case .local = game.storefront,
              let castGame = game as? LocalGame else { throw CocoaError(.coderInvalidValue) }

        return try await launch(game: castGame)
    }

    @MainActor static func move(game: Game,
                                to newLocation: URL) async throws -> GameOperation {
        guard case .local = game.storefront,
              let castGame = game as? LocalGame else { throw CocoaError(.coderInvalidValue) }

        return try await move(game: castGame, to: newLocation)
    }

    @MainActor static func uninstall(game: Game,
                                     persistFiles: Bool) async throws -> GameOperation {
        guard case .local = game.storefront,
              let castGame = game as? LocalGame else { throw CocoaError(.coderInvalidValue) }

        return try await uninstall(game: castGame, persistFiles: persistFiles)
    }
}

class LocalGameManager {
    static var log: Logger { .custom(category: "LocalGameManager") }

    @discardableResult
    @MainActor static func launch(game: LocalGame) async throws -> GameOperation {
        guard case .installed(let location, let platform) = game.installationState else {
            throw CocoaError(.fileNoSuchFile)
        }

        defer {
            if UserDefaults.standard.bool(forKey: "minimiseOnGameLaunch") {
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
        }

        let launchProfile: LaunchProfile = game.launchProfile

        let operation: GameOperation = .init(game: game, type: .launch) { _ in
            switch platform {
            case .macOS:
                let configuration: NSWorkspace.OpenConfiguration = .init()
                configuration.arguments = launchProfile.launchArguments

                guard (try? location.resourceValues(forKeys: [.contentTypeKey]).contentType)?
                    .conforms(to: .bundle) == true else {
                    throw CocoaError(.serviceApplicationLaunchFailed)
                }

                let application = try await NSWorkspace.shared.openApplication(
                    at: location,
                    configuration: configuration
                )

                if UserDefaults.standard.bool(forKey: "minimiseOnGameLaunch") {
                    await MainActor.run {
                        NSApp.windows.first?.miniaturize(nil)
                    }
                }

                try await withTaskCancellationHandler {
                    await withCheckedContinuation { continuation in
                        var observer: NSObjectProtocol?
                        observer = NSWorkspace.shared.notificationCenter.addObserver(
                            forName: NSWorkspace.didTerminateApplicationNotification,
                            object: nil,
                            queue: .main
                        ) { notification in
                            guard
                                let observedApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                                observedApplication == application
                            else {
                                return
                            }

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
                // Single runtime authority, shared with the Epic launch path.
                let plan = try RuntimeResolver.plan(
                    for: launchProfile,
                    gameId: game.id,
                    gameTitle: game.title,
                    executableURL: location,
                    sourceProvider: .local
                )
                let session = LaunchSession(plan: plan)
                session.transitionToResolving()
                session.transitionToProvisioning()

                let target = try RuntimeResolver.resolve(profile: launchProfile)

                if UserDefaults.standard.bool(forKey: "minimiseOnGameLaunch") {
                    await MainActor.run {
                        NSApp.windows.first?.miniaturize(nil)
                    }
                }

                session.transitionToStartingRuntime()
                session.transitionToStartingProcess()

                // Preflight storage readiness to prevent Wine blocking on iCloud / APFS dataless stubs
                let storageResult = GameStoragePreflight.inspect(at: location)
                if storageResult.datalessFileCount > 0 {
                    Self.log.warning("Game assets contain \(storageResult.datalessFileCount, privacy: .public) dataless files offloaded to iCloud. Triggering background materialization.")
                    GameStoragePreflight.materializeDatalessFiles(in: location)
                }

                let process = Process()
                process.currentDirectoryURL = location.deletingLastPathComponent()
                process.arguments = [location.path] + target.launchArguments
                RuntimeResolver.configure(process, for: target)

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    for line in text.split(whereSeparator: \.isNewline) {
                        Self.log.info("[Wine stdout] \(line, privacy: .public)")
                    }
                }

                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    for line in text.split(whereSeparator: \.isNewline) {
                        Self.log.notice("[Wine stderr] \(line, privacy: .public)")
                    }
                }

                /*
                 Process is an Objective-C reference type and Swift 6 requires
                 values captured by the cancellation handler to satisfy
                 Sendable. This wrapper deliberately confines the unchecked
                 boundary to the Foundation Process object itself.
                 */
                final class ProcessBox: @unchecked Sendable {
                    let value: Process

                    init(_ value: Process) {
                        self.value = value
                    }
                }

                let processBox = ProcessBox(process)

                try process.run()
                session.recordProcessCreated(pid: process.processIdentifier)
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
    @MainActor static func move(game: LocalGame,
                                to newLocation: URL) async throws -> GameOperation {
        guard case .installed(let currentLocation, let platform) = game.installationState else {
            throw CocoaError(.fileNoSuchFile)
        }

        let operation: GameOperation = .init(game: game, type: .move) {  _ in
            try FileManager.default.moveItem(at: currentLocation, to: newLocation)
            await MainActor.run {
                game.installationState = .installed(location: newLocation, platform: platform)
            }
        }

        Game.operationManager.queueOperation(operation)
        return operation
    }

    @discardableResult
    @MainActor static func uninstall(game: LocalGame,
                                     persistFiles: Bool) async throws -> GameOperation {
        guard case .installed(let location, _) = game.installationState else {
            throw CocoaError(.fileNoSuchFile)
        }

        let operation: GameOperation = .init(game: game, type: .uninstall) {  _ in
            if !persistFiles {
                try FileManager.default.removeItem(at: location)
            }
            
            game.installationState = .uninstalled
            
            // remove the game from the library if present.
            // this is only necessary for non-storefront games.
            if GameDataStore.shared.library.contains(game) {
                GameDataStore.shared.library.remove(game)
            }
        }

        Game.operationManager.queueOperation(operation)
        return operation
    }
}
