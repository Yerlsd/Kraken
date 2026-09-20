//
//  RuntimePackageTests.swift
//  KrakenTests
//
// Copyright © 2026 Kraken contributors
//

import XCTest
@testable import Kraken

final class RuntimePackageTests: XCTestCase {

    // MARK: - 1. Manifest Structure & Properties

    func testRuntimeManifestsExistForAllRegisteredRuntimes() {
        let registry = RuntimeRegistry.shared
        for id in RuntimeID.allCases {
            let manifest = registry.manifest(for: id)
            XCTAssertNotNil(manifest, "Manifest must exist for \(id.rawValue)")
            XCTAssertEqual(manifest?.id, id)
        }
    }

    func testMythicEngineManifestProperties() {
        guard let manifest = RuntimeRegistry.shared.manifest(for: .mythicEngine) else {
            return XCTFail("Mythic Engine manifest not found")
        }
        XCTAssertEqual(manifest.family, .mythicEngine)
        XCTAssertEqual(manifest.technicalVersion, "7.7-mythic")
        XCTAssertTrue(manifest.requiredRelativePaths.contains("wine/bin/wine64"))
        XCTAssertTrue(manifest.requiredRelativePaths.contains("wine/bin/wineserver"))
        XCTAssertEqual(manifest.supportedGraphicsBackends, [.dxvk, .wined3d])
    }

    func testWine11ManifestProperties() {
        guard let manifest = RuntimeRegistry.shared.manifest(for: .wine11) else {
            return XCTFail("Wine 11 manifest not found")
        }
        XCTAssertEqual(manifest.family, .wine11)
        XCTAssertEqual(manifest.technicalVersion, "11.0_1")
        XCTAssertTrue(manifest.requiredRelativePaths.contains("Wine Stable.app/Contents/Resources/wine/bin/wine"))
        XCTAssertTrue(manifest.requiredRelativePaths.contains("Wine Stable.app/Contents/Resources/wine/bin/wineserver"))
        XCTAssertTrue(manifest.requiredRelativePaths.contains("Wine Stable.app/Contents/Resources/wine/bin/wineboot"))
        XCTAssertTrue(manifest.requiredRelativePaths.contains("Wine Stable.app/Contents/Resources/wine/lib/wine/x86_64-unix/ntdll.so"))
        XCTAssertTrue(manifest.requiredRelativePaths.contains("Wine Stable.app/Contents/Resources/wine/lib/wine/x86_64-windows/wined3d.dll"))
        XCTAssertEqual(manifest.supportedGraphicsBackends, [.dxvk, .wined3d, .d3dmetal, .dxmt])
    }

    func testGPTKManifestProperties() {
        guard let manifest = RuntimeRegistry.shared.manifest(for: .gptk) else {
            return XCTFail("GPTK manifest not found")
        }
        XCTAssertEqual(manifest.family, .gptk)
        XCTAssertEqual(manifest.technicalVersion, "4.0-beta2")
        XCTAssertEqual(manifest.supportedGraphicsBackends, [.d3dmetal, .wined3d])
    }

    // MARK: - 2. Package Verification Logic

    func testManifestVerificationWithNonexistentDirectory() {
        let manifest = RuntimeManifest(
            id: .wine11,
            family: .wine11,
            technicalVersion: "11.0",
            requiredRelativePaths: ["bin/wine"],
            supportedGraphicsBackends: [.dxvk]
        )
        let nonExistentURL = URL(fileURLWithPath: "/tmp/nonexistent_runtime_dir_\(UUID().uuidString)")
        let result = manifest.verify(at: nonExistentURL)

        XCTAssertFalse(result.isReady)
        XCTAssertEqual(result.status, .notInstalled)
        XCTAssertEqual(result.missingPaths, [nonExistentURL.path])
    }

    func testManifestVerificationWithMissingComponents() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "test_runtime_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create one required file but omit the other
        let presentFile = tempDir.appending(path: "bin/wine")
        try FileManager.default.createDirectory(at: presentFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "dummy".write(to: presentFile, atomically: true, encoding: .utf8)

        let manifest = RuntimeManifest(
            id: .wine11,
            family: .wine11,
            technicalVersion: "11.0",
            requiredRelativePaths: ["bin/wine", "bin/wineserver"],
            supportedGraphicsBackends: [.dxvk]
        )

        let result = manifest.verify(at: tempDir)
        XCTAssertFalse(result.isReady)
        XCTAssertEqual(result.missingPaths, ["bin/wineserver"])
        XCTAssertEqual(result.status, .missingComponents(["bin/wineserver"]))
    }

    func testManifestVerificationSuccess() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "test_runtime_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create all required files
        let wineFile = tempDir.appending(path: "bin/wine")
        let serverFile = tempDir.appending(path: "bin/wineserver")
        try FileManager.default.createDirectory(at: wineFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "dummy".write(to: wineFile, atomically: true, encoding: .utf8)
        try "dummy".write(to: serverFile, atomically: true, encoding: .utf8)

        let manifest = RuntimeManifest(
            id: .wine11,
            family: .wine11,
            technicalVersion: "11.0",
            requiredRelativePaths: ["bin/wine", "bin/wineserver"],
            supportedGraphicsBackends: [.dxvk]
        )

        let result = manifest.verify(at: tempDir)
        XCTAssertTrue(result.isReady)
        XCTAssertEqual(result.status, .verified)
        XCTAssertTrue(result.missingPaths.isEmpty)
    }

    // MARK: - 3. Mock Provider Verification

    func testMockProviderVerificationIntegration() {
        let mockInstalled = MockRuntimeProvider(id: .wine11, installed: true)
        XCTAssertTrue(mockInstalled.verify().isReady)
        XCTAssertEqual(mockInstalled.verify().status, .verified)

        let mockUninstalled = MockRuntimeProvider(id: .wine11, installed: false)
        XCTAssertFalse(mockUninstalled.verify().isReady)
        XCTAssertEqual(mockUninstalled.verify().status, .notInstalled)
    }
}
