//
//  GraphicsArtifact.swift
//  Kraken
//
// Copyright © 2026 Kraken contributors
//

import Foundation
import CryptoKit

/// Represents an individual file within a graphics artifact distribution.
struct ArtifactFileRecord: Codable, Equatable, Hashable, Sendable {
    let relativePath: String
    let sha256: String
    let sizeBytes: Int64

    init(relativePath: String, sha256: String, sizeBytes: Int64) {
        self.relativePath = relativePath
        self.sha256 = sha256.lowercased()
        self.sizeBytes = sizeBytes
    }
}

/// Upstream source provenance and build-level metadata for a graphics artifact.
struct GraphicsArtifactProvenance: Codable, Equatable, Hashable, Sendable {
    let upstreamRepository: String
    let upstreamTagOrCommit: String
    let patchSet: [String]
    let buildToolchain: String

    init(
        upstreamRepository: String,
        upstreamTagOrCommit: String,
        patchSet: [String] = [],
        buildToolchain: String = "unknown"
    ) {
        self.upstreamRepository = upstreamRepository
        self.upstreamTagOrCommit = upstreamTagOrCommit
        self.patchSet = patchSet
        self.buildToolchain = buildToolchain
    }
}

/// Immutable manifest defining ownership, compatibility, and checksums for a graphics artifact.
struct GraphicsArtifactManifest: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let displayName: String
    let backend: GraphicsBackend
    let runtimeFamily: RuntimeFamily
    let version: String
    let provenance: GraphicsArtifactProvenance
    let files: [ArtifactFileRecord]
    let license: String

    init(
        id: String,
        displayName: String,
        backend: GraphicsBackend,
        runtimeFamily: RuntimeFamily,
        version: String,
        provenance: GraphicsArtifactProvenance,
        files: [ArtifactFileRecord],
        license: String
    ) {
        self.id = id
        self.displayName = displayName
        self.backend = backend
        self.runtimeFamily = runtimeFamily
        self.version = version
        self.provenance = provenance
        self.files = files
        self.license = license
    }
}

/// Health and integrity evaluation result for an artifact on disk.
enum GraphicsArtifactHealth: Equatable, Sendable {
    case healthy
    case missingFiles([String])
    case checksumMismatch(expected: String, actual: String, relativePath: String)
    case unsupportedRuntime(RuntimeFamily)
    case notInstalled(reason: String)
    case readError(String)
}

/// Validates graphics artifacts on disk against their manifest.
struct GraphicsArtifactValidator: Sendable {
    static func computeSHA256(for fileURL: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = fileHandle.readData(ofLength: 64 * 1024)
            if data.isEmpty {
                return false
            }
            hasher.update(data: data)
            return true
        }) {}
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func validate(
        manifest: GraphicsArtifactManifest,
        in baseDirectory: URL,
        fileManager: FileManager = .default
    ) -> GraphicsArtifactHealth {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: baseDirectory.path, isDirectory: &isDir), isDir.boolValue else {
            return .notInstalled(reason: "Directory does not exist: \(baseDirectory.path)")
        }

        var missing: [String] = []
        for fileRecord in manifest.files {
            let fileURL = baseDirectory.appending(path: fileRecord.relativePath)
            if !fileManager.fileExists(atPath: fileURL.path) {
                missing.append(fileRecord.relativePath)
            }
        }

        if !missing.isEmpty {
            return .missingFiles(missing)
        }

        for fileRecord in manifest.files {
            let fileURL = baseDirectory.appending(path: fileRecord.relativePath)
            do {
                let actualHash = try computeSHA256(for: fileURL)
                if actualHash.lowercased() != fileRecord.sha256.lowercased() {
                    return .checksumMismatch(
                        expected: fileRecord.sha256.lowercased(),
                        actual: actualHash.lowercased(),
                        relativePath: fileRecord.relativePath
                    )
                }
            } catch {
                return .readError("Failed reading file \(fileRecord.relativePath): \(error.localizedDescription)")
            }
        }

        return .healthy
    }
}

/// Central registry of known graphics artifacts, manifests, and integrity probes.
struct GraphicsArtifactRegistry: Sendable {
    static let shared = GraphicsArtifactRegistry()

    private let manifests: [String: GraphicsArtifactManifest]

    // MARK: - Built-in Artifact Manifests

    /// Pristine Mythic Engine baseline DXVK 1.10.3 (Engine 2).
    static let mythicEngineDXVK = GraphicsArtifactManifest(
        id: "mythic-engine-dxvk-1.10.3",
        displayName: "DXVK 1.10.3 (Engine Baseline)",
        backend: .dxvk,
        runtimeFamily: .mythicEngine,
        version: "1.10.3-20230507",
        provenance: GraphicsArtifactProvenance(
            upstreamRepository: "https://github.com/Gcenx/DXVK-macOS",
            upstreamTagOrCommit: "v1.10.3-20230507",
            patchSet: [],
            buildToolchain: "x86_64-w64-mingw32-gcc / meson"
        ),
        files: [
            ArtifactFileRecord(
                relativePath: "x64/d3d11.dll",
                sha256: "0ff0b0835dde29556bd01dfce7b1ae348d7f229cb1e1a37cc71ea1a028beeca4",
                sizeBytes: 2548810
            ),
            ArtifactFileRecord(
                relativePath: "x64/d3d10core.dll",
                sha256: "0fa08bba860c63e3abeeabfc96d0e7aa327411a975f8f23d2dc63594ef5f796e",
                sizeBytes: 1530949
            ),
            ArtifactFileRecord(
                relativePath: "x64/dxgi.dll",
                sha256: "e74f5c985fe98f38f1a096258ef35d62e03a64df7096837965c7383e3cfe153d",
                sizeBytes: 1475704
            ),
            ArtifactFileRecord(
                relativePath: "x64/d3d9.dll",
                sha256: "8060b9b70d1b36f6952af83a3ebdab3395c8045fec94e09919b7a967f3bccb68",
                sizeBytes: 2289659
            )
        ],
        license: "Zlib"
    )

