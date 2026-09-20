//
//  GPTKInstaller.swift
//  Kraken
//
// Copyright © 2026 Kraken contributors
//

import Foundation
import OSLog

/// Manages installation and configuration of Apple's Game Porting Toolkit (GPTK) payload
/// into Wine runtimes (such as Wine 11) and container synchronization.
enum GPTKInstaller {
    private static let logger = Logger(subsystem: "com.yerlsd.kraken", category: "GPTKInstaller")

    enum GPTKError: LocalizedError {
        case payloadNotFound
        case mountFailed(String)
        case installationFailed(String)
        case runtimeNotFound

        var errorDescription: String? {
            switch self {
            case .payloadNotFound:
                return String(localized: "Game Porting Toolkit 4.0 DMG was not found in ~/Documents or mounted volumes.")
            case .mountFailed(let detail):
                return String(localized: "Failed to mount Game Porting Toolkit DMG: \(detail)")
            case .installationFailed(let detail):
                return String(localized: "Failed to install Game Porting Toolkit payload: \(detail)")
            case .runtimeNotFound:
                return String(localized: "Target Wine runtime bundle was not found.")
            }
        }
    }

    /// Default candidates where the evaluation environment DMG may be located.
    static var defaultDMGPaths: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appending(path: "Documents/Game Porting Toolkit 4.0/Evaluation environment for Windows games 4.0 beta 2.dmg"),
            home.appending(path: "Documents/Game Porting Toolkit 4.0/Evaluation environment for Windows games 4.0.dmg"),
            home.appending(path: "Downloads/Evaluation environment for Windows games 4.0 beta 2.dmg"),
            home.appending(path: "Downloads/Evaluation environment for Windows games 4.0.dmg"),
        ]
    }

    /// Default mount point for the DMG.
    static let mountedVolumeURL = URL(fileURLWithPath: "/Volumes/Evaluation environment for Windows games 4.0 beta 2")

    /// Check whether GPTK is currently installed in the given runtime.
    static func isInstalled(for runtimeID: RuntimeID = .gptk) -> Bool {
        guard runtimeID == .gptk else { return false }
        let runtime = Engine.wineRuntime(for: runtimeID)

        let frameworkPath = runtime.externalLibrariesURL.appending(
            path: "D3DMetal.framework"
        )
        let bridgePath = runtime.unixLibrariesURL.appending(
            path: "d3d11.so"
        )
        let pePath = runtime.windowsLibrariesURL.appending(
            path: "d3d11.dll"
        )

        return FileManager.default.fileExists(atPath: frameworkPath.path) &&
               FileManager.default.fileExists(atPath: bridgePath.path) &&
               FileManager.default.fileExists(atPath: pePath.path)
    }

    /// Install the GPTK payload into the runtime bundle or directory.
    @discardableResult
    static func install(for runtimeID: RuntimeID = .gptk, dmgURL: URL? = nil) throws -> Bool {
        guard Engine.isRuntimeInstalled(runtimeID) else {
            throw GPTKError.runtimeNotFound
        }
        let runtime = Engine.wineRuntime(for: runtimeID)

        let fm = FileManager.default
        var sourceVolumeURL: URL?
        var didMount = false

        // Check if already mounted
        if fm.fileExists(atPath: mountedVolumeURL.path) {
            sourceVolumeURL = mountedVolumeURL
        } else {
            // Find DMG to mount
            let candidates = dmgURL != nil ? [dmgURL!] : defaultDMGPaths
            guard let foundDMG = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
                throw GPTKError.payloadNotFound
            }

            // Mount DMG
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["attach", "-nobrowse", "-readonly", foundDMG.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                throw GPTKError.mountFailed(output)
            }

            didMount = true
            sourceVolumeURL = mountedVolumeURL
        }

        defer {
            if didMount, let sourceVolumeURL = sourceVolumeURL {
                let unmountProcess = Process()
                unmountProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                unmountProcess.arguments = ["detach", sourceVolumeURL.path]
                try? unmountProcess.run()
                unmountProcess.waitUntilExit()
            }
        }

        guard let source = sourceVolumeURL else {
            throw GPTKError.payloadNotFound
        }

        let redistLib = source.appending(path: "redist/lib")
        guard fm.fileExists(atPath: redistLib.path) else {
            throw GPTKError.installationFailed("redist/lib not found in DMG")
        }

        let targetLib = runtime.wineBundleURL?.appending(path: "Contents/Resources/wine/lib") ?? runtime.rootDirectory.appending(path: "wine/lib")
        try fm.createDirectory(at: targetLib, withIntermediateDirectories: true)

        // Use ditto to copy external/ and wine/
        let dittoProcess = Process()
        dittoProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        dittoProcess.arguments = [redistLib.path, targetLib.path]
        try dittoProcess.run()
        dittoProcess.waitUntilExit()

        guard dittoProcess.terminationStatus == 0 else {
            throw GPTKError.installationFailed("ditto failed with status \(dittoProcess.terminationStatus)")
        }

        logger.info("Successfully deployed GPTK 4 payload to \(targetLib.path)")
        return true
    }

    /// The list of Direct3D PE DLLs that belong to GPTK.
    static let gptkCompanionDLLs = [
        "d3d10.dll",
        "d3d10core.dll",
        "d3d11.dll",
        "d3d12.dll",
        "dxgi.dll",
        "nvapi64.dll",
        "nvngx.dll"
    ]

    /// Synchronizes GPTK Direct3D PE companion DLLs into a container's system32 directory.
    static func syncContainerDLLs(containerURL: URL, for runtimeID: RuntimeID = .gptk) throws {
        let runtime = Engine.wineRuntime(for: runtimeID)
        let fm = FileManager.default
        let sourceWindowsLib = runtime.windowsLibrariesURL
        let targetSystem32 = containerURL.appending(
            path: "drive_c/windows/system32"
        )

        guard fm.fileExists(atPath: targetSystem32.path) else { return }

        for dllName in gptkCompanionDLLs {
            let src = sourceWindowsLib.appending(path: dllName)
            let dst = targetSystem32.appending(path: dllName)

            guard fm.fileExists(atPath: src.path) else { continue }

            // If destination already exists with same size, skip
            if let srcAttrs = try? fm.attributesOfItem(atPath: src.path),
               let dstAttrs = try? fm.attributesOfItem(atPath: dst.path),
               let srcSize = srcAttrs[.size] as? NSNumber,
               let dstSize = dstAttrs[.size] as? NSNumber,
               srcSize == dstSize {
                continue
            }

            try? fm.removeItem(at: dst)
            try? fm.copyItem(at: src, to: dst)
            logger.debug("Synchronized \(dllName) to \(dst.path)")
        }
    }
}
