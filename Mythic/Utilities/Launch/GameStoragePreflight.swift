//
//  GameStoragePreflight.swift
//  Kraken
//
// Copyright © 2026 Kraken contributors
//

import Foundation
import OSLog

/// Represents the readiness of a game's on-disk assets before launch.
public enum StorageReadiness: Codable, Equatable, Hashable, Sendable {
    /// All assets are stored locally on disk; no cloud delays expected.
    case ready

    /// Files have been offloaded by macOS iCloud Drive (UF_DATALESS) and must be materialized.
    case materializationRequired(datalessCount: Int, totalBytes: Int64)

    /// The game is stored in an iCloud-managed directory (e.g. ~/Documents or ~/Desktop)
    /// where macOS may aggressively evict assets under low disk space conditions.
    case cloudLocationWarning(path: String)
}

/// Detailed results of a game storage pre-flight analysis.
public struct StoragePreflightResult: Codable, Equatable, Hashable, Sendable {
    public let isUbiquitous: Bool
    public let isInCloudManagedDirectory: Bool
    public let datalessFileCount: Int
    public let datalessBytes: Int64
    public let totalFilesChecked: Int
    public let readiness: StorageReadiness

    public init(
        isUbiquitous: Bool,
        isInCloudManagedDirectory: Bool,
        datalessFileCount: Int,
        datalessBytes: Int64,
        totalFilesChecked: Int,
        readiness: StorageReadiness
    ) {
        self.isUbiquitous = isUbiquitous
        self.isInCloudManagedDirectory = isInCloudManagedDirectory
        self.datalessFileCount = datalessFileCount
        self.datalessBytes = datalessBytes
        self.totalFilesChecked = totalFilesChecked
        self.readiness = readiness
    }

    /// User-facing diagnostic summary suitable for logs and UI warnings.
    public var diagnosticSummary: String {
        switch readiness {
        case .ready:
            return "Storage ready: \(totalFilesChecked) files checked, all local on disk."
        case let .materializationRequired(count, bytes):
            let mb = Double(bytes) / (1024.0 * 1024.0)
            return "Performance Warning: \(count) files (\(String(format: "%.1f", mb)) MB) are offloaded to iCloud (dataless). Materialization required to avoid severe in-game loading stalls."
        case let .cloudLocationWarning(path):
            return "Location Notice: Game is located in iCloud-synced folder (\(path)). macOS may evict assets to save disk space. Moving to ~/Games or /Users/Shared is recommended."
        }
    }
}

/// Pre-flight validator ensuring games are not starved by APFS / iCloud Drive dataless file faults.
public enum GameStoragePreflight: Sendable {
    private static let logger = Logger(subsystem: "com.yerlsd.kraken", category: "GameStoragePreflight")

    /// Bitflag on macOS representing UF_DATALESS in `stat.st_flags`.
    public static let ufDatalessFlag: UInt32 = 0x40000000

    /// Inspects the given game root directory or executable URL for ubiquitous and dataless status.
    public static func inspect(
        at url: URL,
        maxFilesToScan: Int = 50_000
    ) -> StoragePreflightResult {
        var isDir: ObjCBool = false
        let pathString = url.path(percentEncoded: false)
        let exists = FileManager.default.fileExists(atPath: pathString, isDirectory: &isDir)
        let directoryURL: URL
        if exists && isDir.boolValue {
            directoryURL = url
        } else if url.hasDirectoryPath {
            directoryURL = url
        } else {
            directoryURL = url.deletingLastPathComponent()
        }
        let path = directoryURL.path(percentEncoded: false)

        let isUbiquitous = FileManager.default.isUbiquitousItem(at: directoryURL)
        let inCloudDir = isPathInCloudManagedDirectory(path)

        var datalessCount = 0
        var datalessBytes: Int64 = 0
        var totalCount = 0

        let fm = FileManager.default
        if let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                totalCount += 1
                if totalCount > maxFilesToScan {
                    break
                }

                var st = stat()
                if lstat(fileURL.path(percentEncoded: false), &st) == 0 {
                    if (st.st_flags & ufDatalessFlag) != 0 {
                        datalessCount += 1
                        datalessBytes += Int64(st.st_size)
                    }
                }
            }
        }

        let readiness: StorageReadiness
        if datalessCount > 0 {
            readiness = .materializationRequired(datalessCount: datalessCount, totalBytes: datalessBytes)
        } else if inCloudDir || isUbiquitous {
            readiness = .cloudLocationWarning(path: path)
        } else {
            readiness = .ready
        }

        let result = StoragePreflightResult(
            isUbiquitous: isUbiquitous,
            isInCloudManagedDirectory: inCloudDir,
            datalessFileCount: datalessCount,
            datalessBytes: datalessBytes,
            totalFilesChecked: totalCount,
            readiness: readiness
        )

        if readiness != .ready {
            logger.warning("\(result.diagnosticSummary, privacy: .public)")
        } else {
            logger.info("\(result.diagnosticSummary, privacy: .public)")
        }

        return result
    }

    /// Triggers asynchronous background download for any dataless stubs in the target directory.
    @discardableResult
    public static func materializeDatalessFiles(
        in directoryURL: URL,
        maxItems: Int = 50_000
    ) -> Int {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let pathString = directoryURL.path(percentEncoded: false)
        let exists = fm.fileExists(atPath: pathString, isDirectory: &isDir)
        let dir: URL
        if exists && isDir.boolValue {
            dir = directoryURL
        } else if directoryURL.hasDirectoryPath {
            dir = directoryURL
        } else {
            dir = directoryURL.deletingLastPathComponent()
        }
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: nil, options: []) else {
            return 0
        }

        var triggered = 0
        for case let fileURL as URL in enumerator {
            var st = stat()
            if lstat(fileURL.path(percentEncoded: false), &st) == 0 {
                if (st.st_flags & ufDatalessFlag) != 0 {
                    try? fm.startDownloadingUbiquitousItem(at: fileURL)
                    triggered += 1
                    if triggered >= maxItems {
                        break
                    }
                }
            }
        }

        if triggered > 0 {
            logger.info("Triggered materialization for \(triggered, privacy: .public) dataless files in \(dir.path(percentEncoded: false), privacy: .public)")
        }
        return triggered
    }

    /// Determines if a path is located inside iCloud Drive's default synchronized root directories.
    public static func isPathInCloudManagedDirectory(_ path: String) -> Bool {
        let home = NSHomeDirectory()
        let documentsPath = (home as NSString).appendingPathComponent("Documents")
        let desktopPath = (home as NSString).appendingPathComponent("Desktop")

        if path.hasPrefix(documentsPath) || path.hasPrefix(desktopPath) {
            return true
        }

        if path.contains("Library/Mobile Documents") {
            return true
        }

        return false
    }
}