    /// Patched Wine 11 DXVK 1.10.3 with D3D11 input-signature signedness reconciliation.
    static let wine11DXVKPatched = GraphicsArtifactManifest(
        id: "wine11-dxvk-1.10.3-signedness-reconciled",
        displayName: "DXVK 1.10.3 (Signedness Reconciled)",
        backend: .dxvk,
        runtimeFamily: .wine11,
        version: "1.10.3-20230507-kraken1",
        provenance: GraphicsArtifactProvenance(
            upstreamRepository: "https://github.com/Gcenx/DXVK-macOS",
            upstreamTagOrCommit: "v1.10.3-20230507",
            patchSet: ["dxvk-d3d11-input-layout-signedness-reconciliation"],
            buildToolchain: "x86_64-w64-mingw32-gcc / meson"
        ),
        files: [
            ArtifactFileRecord(
                relativePath: "x64/d3d11.dll",
                sha256: "489f5d6574c667c8282dd132cd128a45aa5d878d9402dee205c5197eac277cff",
                sizeBytes: 2548810
            ),
            ArtifactFileRecord(
                relativePath: "x64/d3d10core.dll",
                sha256: "0fa08bba860c63e3abeeabfc96d0e7aa327411a975f8f23d2dc63594ef5f796e",
                sizeBytes: 1530949
            ),
            ArtifactFileRecord(
                relativePath: "x64/dxgi.dll",
                sha256: "e74f5c985fe98f38f1a096258ef35d62e03a64df7096837965c7383e3cfe153d",
                sizeBytes: 1475704
            ),
            ArtifactFileRecord(
                relativePath: "x64/d3d9.dll",
                sha256: "8060b9b70d1b36f6952af83a3ebdab3395c8045fec94e09919b7a967f3bccb68",
                sizeBytes: 2289659
            )
        ],
        license: "Zlib"
    )

    /// Apple D3DMetal for GPTK 4 / Wine 11.
    static let gptkD3DMetal = GraphicsArtifactManifest(
        id: "gptk-d3dmetal-4.0",
        displayName: "D3DMetal 4.0",
        backend: .d3dmetal,
        runtimeFamily: .gptk,
        version: "4.0",
        provenance: GraphicsArtifactProvenance(
            upstreamRepository: "Apple Game Porting Toolkit",
            upstreamTagOrCommit: "4.0",
            patchSet: [],
            buildToolchain: "Apple Clang / Metal Toolchain"
        ),
        files: [
            ArtifactFileRecord(
                relativePath: "x64/d3d11.dll",
                sha256: "d3dmetal-d3d11-placeholder",
                sizeBytes: 0
            ),
            ArtifactFileRecord(
                relativePath: "x64/d3d12.dll",
                sha256: "d3dmetal-d3d12-placeholder",
                sizeBytes: 0
            ),
            ArtifactFileRecord(
                relativePath: "x64/dxgi.dll",
                sha256: "d3dmetal-dxgi-placeholder",
                sizeBytes: 0
            )
        ],
        license: "Apple Proprietary"
    )

    /// DXMT for Wine 11.
    static let wine11DXMT = GraphicsArtifactManifest(
        id: "wine11-dxmt-0.60",
        displayName: "DXMT 0.60",
        backend: .dxmt,
        runtimeFamily: .wine11,
        version: "0.60",
        provenance: GraphicsArtifactProvenance(
            upstreamRepository: "https://github.com/3Shain/dxmt",
            upstreamTagOrCommit: "0.60",
            patchSet: [],
            buildToolchain: "Metal / MinGW"
        ),
        files: [
            ArtifactFileRecord(
                relativePath: "x64/d3d11.dll",
                sha256: "dxmt-d3d11-placeholder",
                sizeBytes: 0
            ),
            ArtifactFileRecord(
                relativePath: "x64/dxgi.dll",
                sha256: "dxmt-dxgi-placeholder",
                sizeBytes: 0
            )
        ],
        license: "LGPL-2.1"
    )

    init(manifests: [GraphicsArtifactManifest] = [
        mythicEngineDXVK,
        wine11DXVKPatched,
        gptkD3DMetal,
        wine11DXMT
    ]) {
        var map: [String: GraphicsArtifactManifest] = [:]
        for manifest in manifests {
            map[manifest.id] = manifest
        }
        self.manifests = map
    }

    func manifest(for id: String) -> GraphicsArtifactManifest? {
        manifests[id]
    }

    func manifest(for backend: GraphicsBackend, runtimeFamily: RuntimeFamily) -> GraphicsArtifactManifest? {
        manifests.values.first { $0.backend == backend && $0.runtimeFamily == runtimeFamily }
    }

    var allManifests: [GraphicsArtifactManifest] {
        Array(manifests.values)
    }

    func validate(
        manifest: GraphicsArtifactManifest,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> GraphicsArtifactHealth {
        GraphicsArtifactValidator.validate(manifest: manifest, in: directory, fileManager: fileManager)
    }
}
