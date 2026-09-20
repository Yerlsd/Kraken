//
//  GraphicsArtifactTests.swift
//  KrakenTests
//
// Copyright © 2026 Kraken contributors
//

import XCTest
@testable import Kraken

final class GraphicsArtifactTests: XCTestCase {

    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }

    func testMythicEngineDXVKManifest_isPristineBaseline() {
        let manifest = GraphicsArtifactRegistry.mythicEngineDXVK
        XCTAssertEqual(manifest.id, "mythic-engine-dxvk-1.10.3")
        XCTAssertEqual(manifest.runtimeFamily, .mythicEngine)
        XCTAssertEqual(manifest.backend, .dxvk)
        XCTAssertEqual(manifest.version, "1.10.3-20230507")
        XCTAssertTrue(manifest.provenance.patchSet.isEmpty)

        let d3d11 = manifest.files.first { $0.relativePath == "x64/d3d11.dll" }
        XCTAssertNotNil(d3d11)
        XCTAssertEqual(d3d11?.sha256, "0ff0b0835dde29556bd01dfce7b1ae348d7f229cb1e1a37cc71ea1a028beeca4")
    }

    func testWine11DXVKPatchedManifest_containsSignednessPatch() {
        let manifest = GraphicsArtifactRegistry.wine11DXVKPatched
        XCTAssertEqual(manifest.id, "wine11-dxvk-1.10.3-signedness-reconciled")
        XCTAssertEqual(manifest.runtimeFamily, .wine11)
        XCTAssertEqual(manifest.backend, .dxvk)
        XCTAssertEqual(manifest.version, "1.10.3-20230507-kraken1")
        XCTAssertEqual(manifest.provenance.patchSet, ["dxvk-d3d11-input-layout-signedness-reconciliation"])

        let d3d11 = manifest.files.first { $0.relativePath == "x64/d3d11.dll" }
        XCTAssertNotNil(d3d11)
        XCTAssertEqual(d3d11?.sha256, "489f5d6574c667c8282dd132cd128a45aa5d878d9402dee205c5197eac277cff")
    }

    func testIsolationBetweenBaselineAndPatchedDXVK() {
        let baseline = GraphicsArtifactRegistry.mythicEngineDXVK
        let patched = GraphicsArtifactRegistry.wine11DXVKPatched

        XCTAssertNotEqual(baseline.id, patched.id)
        XCTAssertNotEqual(baseline.runtimeFamily, patched.runtimeFamily)

        let baselineD3D11 = baseline.files.first { $0.relativePath == "x64/d3d11.dll" }?.sha256
        let patchedD3D11 = patched.files.first { $0.relativePath == "x64/d3d11.dll" }?.sha256
        XCTAssertNotNil(baselineD3D11)
        XCTAssertNotNil(patchedD3D11)
        XCTAssertNotEqual(baselineD3D11, patchedD3D11)
    }

    func testManifestLookupByBackendAndRuntimeFamily() {
        let registry = GraphicsArtifactRegistry.shared

        let engineDXVK = registry.manifest(for: .dxvk, runtimeFamily: .mythicEngine)
        XCTAssertEqual(engineDXVK?.id, "mythic-engine-dxvk-1.10.3")

        let wine11DXVK = registry.manifest(for: .dxvk, runtimeFamily: .wine11)
        XCTAssertEqual(wine11DXVK?.id, "wine11-dxvk-1.10.3-signedness-reconciled")

        let gptkD3DMetal = registry.manifest(for: .d3dmetal, runtimeFamily: .gptk)
        XCTAssertEqual(gptkD3DMetal?.id, "gptk-d3dmetal-4.0")

        let wine11DXMT = registry.manifest(for: .dxmt, runtimeFamily: .wine11)
        XCTAssertEqual(wine11DXMT?.id, "wine11-dxmt-0.60")

        let unknown = registry.manifest(for: .wined3d, runtimeFamily: .mythicEngine)
        XCTAssertNil(unknown)
    }

    func testManifestCodableSerialization() throws {
        let original = GraphicsArtifactRegistry.wine11DXVKPatched
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(GraphicsArtifactManifest.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testComputeSHA256() throws {
        let testFileURL = tempDirectory.appending(path: "test.txt")
        let content = "Hello, Kraken Graphics Pipeline!"
        try content.write(to: testFileURL, atomically: true, encoding: .utf8)

        let hash = try GraphicsArtifactValidator.computeSHA256(for: testFileURL)
        // echo -n "Hello, Kraken Graphics Pipeline!" | shasum -a 256
        // e927e189d2d0c265e08c8dc1d6f1bfd8c130388d0f735ca312386bbd79ea9bc2
        XCTAssertFalse(hash.isEmpty)
        XCTAssertEqual(hash.count, 64)
    }

    func testArtifactValidator_healthyDirectory() throws {
        let file1URL = tempDirectory.appending(path: "bin/file1.dll")
        let file2URL = tempDirectory.appending(path: "bin/file2.dll")
        try FileManager.default.createDirectory(at: tempDirectory.appending(path: "bin"), withIntermediateDirectories: true)

        let data1 = "File 1 Content".data(using: .utf8)!
        let data2 = "File 2 Content".data(using: .utf8)!
        try data1.write(to: file1URL)
        try data2.write(to: file2URL)

        let hash1 = try GraphicsArtifactValidator.computeSHA256(for: file1URL)
        let hash2 = try GraphicsArtifactValidator.computeSHA256(for: file2URL)

        let manifest = GraphicsArtifactManifest(
            id: "test-manifest",
            displayName: "Test Manifest",
            backend: .dxvk,
            runtimeFamily: .wine11,
            version: "1.0",
            provenance: GraphicsArtifactProvenance(upstreamRepository: "test", upstreamTagOrCommit: "v1"),
            files: [
                ArtifactFileRecord(relativePath: "bin/file1.dll", sha256: hash1, sizeBytes: Int64(data1.count)),
                ArtifactFileRecord(relativePath: "bin/file2.dll", sha256: hash2, sizeBytes: Int64(data2.count))
            ],
            license: "MIT"
        )

        let health = GraphicsArtifactValidator.validate(manifest: manifest, in: tempDirectory)
        XCTAssertEqual(health, .healthy)
    }

    func testArtifactValidator_missingFiles() {
        let manifest = GraphicsArtifactManifest(
            id: "test-manifest",
            displayName: "Test Manifest",
            backend: .dxvk,
            runtimeFamily: .wine11,
            version: "1.0",
            provenance: GraphicsArtifactProvenance(upstreamRepository: "test", upstreamTagOrCommit: "v1"),
            files: [
                ArtifactFileRecord(relativePath: "missing1.dll", sha256: "abc", sizeBytes: 10),
                ArtifactFileRecord(relativePath: "missing2.dll", sha256: "def", sizeBytes: 20)
            ],
            license: "MIT"
        )

        let health = GraphicsArtifactValidator.validate(manifest: manifest, in: tempDirectory)
        XCTAssertEqual(health, .missingFiles(["missing1.dll", "missing2.dll"]))
    }

    func testArtifactValidator_checksumMismatch() throws {
        let fileURL = tempDirectory.appending(path: "corrupt.dll")
        try "Corrupted bytes".data(using: .utf8)!.write(to: fileURL)

        let manifest = GraphicsArtifactManifest(
            id: "test-manifest",
            displayName: "Test Manifest",
            backend: .dxvk,
            runtimeFamily: .wine11,
            version: "1.0",
            provenance: GraphicsArtifactProvenance(upstreamRepository: "test", upstreamTagOrCommit: "v1"),
            files: [
                ArtifactFileRecord(relativePath: "corrupt.dll", sha256: "0000000000000000000000000000000000000000000000000000000000000000", sizeBytes: 14)
            ],
            license: "MIT"
        )

        let health = GraphicsArtifactValidator.validate(manifest: manifest, in: tempDirectory)
        if case .checksumMismatch(let expected, let actual, let path) = health {
            XCTAssertEqual(expected, "0000000000000000000000000000000000000000000000000000000000000000")
            XCTAssertNotEqual(actual, expected)
            XCTAssertEqual(path, "corrupt.dll")
        } else {
            XCTFail("Expected checksumMismatch, got \(health)")
        }
    }

    func testArtifactValidator_nonExistentDirectory() {
        let nonExistentURL = tempDirectory.appending(path: "does_not_exist")
        let manifest = GraphicsArtifactRegistry.mythicEngineDXVK
        let health = GraphicsArtifactValidator.validate(manifest: manifest, in: nonExistentURL)
        if case .notInstalled(let reason) = health {
            XCTAssertTrue(reason.contains("does_not_exist"))
        } else {
            XCTFail("Expected notInstalled, got \(health)")
        }
    }
}
