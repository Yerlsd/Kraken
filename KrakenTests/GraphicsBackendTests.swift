//
//  GraphicsBackendTests.swift
//  KrakenTests
//
// Copyright © 2026 Kraken contributors

import XCTest
@testable import Kraken

final class GraphicsBackendTests: XCTestCase {

    // MARK: - Backend Model Tests

    func testGraphicsBackendCodable() throws {
        let backends: [GraphicsBackend] = [.automatic, .d3dmetal, .dxmt, .dxvk, .wined3d]

        for backend in backends {
            let encoded = try JSONEncoder().encode(backend)
            let decoded = try JSONDecoder().decode(GraphicsBackend.self, from: encoded)
            XCTAssertEqual(backend, decoded, "Backend \(backend.displayName) should round-trip through Codable")
        }
    }

    func testGraphicsBackendCapabilities() {
        // D3DMetal supports D3D10/11/12 but not D3D9
        let d3dmetalCaps = GraphicsBackend.d3dmetal.capabilities
        XCTAssertFalse(d3dmetalCaps.supportsD3D9)
        XCTAssertTrue(d3dmetalCaps.supportsD3D10)
        XCTAssertTrue(d3dmetalCaps.supportsD3D11)
        XCTAssertTrue(d3dmetalCaps.supportsD3D12)

        // DXMT supports D3D10/11 but not D3D9/12
        let dxmtCaps = GraphicsBackend.dxmt.capabilities
        XCTAssertFalse(dxmtCaps.supportsD3D9)
        XCTAssertTrue(dxmtCaps.supportsD3D10)
        XCTAssertTrue(dxmtCaps.supportsD3D11)
        XCTAssertFalse(dxmtCaps.supportsD3D12)

        // DXVK supports D3D9/10/11 but not D3D12
        let dxvkCaps = GraphicsBackend.dxvk.capabilities
        XCTAssertTrue(dxvkCaps.supportsD3D9)
        XCTAssertTrue(dxvkCaps.supportsD3D10)
        XCTAssertTrue(dxvkCaps.supportsD3D11)
        XCTAssertFalse(dxvkCaps.supportsD3D12)

        // WineD3D supports all
        let wined3dCaps = GraphicsBackend.wined3d.capabilities
        XCTAssertTrue(wined3dCaps.supportsD3D9)
        XCTAssertTrue(wined3dCaps.supportsD3D10)
        XCTAssertTrue(wined3dCaps.supportsD3D11)
        XCTAssertTrue(wined3dCaps.supportsD3D12)
    }

    // MARK: - LaunchProfile Persistence Tests

    func testLaunchProfileBackendPersistence() throws {
        var profile = LaunchProfile(graphicsBackend: .d3dmetal)

        let encoded = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(LaunchProfile.self, from: encoded)

        XCTAssertEqual(decoded.graphicsBackend, .d3dmetal)
        XCTAssertNil(decoded.lastSuccessfulBackend)
    }

    func testLaunchProfileBackwardCompatibility() throws {
        // Simulate old profile without graphicsBackend field
        let oldProfileJSON = """
        {
            "runtimeID": "mythic-engine",
            "launchArguments": []
        }
        """.data(using: .utf8)!

        let profile = try JSONDecoder().decode(LaunchProfile.self, from: oldProfileJSON)

        // Should default to automatic
        XCTAssertEqual(profile.graphicsBackend, .automatic)
        XCTAssertNil(profile.lastSuccessfulBackend)
    }

    func testRecordSuccessfulBackend() throws {
        var profile = LaunchProfile(graphicsBackend: .automatic)
        XCTAssertNil(profile.lastSuccessfulBackend)

        profile.recordSuccessfulLaunch(backend: .d3dmetal)
        XCTAssertEqual(profile.lastSuccessfulBackend, .d3dmetal)

        // Should persist
        let encoded = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(LaunchProfile.self, from: encoded)
        XCTAssertEqual(decoded.lastSuccessfulBackend, .d3dmetal)
    }

    // MARK: - Backend Resolver Tests

    func testExplicitBackendSelection() throws {
        var profile = LaunchProfile()
        profile.selectGraphicsBackend(.wined3d)

        // WineD3D is always available
        let resolved = try GraphicsBackendResolver.resolve(
            profile: profile,
            runtimeID: .mythicEngine
        )

        XCTAssertEqual(resolved, .wined3d)
    }

    func testExplicitBackendUnavailable() throws {
        var profile = LaunchProfile()
        profile.selectGraphicsBackend(.d3dmetal)

        // D3DMetal not available for Engine 2
        XCTAssertThrowsError(
            try GraphicsBackendResolver.resolve(
                profile: profile,
                runtimeID: .mythicEngine
            )
        ) { error in
            XCTAssertTrue(error is GraphicsBackendResolver.BackendUnavailableError)
        }
    }

    func testAutomaticBackendSelection() throws {
        let profile = LaunchProfile(graphicsBackend: .automatic)

        // Should resolve to a concrete backend
        let resolved = try GraphicsBackendResolver.resolve(
            profile: profile,
            runtimeID: .mythicEngine
        )

        // Should not be automatic
        XCTAssertNotEqual(resolved, .automatic)

        // Engine 2 should get DXVK or WineD3D
        XCTAssertTrue([.dxvk, .wined3d].contains(resolved))
    }

