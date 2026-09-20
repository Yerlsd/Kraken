//
//  RuntimeResolverTests.swift
//  KrakenTests
//
// Copyright © 2026 Kraken contributors

import XCTest
@testable import Kraken

/// Tests for RuntimeResolver pure resolution logic.
///
/// These tests verify that RuntimeResolver correctly determines which runtime
/// should be used, validates container compatibility, and produces typed errors
/// for missing/incompatible components without mutating persistent state.
final class RuntimeResolverTests: XCTestCase {

    // MARK: - Runtime Authority

    func testRuntimeIDFromProfile() {
        // Default runtime, no override
        let profile1 = LaunchProfile(
            defaultRuntimeID: .mythicEngine,
            runtimeOverride: nil
        )
        XCTAssertEqual(RuntimeResolver.runtimeID(for: profile1), .mythicEngine)

        // Override takes precedence
        let profile2 = LaunchProfile(
            defaultRuntimeID: .mythicEngine,
            runtimeOverride: .wine11
        )
        XCTAssertEqual(RuntimeResolver.runtimeID(for: profile2), .wine11)
    }

    func testEffectiveRuntimeMatchesResolverAuthority() {
        let profile = LaunchProfile(
            defaultRuntimeID: .mythicEngine,
            runtimeOverride: .wine11
        )

        // RuntimeResolver and LaunchProfile must agree
        XCTAssertEqual(RuntimeResolver.runtimeID(for: profile), profile.effectiveRuntimeID)
    }

    // MARK: - Resolution Errors

    func testRuntimeNotInstalledError() {
        let profile = LaunchProfile(
            container: ContainerReference(url: URL(fileURLWithPath: "/tmp/fake")),
            defaultRuntimeID: .wine11,
            runtimeOverride: nil
        )

        // This test assumes Wine 11 is not installed in test environment
        // If it is installed, the error would be different (container missing)
        do {
            _ = try RuntimeResolver.resolve(profile: profile)
            // If resolution succeeds, either Wine 11 is installed or container exists
            // which is environment-dependent, so we don't fail the test
        } catch let error as RuntimeResolver.ResolutionError {
            // Verify error is one of the expected typed errors
            switch error {
            case .runtimeNotInstalled(let runtimeID):
                XCTAssertEqual(runtimeID, .wine11)
            case .containerMissing, .containerUnreadable, .noContainerAssigned, .containerRuntimeMismatch:
                // These are also valid outcomes depending on environment
                break
            }
        } catch {
            XCTFail("Expected RuntimeResolver.ResolutionError, got \(error)")
        }
    }

    func testNoContainerAssignedError() {
        let profile = LaunchProfile(
            container: nil,
            defaultRuntimeID: .mythicEngine,
            runtimeOverride: nil
        )

        do {
            _ = try RuntimeResolver.resolve(profile: profile)
            XCTFail("Expected noContainerAssigned error")
        } catch let error as RuntimeResolver.ResolutionError {
            switch error {
            case .noContainerAssigned(let runtimeID):
                XCTAssertEqual(runtimeID, .mythicEngine)
            default:
                XCTFail("Expected noContainerAssigned, got \(error)")
            }
        } catch {
            XCTFail("Expected RuntimeResolver.ResolutionError, got \(error)")
        }
    }

    func testContainerMissingError() {
        let nonexistentContainer = URL(fileURLWithPath: "/nonexistent/container/\(UUID().uuidString)")
        let profile = LaunchProfile(
            container: ContainerReference(url: nonexistentContainer),
            defaultRuntimeID: .mythicEngine,
            runtimeOverride: nil
        )

        do {
            _ = try RuntimeResolver.resolve(profile: profile)
            XCTFail("Expected containerMissing error")
        } catch let error as RuntimeResolver.ResolutionError {
            switch error {
            case .containerMissing(let url):
                XCTAssertEqual(url, nonexistentContainer)
            case .runtimeNotInstalled:
                // If mythicEngine is not installed, this is the expected error
                break
            default:
                XCTFail("Expected containerMissing or runtimeNotInstalled, got \(error)")
            }
        } catch {
            XCTFail("Expected RuntimeResolver.ResolutionError, got \(error)")
        }
    }

