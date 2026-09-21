//
//  GameStoragePreflightTests.swift
//  KrakenTests
//
// Copyright © 2026 Kraken contributors
//

import XCTest
@testable import Kraken

final class GameStoragePreflightTests: XCTestCase {

    // MARK: - Codable Round-Trip Tests

    func testStorageReadinessCodable() throws {
        let cases: [StorageReadiness] = [
            .ready,
            .materializationRequired(datalessCount: 15239, totalBytes: 6245123987),
            .cloudLocationWarning(path: "/Users/test/Documents/Game")
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for original in cases {
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(StorageReadiness.self, from: data)
            XCTAssertEqual(original, decoded)
        }
    }

    func testStoragePreflightResultCodable() throws {
        let original = StoragePreflightResult(
            isUbiquitous: true,
            isInCloudManagedDirectory: true,
            datalessFileCount: 42,
            datalessBytes: 104857600,
            totalFilesChecked: 100,
            readiness: .materializationRequired(datalessCount: 42, totalBytes: 104857600)
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(StoragePreflightResult.self, from: data)

        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.datalessFileCount, 42)
        XCTAssertEqual(decoded.datalessBytes, 104857600)
    }

    // MARK: - Cloud Directory Path Detection

    func testCloudDirectoryPathDetection() {
        let home = NSHomeDirectory()
        let documentsGame = "\(home)/Documents/Subnautica"
        let desktopGame = "\(home)/Desktop/Game"
        let mobileDocs = "\(home)/Library/Mobile Documents/com~apple~CloudDocs/Game"

        let gamesFolder = "\(home)/Games/Subnautica"
        let sharedFolder = "/Users/Shared/Games/Subnautica"
        let appSupportFolder = "\(home)/Library/Application Support/Kraken/Games"

        XCTAssertTrue(GameStoragePreflight.isPathInCloudManagedDirectory(documentsGame))
        XCTAssertTrue(GameStoragePreflight.isPathInCloudManagedDirectory(desktopGame))
        XCTAssertTrue(GameStoragePreflight.isPathInCloudManagedDirectory(mobileDocs))

        XCTAssertFalse(GameStoragePreflight.isPathInCloudManagedDirectory(gamesFolder))
        XCTAssertFalse(GameStoragePreflight.isPathInCloudManagedDirectory(sharedFolder))
        XCTAssertFalse(GameStoragePreflight.isPathInCloudManagedDirectory(appSupportFolder))
    }

    // MARK: - Diagnostic Summaries

    func testDiagnosticSummaries() {
        let readyResult = StoragePreflightResult(
            isUbiquitous: false,
            isInCloudManagedDirectory: false,
            datalessFileCount: 0,
            datalessBytes: 0,
            totalFilesChecked: 1500,
            readiness: .ready
        )
        XCTAssertTrue(readyResult.diagnosticSummary.contains("Storage ready"))

        let datalessResult = StoragePreflightResult(
            isUbiquitous: true,
            isInCloudManagedDirectory: true,
            datalessFileCount: 1000,
            datalessBytes: 524288000,
            totalFilesChecked: 1000,
            readiness: .materializationRequired(datalessCount: 1000, totalBytes: 524288000)
        )
        XCTAssertTrue(datalessResult.diagnosticSummary.contains("Performance Warning"))
        XCTAssertTrue(datalessResult.diagnosticSummary.contains("dataless"))

        let cloudWarningResult = StoragePreflightResult(
            isUbiquitous: true,
            isInCloudManagedDirectory: true,
            datalessFileCount: 0,
            datalessBytes: 0,
            totalFilesChecked: 50,
            readiness: .cloudLocationWarning(path: "/Users/test/Documents")
        )
        XCTAssertTrue(cloudWarningResult.diagnosticSummary.contains("Location Notice"))
    }

    // MARK: - Inspection on Local Temporary Directory

    func testInspectLocalCleanDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("GameStoragePreflightTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create 5 small dummy files
        for fileIndex in 0..<5 {
            let fileURL = tempDir.appendingPathComponent("asset_\(fileIndex).dat")
            try Data("test_content_\(fileIndex)".utf8).write(to: fileURL)
        }

        let result = GameStoragePreflight.inspect(at: tempDir)
        XCTAssertEqual(result.datalessFileCount, 0)
        XCTAssertEqual(result.datalessBytes, 0)
        XCTAssertEqual(result.totalFilesChecked, 5)
        XCTAssertEqual(result.readiness, .ready)
    }

    func testMaterializeOnLocalFilesDoesNotThrow() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("GameStoragePreflightTest_Mat_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("dummy.bin")
        try Data("dummy".utf8).write(to: fileURL)

        let count = GameStoragePreflight.materializeDatalessFiles(in: tempDir)
        XCTAssertEqual(count, 0) // No dataless files in temp
    }
}