    func testLastSuccessfulBackendPreferred() throws {
        var profile = LaunchProfile(graphicsBackend: .automatic)
        profile.recordSuccessfulLaunch(backend: .wined3d)

        // Should prefer last successful backend
        let resolved = try GraphicsBackendResolver.resolve(
            profile: profile,
            runtimeID: .mythicEngine
        )

        XCTAssertEqual(resolved, .wined3d)
    }

    func testLastSuccessfulBackendIgnoredIfUnavailable() throws {
        var profile = LaunchProfile(graphicsBackend: .automatic)
        profile.recordSuccessfulLaunch(backend: .d3dmetal)

        // D3DMetal not available for Engine 2, should fall back to ranking
        let resolved = try GraphicsBackendResolver.resolve(
            profile: profile,
            runtimeID: .mythicEngine
        )

        // Should NOT be d3dmetal
        XCTAssertNotEqual(resolved, .d3dmetal)
    }

    // MARK: - Backend Detector Tests

    func testWineD3DAlwaysAvailable() {
        let engine2 = GraphicsBackendDetector.availableBackends(for: .mythicEngine)
        let wine11 = GraphicsBackendDetector.availableBackends(for: .wine11)
        let gptk = GraphicsBackendDetector.availableBackends(for: .gptk)

        XCTAssertTrue(engine2.contains(.wined3d), "WineD3D should always be available for Engine 2")
        XCTAssertTrue(wine11.contains(.wined3d), "WineD3D should always be available for Wine 11")
        XCTAssertTrue(gptk.contains(.wined3d), "WineD3D should always be available for GPTK")
    }

    func testEngine2ProvidesDXVK() {
        let available = GraphicsBackendDetector.availableBackends(for: .mythicEngine)

        // Engine 2 bundles DXVK
        XCTAssertTrue(available.contains(.dxvk), "Engine 2 should provide DXVK")
    }

    func testWine11ProvidesDXVK() {
        let available = GraphicsBackendDetector.availableBackends(for: .wine11)
        XCTAssertTrue(available.contains(.dxvk), "Wine 11 should provide DXVK")
    }

    func testD3DMetalNotAvailableForEngine2() {
        let available = GraphicsBackendDetector.availableBackends(for: .mythicEngine)

        // D3DMetal is not enabled on Engine 2 default
        XCTAssertFalse(available.contains(.d3dmetal), "D3DMetal should not be available for Engine 2")
    }

    func testD3DMetalNotAvailableForWine11() {
        let available = GraphicsBackendDetector.availableBackends(for: .wine11)
        XCTAssertFalse(available.contains(.d3dmetal), "Stock Wine 11 should not provide D3DMetal")

        var profile = LaunchProfile()
        profile.selectGraphicsBackend(.d3dmetal)
        XCTAssertThrowsError(try GraphicsBackendResolver.resolve(profile: profile, runtimeID: .wine11)) { error in
            XCTAssertTrue(error is GraphicsBackendResolver.BackendUnavailableError)
        }
    }

    func testGPTKProvidesD3DMetalWhenInstalled() {
        if GPTKInstaller.isInstalled(for: .gptk) {
            let available = GraphicsBackendDetector.availableBackends(for: .gptk)
            XCTAssertTrue(available.contains(.d3dmetal), "GPTK runtime should provide D3DMetal when installed")

            let profile = LaunchProfile(graphicsBackend: .automatic)
            let resolved = try? GraphicsBackendResolver.resolve(profile: profile, runtimeID: .gptk)
            XCTAssertEqual(resolved, .d3dmetal, "Automatic backend selection should prefer D3DMetal for GPTK runtime")
        }
    }

    // MARK: - Per-Game Isolation Tests

    func testPerGameBackendIsolation() throws {
        var game1Profile = LaunchProfile()
        game1Profile.selectGraphicsBackend(.d3dmetal)

        var game2Profile = LaunchProfile()
        game2Profile.selectGraphicsBackend(.dxvk)

        // Profiles should be independent
        XCTAssertEqual(game1Profile.graphicsBackend, .d3dmetal)
        XCTAssertEqual(game2Profile.graphicsBackend, .dxvk)

        // Modifying one should not affect the other
        game1Profile.selectGraphicsBackend(.wined3d)
        XCTAssertEqual(game1Profile.graphicsBackend, .wined3d)
        XCTAssertEqual(game2Profile.graphicsBackend, .dxvk)
    }

    // MARK: - No Silent Fallback Tests

    func testExplicitSelectionNeverFallsBack() throws {
        var profile = LaunchProfile()
        profile.selectGraphicsBackend(.d3dmetal)

        // If D3DMetal unavailable, should throw not fallback
        XCTAssertThrowsError(
            try GraphicsBackendResolver.resolve(
                profile: profile,
                runtimeID: .mythicEngine
            )
        ) { error in
            guard let backendError = error as? GraphicsBackendResolver.BackendUnavailableError else {
                XCTFail("Expected BackendUnavailableError")
                return
            }

            XCTAssertEqual(backendError.backend, .d3dmetal)
            XCTAssertNotNil(backendError.errorDescription)
            XCTAssertNotNil(backendError.recoverySuggestion)
        }
    }
}
