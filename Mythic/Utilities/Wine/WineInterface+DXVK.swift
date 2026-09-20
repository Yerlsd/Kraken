//
//  WineInterface+DXVK.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 11/11/2025.
//

// Copyright © 2023-2025 vapidinfinity

import Foundation

extension Wine {
    final class DXVK {
        /// Thrown when DXVK installation is attempted on a non-Engine 2 prefix.
        struct UnsupportedRuntimeError: LocalizedError {
            let runtimeID: RuntimeID

            var errorDescription: String? {
                String(localized: """
                    Kraken only ships DXVK for \(Runtime.mythicEngine.name) and \(Runtime.wine11.name). \
                    This Windows environment belongs to \(Runtime.displayName(for: runtimeID)).
                    """)
            }
        }

        /// Replaces the Engine’s DirectX DLLs in the specified Wine container with their DXVK equivalents.
        static func install(toContainerAtURL containerURL: URL) async throws {
            let container = try Wine.getContainerObject(at: containerURL)
            guard container.runtimeID == .mythicEngine || container.runtimeID == .wine11 else {
                throw UnsupportedRuntimeError(runtimeID: container.runtimeID)
            }

            try Wine.killServer(at: containerURL, runtimeID: container.runtimeID)

            // remove existing d3d dlls
            // x64
            try FileManager.default.removeItemIfExists(at: containerURL.appending(path: "drive_c/windows/system32/d3d10core.dll"))
            try FileManager.default.removeItemIfExists(at: containerURL.appending(path: "drive_c/windows/system32/d3d11.dll"))
            try FileManager.default.removeItemIfExists(at: containerURL.appending(path: "drive_c/windows/system32/dxgi.dll"))

            // x32
            try FileManager.default.removeItemIfExists(at: containerURL.appending(path: "drive_c/windows/syswow64/d3d10core.dll"))
            try FileManager.default.removeItemIfExists(at: containerURL.appending(path: "drive_c/windows/syswow64/d3d11.dll"))
            try FileManager.default.removeItemIfExists(at: containerURL.appending(path: "drive_c/windows/syswow64/dxgi.dll"))

            let dxvkBaseURL: URL
            switch container.runtimeID {
            case .mythicEngine:
                dxvkBaseURL = Engine.directory.appending(path: "DXVK")
            case .wine11:
                dxvkBaseURL = Engine.runtimeDirectory.appending(path: "wine11/DXVK")
            default:
                throw UnsupportedRuntimeError(runtimeID: container.runtimeID)
            }

            // copy d3d dlls from dxvk
            // x64
            try FileManager.default.forceCopyItem(
                at: dxvkBaseURL.appending(path: "x64/d3d10core.dll"),
                to: containerURL.appending(path: "drive_c/windows/system32")
            )
            try FileManager.default.forceCopyItem(
                at: dxvkBaseURL.appending(path: "x64/d3d11.dll"),
                to: containerURL.appending(path: "drive_c/windows/system32")
            )
            try FileManager.default.forceCopyItem(
                at: dxvkBaseURL.appending(path: "x64/dxgi.dll"),
                to: containerURL.appending(path: "drive_c/windows/system32")
            )

            // x32
            try FileManager.default.forceCopyItem(
                at: dxvkBaseURL.appending(path: "x32/d3d10core.dll"),
                to: containerURL.appending(path: "drive_c/windows/syswow64")
            )
            try FileManager.default.forceCopyItem(
                at: dxvkBaseURL.appending(path: "x32/d3d11.dll"),
                to: containerURL.appending(path: "drive_c/windows/syswow64")
            )
            try FileManager.default.forceCopyItem(
                at: dxvkBaseURL.appending(path: "x32/dxgi.dll"),
                to: containerURL.appending(path: "drive_c/windows/syswow64")
            )
        }

        // to remove DXVK, you must run wineboot in update mode
    }
}
