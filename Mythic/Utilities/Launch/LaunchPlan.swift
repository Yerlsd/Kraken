//
//  LaunchPlan.swift
//  Kraken
//
// Copyright © 2026 Kraken contributors
//

import Foundation

/// Identifies the storefront or subsystem providing the game.
enum LaunchSourceProvider: String, Codable, Equatable, Hashable, Sendable {
    case local
    case epic
    case steam
    case mock
    case custom
}

/// Display and rendering configuration resolved for a specific launch session.
struct LaunchDisplayConfiguration: Codable, Equatable, Hashable, Sendable {
    let retinaMode: Bool
    let scalingDPI: Int
    let metalHUD: Bool
    let msync: Bool
    let avx2: Bool

    init(
        retinaMode: Bool = false,
        scalingDPI: Int = 96,
        metalHUD: Bool = false,
        msync: Bool = true,
        avx2: Bool = false
    ) {
        self.retinaMode = retinaMode
        self.scalingDPI = scalingDPI
        self.metalHUD = metalHUD
        self.msync = msync
        self.avx2 = avx2
    }
}

/// Diagnostic and provenance telemetry recorded at plan generation time.
struct LaunchDiagnostics: Codable, Equatable, Hashable, Sendable {
    let timestamp: Date
    let resolverVersion: String
    let machineArchitecture: String
    let osVersion: String

    init(
        timestamp: Date = Date(),
        resolverVersion: String = "2.0-engine3",
        machineArchitecture: String = {
            #if arch(arm64)
            return "arm64"
            #elseif arch(x86_64)
            return "x86_64"
            #else
            return "unknown"
            #endif
        }(),
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString
    ) {
        self.timestamp = timestamp
        self.resolverVersion = resolverVersion
        self.machineArchitecture = machineArchitecture
        self.osVersion = osVersion
    }
}

/// Fully resolved, immutable launch description representing the complete launch decision.
struct LaunchPlan: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: UUID
    let gameId: String
    let gameTitle: String
    let sourceProvider: LaunchSourceProvider
    let executableURL: URL
    let launchArguments: [String]

    let runtimeID: RuntimeID
    let runtimeFamily: RuntimeFamily
    let runtimeVersion: String
    let wineExecutableURL: URL
    let wineserverExecutableURL: URL

    let containerURL: URL
    let graphicsBackend: GraphicsBackend
    let graphicsArtifactManifest: GraphicsArtifactManifest?
    let reportedGPUMemoryMB: Int

    let environment: [String: String]
    let displayConfiguration: LaunchDisplayConfiguration
    let diagnostics: LaunchDiagnostics

    init(
        id: UUID = UUID(),
        gameId: String,
        gameTitle: String,
        sourceProvider: LaunchSourceProvider,
        executableURL: URL,
        launchArguments: [String],
        runtimeID: RuntimeID,
        runtimeFamily: RuntimeFamily,
        runtimeVersion: String,
        wineExecutableURL: URL,
        wineserverExecutableURL: URL,
        containerURL: URL,
        graphicsBackend: GraphicsBackend,
        graphicsArtifactManifest: GraphicsArtifactManifest?,
        reportedGPUMemoryMB: Int,
        environment: [String: String],
        displayConfiguration: LaunchDisplayConfiguration,
        diagnostics: LaunchDiagnostics = LaunchDiagnostics()
    ) {
        self.id = id
        self.gameId = gameId
        self.gameTitle = gameTitle
        self.sourceProvider = sourceProvider
        self.executableURL = executableURL
        self.launchArguments = launchArguments
        self.runtimeID = runtimeID
        self.runtimeFamily = runtimeFamily
        self.runtimeVersion = runtimeVersion
        self.wineExecutableURL = wineExecutableURL
        self.wineserverExecutableURL = wineserverExecutableURL
        self.containerURL = containerURL
        self.graphicsBackend = graphicsBackend
        self.graphicsArtifactManifest = graphicsArtifactManifest
        self.reportedGPUMemoryMB = reportedGPUMemoryMB
        self.environment = environment
        self.displayConfiguration = displayConfiguration
        self.diagnostics = diagnostics
    }

    /// Configures a `Process` instance with the exact parameters specified by this launch plan.
    func configure(process: Process) {
        process.executableURL = wineExecutableURL
        process.arguments = [executableURL.path(percentEncoded: false)] + launchArguments
        let baseEnvironment = process.environment ?? ProcessInfo.processInfo.environment
        process.environment = baseEnvironment.merging(environment, uniquingKeysWith: { _, resolved in resolved })
    }
}
