//
//  RuntimeIsolationTests.swift
//  KrakenTests
//
// Copyright © 2026 Kraken contributors
//

import XCTest
@testable import Kraken

final class RuntimeIsolationTests: XCTestCase {

    // MARK: - 1. RuntimeID Raw Value & Serialization Integrity

    func testRuntimeIDRawValuesUnchanged() {
        XCTAssertEqual(RuntimeID.mythicEngine.rawValue, "mythic-engine")
        XCTAssertEqual(RuntimeID.wine11.rawValue, "wine-11")
        XCTAssertEqual(RuntimeID.gptk.rawValue, "gptk")
    }

    func testRuntimeIDCodableRoundTrip() throws {
        for id in RuntimeID.allCases {
            let data = try JSONEncoder().encode(id)
            let decoded = try JSONDecoder().decode(RuntimeID.self, from: data)
            XCTAssertEqual(decoded, id)
        }
    }

    // MARK: - 2. Runtime Descriptor & Registry Integrity

    func testRuntimeRegistryProvidesDescriptorsForAllIDs() {
        let registry = RuntimeRegistry.shared
        for id in RuntimeID.allCases {
            let descriptor = registry.descriptor(for: id)
            XCTAssertNotNil(descriptor, "Descriptor should exist for \(id)")
            XCTAssertEqual(descriptor?.id, id)
        }
    }

    func testMythicEngineDescriptorOwnership() {
        let descriptor = RuntimeRegistry.shared.descriptor(for: .mythicEngine)
        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.family, .mythicEngine)
        XCTAssertEqual(descriptor?.displayName, "Mythic Engine")
        XCTAssertEqual(descriptor?.baseDirectory, Engine.directory)
        XCTAssertTrue(descriptor?.capabilities.contains(.providesDXVK) == true)
        XCTAssertTrue(descriptor?.capabilities.contains(.providesWineD3D) == true)
        XCTAssertFalse(descriptor?.capabilities.contains(.requiresExplicitLoader) == true)
    }

    func testWine11DescriptorOwnership() {
        let descriptor = RuntimeRegistry.shared.descriptor(for: .wine11)
        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.family, .wine11)
        XCTAssertEqual(descriptor?.displayName, "Wine 11")
        XCTAssertEqual(descriptor?.baseDirectory, Engine.runtimeDirectory.appending(path: "wine11"))
        XCTAssertTrue(descriptor?.capabilities.contains(.providesDXVK) == true)
        XCTAssertTrue(descriptor?.capabilities.contains(.providesWineD3D) == true)
        XCTAssertTrue(descriptor?.capabilities.contains(.requiresExplicitLoader) == true)
    }

    func testGPTKDescriptorOwnership() {
        let descriptor = RuntimeRegistry.shared.descriptor(for: .gptk)
        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.family, .gptk)
        XCTAssertEqual(descriptor?.displayName, "GPTK 4")
        XCTAssertEqual(descriptor?.baseDirectory, Engine.runtimeDirectory.appending(path: "gptk"))
    }

    // MARK: - 3. Runtime Resolution Isolation

    func testMythicEngineResolvesToOwnDirectory() {
        let runtime = Engine.wineRuntime(for: .mythicEngine)
        XCTAssertEqual(runtime.id, .mythicEngine)
        XCTAssertEqual(runtime.rootDirectory, Engine.directory)
        XCTAssertEqual(runtime.wineExecutable, Engine.directory.appending(path: "wine/bin/wine64"))
        XCTAssertEqual(runtime.wineserverExecutable, Engine.directory.appending(path: "wine/bin/wineserver"))
        XCTAssertNil(runtime.wineBundleURL)
    }

    func testWine11ResolvesToOwnBundle() {
        let runtime = Engine.wineRuntime(for: .wine11)
        let expectedRoot = Engine.runtimeDirectory.appending(path: "wine11")
        let expectedBundle = expectedRoot.appending(path: "Wine Stable.app")
        let expectedWineRoot = expectedBundle.appending(path: "Contents/Resources/wine")

        XCTAssertEqual(runtime.id, .wine11)
        XCTAssertEqual(runtime.rootDirectory, expectedRoot)
        XCTAssertEqual(runtime.wineBundleURL, expectedBundle)
        XCTAssertEqual(runtime.wineExecutable, expectedWineRoot.appending(path: "bin/wine"))
        XCTAssertEqual(runtime.wineserverExecutable, expectedWineRoot.appending(path: "bin/wineserver"))
    }

    func testGPTKResolvesToIsolatedDirectory() {
        let runtime = Engine.wineRuntime(for: .gptk)
        let expectedRoot = Engine.runtimeDirectory.appending(path: "gptk")

        XCTAssertEqual(runtime.id, .gptk)
        XCTAssertEqual(runtime.rootDirectory, expectedRoot)
        XCTAssertEqual(runtime.wineExecutable, expectedRoot.appending(path: "wine/bin/wine64"))
        XCTAssertEqual(runtime.wineserverExecutable, expectedRoot.appending(path: "wine/bin/wineserver"))
        XCTAssertNil(runtime.wineBundleURL)

        // Strict isolation: GPTK must never borrow Engine 2 or Wine 11 root directory
        XCTAssertNotEqual(runtime.rootDirectory, Engine.directory, "GPTK must not borrow Engine 2 root directory")
        XCTAssertNotEqual(runtime.rootDirectory, Engine.runtimeDirectory.appending(path: "wine11"), "GPTK must not borrow Wine 11 root directory")
    }

    // MARK: - 4. Mock Provider Custom Registry

    func testCustomRegistryWithMockProvider() {
        let mockProvider = MockRuntimeProvider(
            id: .wine11,
            displayName: "Test Mock Wine 11",
            installed: true,
            rootDirectory: URL(fileURLWithPath: "/tmp/mock_wine11")
        )

        let customRegistry = RuntimeRegistry(providers: [mockProvider])
        XCTAssertTrue(customRegistry.isInstalled(.wine11))
        XCTAssertFalse(customRegistry.isInstalled(.mythicEngine), "Unregistered provider should report not installed")

        let resolved = customRegistry.resolveRuntime(for: .wine11)
        XCTAssertEqual(resolved.rootDirectory, URL(fileURLWithPath: "/tmp/mock_wine11"))
    }

    // MARK: - 5. Runtime Resolver Affinity & Determinism

    func testResolverRejectsContainerRuntimeMismatch() {
        // Construct a profile targeting Wine 11 but with an Engine 2 container URL
        let mockURL = URL(fileURLWithPath: "/tmp/nonexistent_test_container")
        let profile = LaunchProfile(
            container: ContainerReference(url: mockURL),
            defaultRuntimeID: .wine11,
            runtimeOverride: nil
        )

        XCTAssertThrowsError(try RuntimeResolver.resolve(profile: profile))
    }

    func testRuntimeResolverLoaderRequirements() {
        XCTAssertTrue(RuntimeID.wine11.requiresExplicitLoaderEnvironment)
        XCTAssertFalse(RuntimeID.mythicEngine.requiresExplicitLoaderEnvironment)
        XCTAssertFalse(RuntimeID.gptk.requiresExplicitLoaderEnvironment)
    }
}
