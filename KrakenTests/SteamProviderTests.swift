//
//  SteamProviderTests.swift
//  KrakenTests
//
// Copyright © 2026 Kraken contributors
//

import XCTest
@testable import Kraken

final class SteamProviderTests: XCTestCase {

    // MARK: - 1. ACF Manifest Parsing

    func testSteamAppManifestParsing() {
        let acfContent = """
        "AppState"
        {
        \t"appid"\t\t"480"
        \t"Universe"\t\t"1"
        \t"name"\t\t"Spacewar"
        \t"StateFlags"\t\t"4"
        \t"installdir"\t\t"Spacewar"
        \t"LastUpdated"\t\t"1700000000"
        \t"SizeOnDisk"\t\t"12345678"
        \t"buildid"\t\t"987654"
        }
        """

        let manifest = SteamAppManifest.parse(text: acfContent)
        XCTAssertNotNil(manifest)
        XCTAssertEqual(manifest?.appId, "480")
        XCTAssertEqual(manifest?.name, "Spacewar")
        XCTAssertEqual(manifest?.installDir, "Spacewar")
        XCTAssertEqual(manifest?.stateFlags, 4)
        XCTAssertEqual(manifest?.sizeOnDisk, 12345678)
    }

    func testSteamAppManifestMalformed() {
        let malformed = "This is not an ACF manifest."
        let manifest = SteamAppManifest.parse(text: malformed)
        XCTAssertNil(manifest)
    }

    // MARK: - 2. Steam Game Model & Artwork

    func testSteamGameArtworkURLs() {
        let game = SteamGame(
            appId: "252490",
            title: "Rust",
            installationState: .uninstalled
        )

        XCTAssertEqual(game.storefront, .steam)
        XCTAssertEqual(
            game.computedVerticalImageURL?.absoluteString,
            "https://steamcdn-a.akamaihd.net/steam/apps/252490/library_600x900_2x.jpg"
        )
        XCTAssertEqual(
            game.computedHorizontalImageURL?.absoluteString,
            "https://steamcdn-a.akamaihd.net/steam/apps/252490/header.jpg"
        )
    }

    // MARK: - 3. Codable & Polymorphic Deserialization

    func testSteamGameCodableRoundTrip() throws {
        let location = URL(fileURLWithPath: "/games/Steam/common/Portal 2/portal2.exe")
        let game = SteamGame(
            appId: "620",
            title: "Portal 2",
            installationState: .installed(location: location, platform: .windows),
            containerURL: URL(fileURLWithPath: "/containers/W11")
        )

        let wrapped = AnyGame(game)
        let data = try JSONEncoder().encode(wrapped)
        let decoded = try JSONDecoder().decode(AnyGame.self, from: data)

        guard let steamGame = decoded.base as? SteamGame else {
            XCTFail("Decoded game is not a SteamGame")
            return
        }

        XCTAssertEqual(steamGame.appId, "620")
        XCTAssertEqual(steamGame.title, "Portal 2")
        XCTAssertEqual(steamGame.storefront, .steam)
        XCTAssertEqual(steamGame.installDir, "Portal 2")
        if case .installed(let loc, let plat) = steamGame.installationState {
            XCTAssertEqual(loc, location)
            XCTAssertEqual(plat, .windows)
        } else {
            XCTFail("Expected installed state")
        }
    }

    // MARK: - 4. LaunchPlan Integration

    func testSteamGameLaunchPlanIntegration() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("drive_c"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

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
            url: tempDir,
            id: UUID(),
            settings: settings,
            runtimeID: .mythicEngine
        )
        let propertiesURL = tempDir.appendingPathComponent("Properties.plist")
        let data = try PropertyListEncoder().encode(container)
        try data.write(to: propertiesURL)

        let gameExe = tempDir.appendingPathComponent("game.exe")
        try "dummy".write(to: gameExe, atomically: true, encoding: .utf8)

        let profile = LaunchProfile(
            container: ContainerReference(url: tempDir),
            defaultRuntimeID: .mythicEngine,
            launchArguments: ["-novid"],
            graphicsBackend: .dxvk
        )

        let plan = try RuntimeResolver.plan(
            for: profile,
            gameId: "480",
            gameTitle: "Spacewar",
            executableURL: gameExe,
            sourceProvider: .steam
        )

        XCTAssertEqual(plan.sourceProvider, .steam)
        XCTAssertEqual(plan.gameId, "480")
        XCTAssertEqual(plan.gameTitle, "Spacewar")
        XCTAssertEqual(plan.launchArguments, ["-novid"])
        XCTAssertEqual(plan.graphicsBackend, .dxvk)
    }

    // MARK: - 5. Executable Discovery Heuristic

    func testSteamDiscoveryFindExecutable() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Test direct exe named after installDir
        let targetExe = tempDir.appendingPathComponent("MyGame.exe")
        try "dummy".write(to: targetExe, atomically: true, encoding: .utf8)

        let found = SteamDiscovery.findExecutable(in: tempDir, installDir: "MyGame")
        XCTAssertEqual(found?.path, targetExe.path)
    }
}
