//
//  HardwareCapabilities.swift
//  Kraken
//
// Copyright © 2026 Kraken contributors
//

import Foundation

/// Hardware capabilities abstraction for system querying and unit testing.
public protocol HardwareCapabilitiesProtocol: Sendable {
    /// Total physical unified system memory in bytes.
    var totalPhysicalMemory: UInt64 { get }
    /// Number of logical processors.
    var processorCount: Int { get }
    /// Whether the current architecture is Apple Silicon (arm64).
    var isAppleSilicon: Bool { get }
}

/// Concrete production implementation backed by Darwin/Foundation.
public struct SystemHardwareCapabilities: HardwareCapabilitiesProtocol {
    public init() {}

    public var totalPhysicalMemory: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    public var processorCount: Int {
        ProcessInfo.processInfo.processorCount
    }

    public var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
}

/// Mock implementation for deterministic unit testing.
public struct MockHardwareCapabilities: HardwareCapabilitiesProtocol {
    public var totalPhysicalMemory: UInt64
    public var processorCount: Int
    public var isAppleSilicon: Bool

    public init(
        totalPhysicalMemory: UInt64 = 16 * 1024 * 1024 * 1024,
        processorCount: Int = 8,
        isAppleSilicon: Bool = true
    ) {
        self.totalPhysicalMemory = totalPhysicalMemory
        self.processorCount = processorCount
        self.isAppleSilicon = isAppleSilicon
    }

    /// Convenience factory for configuring mock memory by gigabytes.
    public static func memoryGB(_ gigabytes: Double) -> MockHardwareCapabilities {
        let bytes = UInt64(gigabytes * 1024.0 * 1024.0 * 1024.0)
        return MockHardwareCapabilities(totalPhysicalMemory: bytes)
    }
}
