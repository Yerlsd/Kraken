//
//  ReportedGPUMemoryTests.swift
//  KrakenTests
//
// Copyright © 2026 Kraken contributors
//

import XCTest
@testable import Kraken

final class ReportedGPUMemoryTests: XCTestCase {

    // MARK: - ReportedGPUMemoryPolicy Codable Tests

    func testReportedGPUMemoryPolicyCodableAutomatic() throws {
        let policy = ReportedGPUMemoryPolicy.automatic
        let encoder = JSONEncoder()
        let data = try encoder.encode(policy)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ReportedGPUMemoryPolicy.self, from: data)

        XCTAssertEqual(decoded, .automatic)
    }

    func testReportedGPUMemoryPolicyCodableManual() throws {
        let policy = ReportedGPUMemoryPolicy.manual(megabytes: 4095)
        let encoder = JSONEncoder()
        let data = try encoder.encode(policy)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ReportedGPUMemoryPolicy.self, from: data)

        XCTAssertEqual(decoded, .manual(megabytes: 4095))
    }

    func testReportedGPUMemoryPolicyDecodeMalformedFallsBackToAutomatic() throws {
        let json = """
        {"mode": "unknown_future_mode", "megabytes": 9999}
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ReportedGPUMemoryPolicy.self, from: json)

        XCTAssertEqual(decoded, .automatic)
    }

    // MARK: - Hardware Capabilities & Tier Resolution Tests

    func testResolverAutomaticTier64GB() {
        let mockHardware = MockHardwareCapabilities.memoryGB(64.0)
        let resolver = ReportedGPUMemoryResolver(hardware: mockHardware)

        let resolved = resolver.resolveMegabytes(for: .automatic)
        XCTAssertEqual(resolved, ReportedGPUMemoryResolver.Presets.ultra, "64 GB system should report 8192 MB")
    }

    func testResolverAutomaticTier32GB() {
        let mockHardware = MockHardwareCapabilities.memoryGB(32.0)
        let resolver = ReportedGPUMemoryResolver(hardware: mockHardware)

        let resolved = resolver.resolveMegabytes(for: .automatic)
        XCTAssertEqual(resolved, ReportedGPUMemoryResolver.Presets.ultra, "32 GB system should report 8192 MB")
    }

    func testResolverAutomaticTier16GB() {
        let mockHardware = MockHardwareCapabilities.memoryGB(16.0)
        let resolver = ReportedGPUMemoryResolver(hardware: mockHardware)

        let resolved = resolver.resolveMegabytes(for: .automatic)
        XCTAssertEqual(resolved, ReportedGPUMemoryResolver.Presets.high, "16 GB system should report 4095 MB to prevent DWORD overflow")
    }

    func testResolverAutomaticTier8GB() {
        let mockHardware = MockHardwareCapabilities.memoryGB(8.0)
        let resolver = ReportedGPUMemoryResolver(hardware: mockHardware)

        let resolved = resolver.resolveMegabytes(for: .automatic)
        XCTAssertEqual(resolved, ReportedGPUMemoryResolver.Presets.medium, "8 GB system should report 2048 MB")
    }

    func testResolverAutomaticTier4GB() {
        let mockHardware = MockHardwareCapabilities.memoryGB(4.0)
        let resolver = ReportedGPUMemoryResolver(hardware: mockHardware)

        let resolved = resolver.resolveMegabytes(for: .automatic)
        XCTAssertEqual(resolved, ReportedGPUMemoryResolver.Presets.low, "4 GB system should report 1024 MB")
    }

    func testResolverManualClamping() {
        let resolver = ReportedGPUMemoryResolver(hardware: MockHardwareCapabilities.memoryGB(16.0))

        // Too small -> clamp to 512
        let tooSmall = resolver.resolveMegabytes(for: .manual(megabytes: 128))
        XCTAssertEqual(tooSmall, 512)

        // Valid custom value -> preserve
        let valid = resolver.resolveMegabytes(for: .manual(megabytes: 3072))
        XCTAssertEqual(valid, 3072)

        // Too large -> clamp to 65536
        let tooLarge = resolver.resolveMegabytes(for: .manual(megabytes: 100_000))
        XCTAssertEqual(tooLarge, 65536)
    }

    // MARK: - DXVK Configuration Manager Tests

    func testDXVKConfigurationGeneration() {
        let content = DXVKConfigurationManager.generateConfigContent(memoryMB: 4095)

        XCTAssertTrue(content.contains("dxgi.nvapiHack = False"))
        XCTAssertTrue(content.contains("dxgi.emulateUMA = False"))
        XCTAssertTrue(content.contains("dxgi.maxDeviceMemory = 4095"))
        XCTAssertTrue(content.contains("dxgi.maxSharedMemory = 4095"))
        XCTAssertTrue(content.contains("d3d11.invariantPosition = True"))
    }

    func testDXVKConfigurationWriteToFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try DXVKConfigurationManager.writeConfiguration(toContainerAtURL: tempDir, memoryMB: 4095)

        let writtenFile = tempDir.appending(path: "drive_c/windows/dxvk.conf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: writtenFile.path))

        let readContent = try String(contentsOf: writtenFile, encoding: .utf8)
        XCTAssertTrue(readContent.contains("dxgi.maxDeviceMemory = 4095"))
    }

    // MARK: - Fresh Container Defaults

    func testFreshContainerDefaults() {
        let settings = Wine.Container.Settings()
        XCTAssertFalse(settings.retinaMode, "Fresh containers must default to retinaMode == false")
        XCTAssertEqual(settings.scaling, 96, "Fresh containers must default to 96 DPI (1x scaling)")
    }

    // MARK: - Launch Profile Integration Tests

    func testLaunchProfileReportedGPUMemoryIntegration() throws {
        var profile = LaunchProfile()
        XCTAssertEqual(profile.reportedGPUMemoryPolicy, .automatic)

        profile.selectReportedGPUMemoryPolicy(.manual(megabytes: 2048))
        XCTAssertEqual(profile.reportedGPUMemoryPolicy, .manual(megabytes: 2048))

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(LaunchProfile.self, from: data)

        XCTAssertEqual(decoded.reportedGPUMemoryPolicy, .manual(megabytes: 2048))
    }

    // MARK: - Runtime Resolver Integration Tests

    func testDXVKEnvironmentIncludesConfigFile() {
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

        XCTAssertEqual(env["WINEDLLOVERRIDES"], "d3d10core,d3d11,dxgi=n,b")
        XCTAssertEqual(env["DXVK_ASYNC"], "1")
        XCTAssertEqual(env["DXVK_CONFIG_FILE"], "C:\\windows\\dxvk.conf", "DXVK backend must set DXVK_CONFIG_FILE to C:\\windows\\dxvk.conf")
    }

    func testSymmetricSuccessfulBackendRecording() {
        var profile = LaunchProfile()
        XCTAssertNil(profile.lastSuccessfulBackend)

        profile.recordSuccessfulLaunch(backend: .dxvk)
        XCTAssertEqual(profile.lastSuccessfulBackend, .dxvk)

        profile.recordSuccessfulLaunch(backend: .d3dmetal)
        XCTAssertEqual(profile.lastSuccessfulBackend, .d3dmetal)
    }
}
