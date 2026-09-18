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
                    Kraken only ships DXVK for \(Runtime.mythicEngine.name). \
                    This Windows environment belongs to \(Runtime.displayName(for: runtimeID)).
                    """)
            }
        }

        /// Replaces the Engine’s DirectX DLLs in the specified Wine container with their DXVK equivalents.
        static func install(toContainerAtURL containerURL: URL) async throws {
            /*
             The DLLs copied below come out of `Engine.directory/DXVK`, so this
             is an Engine 2-only operation. Enforce that here rather than
             relying on UI gating — otherwise a Wine 11 prefix would have its
             d3d DLLs deleted and replaced with Engine 2's.
             */
            let container = try Wine.getContainerObject(at: containerURL)
            guard container.runtimeID == .mythicEngine else {
                throw UnsupportedRuntimeError(runtimeID: container.runtimeID)
            }

            try Wine.killServer(at: containerURL, runtimeID: .mythicEngine)

            // remove existing d3d dlls
            // x64
            try FileManager.default.removeItemIfExists(at: containerURL.appending(path: "drive_c/windows/system32/d3d10core.dll"))
            try FileManager.default.removeItemIfExists(at: containerURL.appending(path: "drive_c/windows/system32/d3d11.dll"))

            // x32
            try FileManager.default.removeItemIfExists(at: containerURL.appending(path: "drive_c/windows/syswow64/d3d10core.dll"))
            try FileManager.default.removeItemIfExists(at: containerURL.appending(path: "drive_c/windows/syswow64/d3d11.dll"))

            // copy d3d dlls from dxvk
            // x64
            try FileManager.default.forceCopyItem(
                at: Engine.directory.appending(path: "DXVK/x64/d3d10core.dll"),
                to: containerURL.appending(path: "drive_c/windows/system32")
            )
            try FileManager.default.forceCopyItem(
                at: Engine.directory.appending(path: "DXVK/x64/d3d11.dll"),
                to: containerURL.appending(path: "drive_c/windows/system32")
            )

            // x32
            try FileManager.default.forceCopyItem(
                at: Engine.directory.appending(path: "DXVK/x32/d3d10core.dll"),
                to: containerURL.appending(path: "drive_c/windows/syswow64")
            )
            try FileManager.default.forceCopyItem(
                at: Engine.directory.appending(path: "DXVK/x32/d3d11.dll"),
                to: containerURL.appending(path: "drive_c/windows/syswow64")
            )
        }

        // to remove DXVK, you must run wineboot in update mode
    }
}
