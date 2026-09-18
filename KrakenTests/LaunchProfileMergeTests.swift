//
//  LaunchProfileMergeTests.swift
//  KrakenTests
//
// Copyright © 2026 Kraken contributors

import XCTest
@testable import Kraken

/// Tests for Epic/Legendary game merge behaviour.
///
/// These tests verify that storefront refreshes do not accidentally promote
/// effective runtime into stored runtime, and that launch arguments preserve
/// first-occurrence ordering.
@MainActor
final class LaunchProfileMergeTests: XCTestCase {

    // MARK: - Runtime Preservation

    func testMergePreservesDefaultRuntime() throws {
        // Given a game with explicit default runtime
        let current = createTestGame(
            defaultRuntime: .wine11,
            override: nil
        )

        let new = createTestGame(
            defaultRuntime: .mythicEngine,
            override: nil
        )

        // When merged
        try current.merge(with: new, requiring: .identicalIgnoredKeys)

        // Then current's default runtime is preserved
        XCTAssertEqual(current.launchProfile.defaultRuntimeID, .wine11)
    }

    func testMergePreservesRuntimeOverride() throws {
        // Given a game with manual runtime override
        let current = createTestGame(
            defaultRuntime: .mythicEngine,
            override: .wine11
        )

        let new = createTestGame(
            defaultRuntime: .mythicEngine,
            override: nil
        )

        // When merged
        try current.merge(with: new, requiring: .identicalIgnoredKeys)

        // Then override is preserved
        XCTAssertEqual(current.launchProfile.runtimeOverride, .wine11)
        XCTAssertEqual(current.launchProfile.defaultRuntimeID, .mythicEngine)
    }

    func testMergeDoesNotPromoteEffectiveRuntimeToStored() throws {
        // Given automatic mode uses default runtime
        let current = createTestGame(
            defaultRuntime: .mythicEngine,
            override: nil
        )

        XCTAssertEqual(current.launchProfile.effectiveRuntimeID, .mythicEngine)

        let new = createTestGame(
            defaultRuntime: .wine11,
            override: nil
        )

        // When merged (simulating Epic refresh)
        try current.merge(with: new, requiring: .identicalIgnoredKeys)

        // Then effective runtime does NOT become stored default
        XCTAssertEqual(current.launchProfile.defaultRuntimeID, .mythicEngine)
        XCTAssertNil(current.launchProfile.runtimeOverride)
    }

    func testManualOverrideNotPromotedToDefaultOnRefresh() throws {
        // Given manual Wine 11 override over Engine 2 default
        let current = createTestGame(
            defaultRuntime: .mythicEngine,
            override: .wine11
        )

        XCTAssertEqual(current.launchProfile.effectiveRuntimeID, .wine11)

        let new = createTestGame(
            defaultRuntime: .mythicEngine,
            override: nil
        )

        // When refreshed multiple times
        for _ in 0..<3 {
            try current.merge(with: new, requiring: .identicalIgnoredKeys)
        }

        // Then default remains Engine 2, override remains Wine 11
        XCTAssertEqual(current.launchProfile.defaultRuntimeID, .mythicEngine)
        XCTAssertEqual(current.launchProfile.runtimeOverride, .wine11)

        // And turning off override restores original default
        current.launchProfile.clearRuntimeOverride()
        XCTAssertEqual(current.launchProfile.effectiveRuntimeID, .mythicEngine)
    }

    // MARK: - Container Preservation

    func testMergePreservesCurrentContainer() throws {
        let currentContainer = URL(fileURLWithPath: "/tmp/container1")
        let newContainer = URL(fileURLWithPath: "/tmp/container2")

        let current = createTestGame(container: currentContainer)
        let new = createTestGame(container: newContainer)

        // When merged
        try current.merge(with: new, requiring: .identicalIgnoredKeys)

        // Then current's container is preserved
        XCTAssertEqual(current.launchProfile.container?.url, currentContainer)
    }

