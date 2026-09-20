//
//  ReportedGPUMemory.swift
//  Kraken
//
// Copyright © 2026 Kraken contributors
//

import Foundation

/// User-configurable policy for GPU memory reported to Windows games.
///
/// This is a reporting mechanism, NOT physical memory reservation.
/// It instructs DXVK and DXGI what integer value to return in
/// `DXGI_ADAPTER_DESC.DedicatedVideoMemory` and `SharedSystemMemory`.
public enum ReportedGPUMemoryPolicy: Codable, Equatable, Hashable, Sendable {
    case automatic
    case manual(megabytes: Int)

    private enum CodingKeys: String, CodingKey {
        case mode
        case megabytes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decode(String.self, forKey: .mode)
        switch mode {
        case "manual":
            let mb = try container.decode(Int.self, forKey: .megabytes)
            self = .manual(megabytes: mb)
        default:
            self = .automatic
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .automatic:
            try container.encode("automatic", forKey: .mode)
        case .manual(let mb):
            try container.encode("manual", forKey: .mode)
            try container.encode(mb, forKey: .megabytes)
        }
    }
}

/// Resolves concrete VRAM megabytes to report to the game based on policy and hardware.
public struct ReportedGPUMemoryResolver: Sendable {
    public static let shared = ReportedGPUMemoryResolver()

    private let hardware: HardwareCapabilitiesProtocol

    public init(hardware: HardwareCapabilitiesProtocol = SystemHardwareCapabilities()) {
        self.hardware = hardware
    }

    /// Standard recommended presets for manual configuration.
    public enum Presets {
        public static let low = 1024       // 1 GB
        public static let medium = 2048    // 2 GB
        public static let high = 4095      // 4 GB (safe 4095 MB prevents 32-bit DWORD integer overflow)
        public static let ultra = 8192     // 8 GB
        public static let extreme = 16384  // 16 GB

        public static let all: [Int] = [low, medium, high, ultra, extreme]
    }

    /// Resolve megabytes for a given policy.
    public func resolveMegabytes(for policy: ReportedGPUMemoryPolicy) -> Int {
        switch policy {
        case .manual(let megabytes):
            // Clamp within sane boundaries: 512 MB to 65536 MB (64 GB)
            return min(max(512, megabytes), 65536)
        case .automatic:
            return automaticMegabytes()
        }
    }

    /// Automatic policy derives safe reported VRAM from unified memory.
    public func automaticMegabytes() -> Int {
        let totalBytes = hardware.totalPhysicalMemory
        let totalGB = Double(totalBytes) / (1024.0 * 1024.0 * 1024.0)

        if totalGB >= 30.0 {
            // >= 32 GB unified RAM -> report 8192 MB
            return Presets.ultra
        } else if totalGB >= 14.0 {
            // >= 16 GB unified RAM -> report 4095 MB (battle-tested safe value preventing DWORD overflow)
            return Presets.high
        } else if totalGB >= 7.0 {
            // >= 8 GB unified RAM -> report 2048 MB
            return Presets.medium
        } else {
            // < 8 GB unified RAM -> report 1024 MB
            return Presets.low
        }
    }
}

/// Generates and provisions DXVK configuration for container prefixes.
public enum DXVKConfigurationManager {
    /// Generates the standard dxvk.conf file content for a given reported memory value.
    public static func generateConfigContent(memoryMB: Int) -> String {
        """
        dxgi.nvapiHack = False
        dxgi.emulateUMA = False
        dxgi.maxDeviceMemory = \(memoryMB)
        dxgi.maxSharedMemory = \(memoryMB)
        d3d11.invariantPosition = True

        """
    }

    /// Writes dxvk.conf to drive_c/windows/dxvk.conf in the container.
    public static func writeConfiguration(toContainerAtURL containerURL: URL, memoryMB: Int) throws {
        let windowsDir = containerURL.appending(path: "drive_c/windows")
        if !FileManager.default.fileExists(atPath: windowsDir.path) {
            try FileManager.default.createDirectory(at: windowsDir, withIntermediateDirectories: true)
        }
        let confURL = windowsDir.appending(path: "dxvk.conf")
        let content = generateConfigContent(memoryMB: memoryMB)
        try content.write(to: confURL, atomically: true, encoding: .utf8)
    }
}
