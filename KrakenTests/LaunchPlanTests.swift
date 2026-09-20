//
//  LaunchPlanTests.swift
//  KrakenTests
//
// Copyright © 2026 Kraken contributors
//

import XCTest
@testable import Kraken

final class LaunchPlanTests: XCTestCase {

    var tempDirectory: URL!
    var mockContainerURL: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        mockContainerURL = tempDirectory.appending(path: "mock_container")
        try? FileManager.default.createDirectory(at: mockContainerURL.appending(path: "drive_c"), withIntermediateDirectories: true)

        // Write a minimal mock Properties.plist so Wine.getContainerObject succeeds
        let settings = Wine.Container.Settings(
            metalHUD: false,
            msync: true,
            retinaMode: false,
            dxvk: true,
            dxvkAsync: false,
            scaling: 96
        )
        let container = Wine.Container(
            name: "Mock Container",
            url: mockContainerURL,
            id: UUID(),
            settings: settings,
            runtimeID: .mythicEngine
        )
        let propertiesURL = mockContainerURL.appending(path: "Properties.plist")
        if let data = try? PropertyListEncoder().encode(container) {
            try? data.write(to: propertiesURL)
        }
    }

    override func tearDown() {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }

    func testDeterministicPlans() throws {
        let profile = LaunchProfile(
            container: ContainerReference(url: mockContainerURL),
            defaultRuntimeID: .mythicEngine,
            runtimeOverride: nil,
            launchArguments: ["-windowed", "-dx11"],
            graphicsBackend: .dxvk,
            reportedGPUMemoryPolicy: .manual(megabytes: 2048)
        )

        let mockRegistry = RuntimeRegistry(providers: [
            MockRuntimeProvider(id: .mythicEngine, installed: true, rootDirectory: tempDirectory.appending(path: "mythic"))
        ])

        let plan1 = try RuntimeResolver.plan(
            for: profile,
            gameId: "test-game",
            gameTitle: "Test Game",
            executableURL: URL(fileURLWithPath: "/games/test.exe"),
            sourceProvider: .local,
            runtimeRegistry: mockRegistry
        )

        let plan2 = try RuntimeResolver.plan(
            for: profile,
            gameId: "test-game",
            gameTitle: "Test Game",
            executableURL: URL(fileURLWithPath: "/games/test.exe"),
            sourceProvider: .local,
            runtimeRegistry: mockRegistry
        )

        XCTAssertEqual(plan1.gameId, plan2.gameId)
        XCTAssertEqual(plan1.gameTitle, plan2.gameTitle)
        XCTAssertEqual(plan1.sourceProvider, plan2.sourceProvider)
        XCTAssertEqual(plan1.executableURL, plan2.executableURL)
        XCTAssertEqual(plan1.launchArguments, plan2.launchArguments)
        XCTAssertEqual(plan1.runtimeID, plan2.runtimeID)
        XCTAssertEqual(plan1.runtimeFamily, plan2.runtimeFamily)
        XCTAssertEqual(plan1.graphicsBackend, plan2.graphicsBackend)
        XCTAssertEqual(plan1.reportedGPUMemoryMB, plan2.reportedGPUMemoryMB)
        XCTAssertEqual(plan1.environment, plan2.environment)
        XCTAssertEqual(plan1.displayConfiguration, plan2.displayConfiguration)
    }

    func testExplicitRuntimeSelectionPreserved() throws {
        // Create Wine 11 container
        let wine11ContainerURL = tempDirectory.appending(path: "wine11_container")
        try FileManager.default.createDirectory(at: wine11ContainerURL.appending(path: "drive_c"), withIntermediateDirectories: true)
        let container = Wine.Container(
            name: "Wine 11 Container",
            url: wine11ContainerURL,
            id: UUID(),
            settings: Wine.Container.Settings(metalHUD: false, msync: true, retinaMode: false, scaling: 96),
            runtimeID: .wine11
        )
        let data = try PropertyListEncoder().encode(container)
        try data.write(to: wine11ContainerURL.appending(path: "Properties.plist"))

        let profile = LaunchProfile(
            container: ContainerReference(url: wine11ContainerURL),
            defaultRuntimeID: .mythicEngine,
            runtimeOverride: .wine11,
            launchArguments: [],
            graphicsBackend: .dxvk
        )

        let mockRegistry = RuntimeRegistry(providers: [
            MockRuntimeProvider(id: .mythicEngine, installed: true),
            MockRuntimeProvider(id: .wine11, installed: true, rootDirectory: tempDirectory.appending(path: "wine11"))
        ])

        let plan = try RuntimeResolver.plan(
            for: profile,
            gameId: "wine11-game",
            gameTitle: "Wine 11 Game",
            runtimeRegistry: mockRegistry
        )

        XCTAssertEqual(plan.runtimeID, .wine11)
        XCTAssertEqual(plan.launchArguments, profile.launchArguments)
    }

    func testExplicitGraphicsSelectionPreserved() throws {
        let profile = LaunchProfile(
            container: ContainerReference(url: mockContainerURL),
            defaultRuntimeID: .mythicEngine,
            runtimeOverride: nil,
            launchArguments: [],
            graphicsBackend: .dxvk
        )

        let mockRegistry = RuntimeRegistry(providers: [
            MockRuntimeProvider(id: .mythicEngine, installed: true)
        ])

        let plan = try RuntimeResolver.plan(
            for: profile,
            runtimeRegistry: mockRegistry
        )

        XCTAssertEqual(plan.graphicsBackend, .dxvk)
        XCTAssertNotNil(plan.graphicsArtifactManifest)
        XCTAssertEqual(plan.graphicsArtifactManifest?.backend, .dxvk)
        XCTAssertEqual(plan.graphicsArtifactManifest?.runtimeFamily, .mythicEngine)
    }

    func testContainerRuntimeAffinityPreserved() {
        // mythicEngine container with wine11 profile
        let profile = LaunchProfile(
            container: ContainerReference(url: mockContainerURL), // mockContainerURL is mythicEngine
            defaultRuntimeID: .wine11,
            runtimeOverride: .wine11
        )

        let mockRegistry = RuntimeRegistry(providers: [
            MockRuntimeProvider(id: .wine11, installed: true)
        ])

        XCTAssertThrowsError(try RuntimeResolver.plan(for: profile, runtimeRegistry: mockRegistry)) { error in
            guard case RuntimeResolver.ResolutionError.containerRuntimeMismatch(let selected, let containerRuntime, _) = error else {
                XCTFail("Expected containerRuntimeMismatch, got \(error)")
                return
            }
            XCTAssertEqual(selected, .wine11)
            XCTAssertEqual(containerRuntime, .mythicEngine)
        }
    }

    func testReportedGPUMemoryCarriedThrough() throws {
        let profile = LaunchProfile(
            container: ContainerReference(url: mockContainerURL),
            defaultRuntimeID: .mythicEngine,
            reportedGPUMemoryPolicy: .manual(megabytes: 4095)
        )

        let mockRegistry = RuntimeRegistry(providers: [
            MockRuntimeProvider(id: .mythicEngine, installed: true)
        ])

        let plan = try RuntimeResolver.plan(for: profile, runtimeRegistry: mockRegistry)
        XCTAssertEqual(plan.reportedGPUMemoryMB, 4095)
    }

    func testLaunchArgumentsAndEnvironmentPreserved() throws {
        let profile = LaunchProfile(
            container: ContainerReference(url: mockContainerURL),
            defaultRuntimeID: .mythicEngine,
            runtimeOverride: nil,
            launchArguments: ["-novid", "-high", "-fullscreen"],
            graphicsBackend: .dxvk
        )

        let mockRegistry = RuntimeRegistry(providers: [
            MockRuntimeProvider(id: .mythicEngine, installed: true)
        ])

        let plan = try RuntimeResolver.plan(for: profile, runtimeRegistry: mockRegistry)
        XCTAssertEqual(plan.launchArguments, ["-novid", "-high", "-fullscreen"])
        XCTAssertEqual(plan.environment["WINEPREFIX"], mockContainerURL.path(percentEncoded: false))
        XCTAssertEqual(plan.environment["WINEDLLOVERRIDES"], "d3d10core,d3d11,dxgi=n,b")
        XCTAssertEqual(plan.environment["DXVK_CONFIG_FILE"], "C:\\windows\\dxvk.conf")
    }

    func testResolverRemainsSideEffectFree() throws {
        let profile = LaunchProfile(
            container: ContainerReference(url: mockContainerURL),
            defaultRuntimeID: .mythicEngine,
            runtimeOverride: nil,
            launchArguments: [],
            graphicsBackend: .dxvk
        )

        let mockRegistry = RuntimeRegistry(providers: [
            MockRuntimeProvider(id: .mythicEngine, installed: true)
        ])

        let filesBefore = try FileManager.default.contentsOfDirectory(atPath: mockContainerURL.path)

        _ = try RuntimeResolver.plan(for: profile, runtimeRegistry: mockRegistry)

        let filesAfter = try FileManager.default.contentsOfDirectory(atPath: mockContainerURL.path)
        XCTAssertEqual(filesBefore, filesAfter)
    }

    func testLaunchPlanConfiguresProcessCorrectly() {
        let plan = LaunchPlan(
            gameId: "subnautica",
            gameTitle: "Subnautica",
            sourceProvider: .local,
            executableURL: URL(fileURLWithPath: "/games/subnautica/Subnautica.exe"),
            launchArguments: ["-screen-fullscreen", "1"],
            runtimeID: .wine11,
            runtimeFamily: .wine11,
            runtimeVersion: "Engine 3",
            wineExecutableURL: URL(fileURLWithPath: "/runtimes/wine11/bin/wine"),
            wineserverExecutableURL: URL(fileURLWithPath: "/runtimes/wine11/bin/wineserver"),
            containerURL: URL(fileURLWithPath: "/containers/subnautica"),
            graphicsBackend: .dxvk,
            graphicsArtifactManifest: GraphicsArtifactRegistry.wine11DXVKPatched,
            reportedGPUMemoryMB: 8192,
            environment: ["WINEPREFIX": "/containers/subnautica", "DXVK_ASYNC": "1"],
            displayConfiguration: LaunchDisplayConfiguration(retinaMode: false, scalingDPI: 96)
        )

        let process = Process()
        plan.configure(process: process)

        XCTAssertEqual(process.executableURL?.path, "/runtimes/wine11/bin/wine")
        XCTAssertEqual(process.arguments, ["/games/subnautica/Subnautica.exe", "-screen-fullscreen", "1"])
        XCTAssertEqual(process.environment?["WINEPREFIX"], "/containers/subnautica")
        XCTAssertEqual(process.environment?["DXVK_ASYNC"], "1")
    }

    func testLaunchPlanCodableRoundTrip() throws {
        let original = LaunchPlan(
            gameId: "test-id",
            gameTitle: "Test Title",
            sourceProvider: .epic,
            executableURL: URL(fileURLWithPath: "/games/game.exe"),
            launchArguments: ["--arg1", "--arg2"],
            runtimeID: .mythicEngine,
            runtimeFamily: .mythicEngine,
            runtimeVersion: "Engine 2",
            wineExecutableURL: URL(fileURLWithPath: "/wine/bin/wine"),
            wineserverExecutableURL: URL(fileURLWithPath: "/wine/bin/wineserver"),
            containerURL: URL(fileURLWithPath: "/containers/test"),
            graphicsBackend: .dxvk,
            graphicsArtifactManifest: GraphicsArtifactRegistry.mythicEngineDXVK,
            reportedGPUMemoryMB: 4095,
            environment: ["TEST_ENV": "1"],
            displayConfiguration: LaunchDisplayConfiguration(retinaMode: false, scalingDPI: 96)
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(LaunchPlan.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.gameId, decoded.gameId)
        XCTAssertEqual(original.gameTitle, decoded.gameTitle)
        XCTAssertEqual(original.sourceProvider, decoded.sourceProvider)
        XCTAssertEqual(original.executableURL, decoded.executableURL)
        XCTAssertEqual(original.launchArguments, decoded.launchArguments)
        XCTAssertEqual(original.runtimeID, decoded.runtimeID)
        XCTAssertEqual(original.runtimeFamily, decoded.runtimeFamily)
        XCTAssertEqual(original.runtimeVersion, decoded.runtimeVersion)
        XCTAssertEqual(original.graphicsBackend, decoded.graphicsBackend)
        XCTAssertEqual(original.reportedGPUMemoryMB, decoded.reportedGPUMemoryMB)
        XCTAssertEqual(original.environment, decoded.environment)
    }
}