    func testMergeUsesNewContainerWhenCurrentIsAbsent() throws {
        let newContainer = URL(fileURLWithPath: "/tmp/container")

        let current = createTestGame(container: nil)
        let new = createTestGame(container: newContainer)

        // When merged
        try current.merge(with: new, requiring: .identicalIgnoredKeys)

        // Then new container is adopted
        XCTAssertEqual(current.launchProfile.container?.url, newContainer)
    }

    // MARK: - Launch Arguments

    func testLaunchArgumentsPreserveFirstOccurrenceOrder() throws {
        let current = ["--arg1", "--arg2"]
        let new = ["--arg2", "--arg3", "--arg1", "--arg4"]

        // When merged
        let merged = LaunchProfile.mergeLaunchArguments(current, new)

        // Then first occurrence order is preserved
        XCTAssertEqual(merged, ["--arg1", "--arg2", "--arg3", "--arg4"])
    }

    func testLaunchArgumentsDeduplication() throws {
        let current = ["--verbose", "--debug"]
        let new = ["--debug", "--verbose", "--trace"]

        // When merged
        let merged = LaunchProfile.mergeLaunchArguments(current, new)

        // Then duplicates removed, first occurrence kept
        XCTAssertEqual(merged, ["--verbose", "--debug", "--trace"])
    }

    func testEmptyLaunchArgumentArrays() throws {
        XCTAssertEqual(LaunchProfile.mergeLaunchArguments([], []), [])
        XCTAssertEqual(LaunchProfile.mergeLaunchArguments(["--arg"], []), ["--arg"])
        XCTAssertEqual(LaunchProfile.mergeLaunchArguments([], ["--arg"]), ["--arg"])
    }

    func testLaunchArgumentsMergeNotRandomized() throws {
        // This test would fail if Array(Set(...)) was used
        let current = ["a", "b", "c", "d", "e"]
        let new = ["e", "d", "c", "b", "a"]

        // Run multiple times to ensure deterministic order
        for _ in 0..<10 {
            let merged = LaunchProfile.mergeLaunchArguments(current, new)
            XCTAssertEqual(merged, ["a", "b", "c", "d", "e"])
        }
    }

    func testLaunchArgumentsPreservedThroughGameMerge() throws {
        let current = createTestGame()
        current.launchProfile.launchArguments = ["--current1", "--current2"]

        let new = createTestGame()
        new.launchProfile.launchArguments = ["--current2", "--new1"]

        // When game merged
        try current.merge(with: new, requiring: .identicalIgnoredKeys)

        // Then arguments merged correctly
        XCTAssertEqual(current.launchProfile.launchArguments, ["--current1", "--current2", "--new1"])
    }

    // MARK: - Merge Idempotence

    func testRepeatedRefreshIsIdempotent() throws {
        let original = createTestGame(
            defaultRuntime: .mythicEngine,
            override: .wine11
        )
        original.launchProfile.launchArguments = ["--original"]

        let refresh = createTestGame(
            defaultRuntime: .mythicEngine,
            override: nil
        )
        refresh.launchProfile.launchArguments = ["--refresh"]

        // Capture state after first merge
        try original.merge(with: refresh, requiring: .identicalIgnoredKeys)
        let afterFirst = original.launchProfile

        // Merge same refresh data again
        try original.merge(with: refresh, requiring: .identicalIgnoredKeys)
        let afterSecond = original.launchProfile

        // Then state is identical (no drift)
        XCTAssertEqual(afterFirst.defaultRuntimeID, afterSecond.defaultRuntimeID)
        XCTAssertEqual(afterFirst.runtimeOverride, afterSecond.runtimeOverride)
        XCTAssertEqual(afterFirst.launchArguments, afterSecond.launchArguments)
    }

    // MARK: - Helper

    private func createTestGame(
        defaultRuntime: RuntimeID = .mythicEngine,
        override: RuntimeID? = nil,
        container: URL? = nil
    ) -> LocalGame {
        let game = LocalGame(
            id: UUID().uuidString,
            title: "Test Game",
            installationState: .uninstalled
        )

        game.launchProfile = LaunchProfile(
            container: container.map(ContainerReference.init(url:)),
            defaultRuntimeID: defaultRuntime,
            runtimeOverride: override,
            launchArguments: []
        )

        return game
    }
}