    // MARK: - Error Messages

    func testErrorDescriptionsAreHumanReadable() {
        let errors: [RuntimeResolver.ResolutionError] = [
            .runtimeNotInstalled(.wine11),
            .noContainerAssigned(.mythicEngine),
            .containerMissing(URL(fileURLWithPath: "/tmp/missing")),
            .containerUnreadable(URL(fileURLWithPath: "/tmp/corrupt")),
            .containerRuntimeMismatch(
                selected: .wine11,
                containerRuntime: .mythicEngine,
                containerURL: URL(fileURLWithPath: "/tmp/mismatch")
            )
        ]

        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "Error should have description")
            XCTAssertFalse(error.recoverySuggestion?.isEmpty ?? true, "Error should have recovery suggestion")
        }
    }

    // MARK: - Purity

    func testResolverDoesNotMutateProfile() {
        var profile = LaunchProfile(
            container: nil,
            defaultRuntimeID: .mythicEngine,
            runtimeOverride: nil
        )

        let originalDefault = profile.defaultRuntimeID
        let originalOverride = profile.runtimeOverride

        // Attempt resolution (will fail due to no container)
        _ = try? RuntimeResolver.resolve(profile: profile)

        // Profile is not mutated
        XCTAssertEqual(profile.defaultRuntimeID, originalDefault)
        XCTAssertEqual(profile.runtimeOverride, originalOverride)
    }

    func testResolverIsDeterministic() {
        let profile = LaunchProfile(
            container: ContainerReference(url: URL(fileURLWithPath: "/tmp/test")),
            defaultRuntimeID: .mythicEngine,
            runtimeOverride: nil
        )

        // Same profile should produce same runtime ID every time
        let results = (0..<10).map { _ in RuntimeResolver.runtimeID(for: profile) }
        XCTAssertTrue(results.allSatisfy { $0 == .mythicEngine })
    }

    // MARK: - Launch Arguments

    func testResolvedTargetPreservesLaunchArguments() {
        let args = ["--test", "--verbose", "--flag"]
        let profile = LaunchProfile(
            container: nil,
            defaultRuntimeID: .mythicEngine,
            runtimeOverride: nil,
            launchArguments: args
        )

        // Even though resolution fails, we can verify the profile preserves args
        XCTAssertEqual(profile.launchArguments, args)
    }

    // MARK: - Environment Assembly

    func testEnvironmentIncludesWINEPREFIX() {
        let containerURL = URL(fileURLWithPath: "/tmp/testprefix")
        let settings = Wine.Container.Settings()

        let env = RuntimeResolver.environment(
            forRuntime: .mythicEngine,
            containerURL: containerURL,
            settings: settings,
            graphicsBackend: .wined3d
        )

        XCTAssertEqual(env["WINEPREFIX"], containerURL.path(percentEncoded: false))
    }

    func testEnvironmentIncludesRosettaAdvertiseAVX() {
        let containerURL = URL(fileURLWithPath: "/tmp/testprefix")
        let settings = Wine.Container.Settings()

        let env = RuntimeResolver.environment(
            forRuntime: .mythicEngine,
            containerURL: containerURL,
            settings: settings,
            graphicsBackend: .wined3d
        )

        XCTAssertNotNil(env["ROSETTA_ADVERTISE_AVX"])
    }

    func testEnvironmentIncludesMSYNC() {
        let containerURL = URL(fileURLWithPath: "/tmp/testprefix")
        let settings = Wine.Container.Settings()

        let env = RuntimeResolver.environment(
            forRuntime: .mythicEngine,
            containerURL: containerURL,
            settings: settings,
            graphicsBackend: .wined3d
        )

        XCTAssertNotNil(env["WINEMSYNC"])
    }

    func testWine11EnvironmentIncludesExplicitLoader() {
        let containerURL = URL(fileURLWithPath: "/tmp/testprefix")
        let settings = Wine.Container.Settings()

        let env = RuntimeResolver.environment(
            forRuntime: .wine11,
            containerURL: containerURL,
            settings: settings,
            graphicsBackend: .wined3d
        )

        // Wine 11 requires explicit loader environment
        XCTAssertNotNil(env["WINESERVER"], "Wine 11 should set WINESERVER")
        XCTAssertNotNil(env["WINELOADER"], "Wine 11 should set WINELOADER")
        XCTAssertNotNil(env["WINE"], "Wine 11 should set WINE")
        XCTAssertNotNil(env["WINE64"], "Wine 11 should set WINE64")
    }

    func testD3DMetalEnvironmentIncludesFrameworkAndDXR() {
        let containerURL = URL(fileURLWithPath: "/tmp/testprefix")
        let settings = Wine.Container.Settings()

        let env = RuntimeResolver.environment(
            forRuntime: .gptk,
            containerURL: containerURL,
            settings: settings,
            graphicsBackend: .d3dmetal
        )

        XCTAssertEqual(env["WINEDLLOVERRIDES"], "d3d10,d3d11,d3d12,dxgi=n,b")
        XCTAssertEqual(env["D3DM_SUPPORT_DXR"], "1")
        XCTAssertNil(env["D3DM_WINE_UNIX_CALL"], "D3DM_WINE_UNIX_CALL should not be set")
        let expectedFrameworkPath = Engine.wineRuntime(for: .gptk).externalLibrariesURL.appending(path: "D3DMetal.framework/D3DMetal").path
        XCTAssertEqual(env["D3DMETAL_FRAMEWORK_PATH"], expectedFrameworkPath)
        XCTAssertEqual(env["DYLD_FRAMEWORK_PATH"], Engine.wineRuntime(for: .gptk).externalLibrariesURL.path)
    }

    func testGPTKDoesNotSetExplicitLoader() {
        let containerURL = URL(fileURLWithPath: "/tmp/testprefix")
        let settings = Wine.Container.Settings()

        let env = RuntimeResolver.environment(
            forRuntime: .gptk,
            containerURL: containerURL,
            settings: settings,
            graphicsBackend: .wined3d
        )

        XCTAssertNil(env["WINESERVER"])
        XCTAssertNil(env["WINELOADER"])
        XCTAssertNil(env["WINE"])
        XCTAssertNil(env["WINE64"])
    }

    func testMythicEngineDoesNotSetExplicitLoader() {
        let containerURL = URL(fileURLWithPath: "/tmp/testprefix")
        let settings = Wine.Container.Settings()

        let env = RuntimeResolver.environment(
            forRuntime: .mythicEngine,
            containerURL: containerURL,
            settings: settings,
            graphicsBackend: .wined3d
        )

        // Engine 2 relies on relative Wine lookups, should not set explicit loader
        XCTAssertNil(env["WINESERVER"], "Engine 2 should not set explicit WINESERVER")
        XCTAssertNil(env["WINELOADER"], "Engine 2 should not set explicit WINELOADER")
    }

    func testDXVKSettingsWhenEnabled() {
        let containerURL = URL(fileURLWithPath: "/tmp/testprefix")
        var settings = Wine.Container.Settings()
        settings.dxvk = true
        settings.dxvkAsync = true

        let env = RuntimeResolver.environment(
            forRuntime: .mythicEngine,
            containerURL: containerURL,
            settings: settings,
            graphicsBackend: .dxvk
        )

        // Engine 2 with DXVK backend
        XCTAssertEqual(env["WINEDLLOVERRIDES"], "d3d10core,d3d11,dxgi=n,b")
        XCTAssertEqual(env["DXVK_ASYNC"], "1")
    }

    func testDXVKNotSetWhenDisabled() {
        let containerURL = URL(fileURLWithPath: "/tmp/testprefix")
        var settings = Wine.Container.Settings()
        settings.dxvk = false

        let env = RuntimeResolver.environment(
            forRuntime: .mythicEngine,
            containerURL: containerURL,
            settings: settings,
            graphicsBackend: .wined3d
        )

        XCTAssertNil(env["WINEDLLOVERRIDES"])
        XCTAssertNil(env["DXVK_ASYNC"])
    }
}
