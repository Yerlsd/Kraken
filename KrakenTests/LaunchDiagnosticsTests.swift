//
//  LaunchDiagnosticsTests.swift
//  KrakenTests
//
// Copyright © 2026 Kraken contributors
//

import XCTest
@testable import Kraken

final class LaunchDiagnosticsTests: XCTestCase {

    // MARK: - 1. Launch Failure Stage & Serialization

    func testLaunchFailureStageCodableRoundTrip() throws {
        let stages: [LaunchFailureStage] = [
            .resolutionFailure,
            .runtimeUnavailable,
            .containerFailure,
            .artifactFailure,
            .environmentFailure,
            .storageValidationFailure,
            .storageMaterializationPending,
            .processCreationFailure,
            .processTerminationFailure,
            .unknown
        ]

        for stage in stages {
            let data = try JSONEncoder().encode(stage)
            let decoded = try JSONDecoder().decode(LaunchFailureStage.self, from: data)
            XCTAssertEqual(decoded, stage)
        }
    }

    // MARK: - 2. Session Diagnostics User Summaries

    func testSessionDiagnosticsSuccessfulSummary() {
        let diagnostics = SessionDiagnostics(
            sessionId: UUID(),
            gameId: "test-game",
            gameTitle: "Test Game",
            sourceProvider: .local,
            executablePath: "/path/to/game.exe",
            runtimeFamily: .wine11,
            runtimeVersion: "11.0",
            containerPath: "/path/to/container",
            graphicsBackend: .dxvk,
            graphicsArtifactVersion: "1.10.3-patched",
            reportedGPUMemoryMB: 4096,
            processID: 12345
        )

        XCTAssertTrue(diagnostics.userSummary.contains("12345"))
        XCTAssertNil(diagnostics.failureStage)
        XCTAssertNil(diagnostics.failureMessage)
    }

    func testSessionDiagnosticsFailureSummary() {
        let diagnostics = SessionDiagnostics(
            sessionId: UUID(),
            gameId: "test-game",
            gameTitle: "Test Game",
            sourceProvider: .epic,
            executablePath: "/path/to/game.exe",
            runtimeFamily: .gptk,
            runtimeVersion: "4.0",
            containerPath: "/path/to/container",
            graphicsBackend: .d3dmetal,
            graphicsArtifactVersion: nil,
            reportedGPUMemoryMB: 8192,
            failureStage: .runtimeUnavailable,
            failureMessage: "GPTK 4 runtime package is not installed on disk."
        )

        XCTAssertEqual(diagnostics.failureStage, .runtimeUnavailable)
        XCTAssertTrue(diagnostics.userSummary.contains("runtimeUnavailable"))
        XCTAssertTrue(diagnostics.userSummary.contains("GPTK 4 runtime package is not installed"))
    }

    // MARK: - 3. Process Termination Info

    func testProcessTerminationReasonSerialization() throws {
        let reasons: [ProcessTerminationReason] = [
            .normalExit,
            .uncaughtSignal,
            .userCancelled,
            .startupFailed,
            .unknown
        ]

        for reason in reasons {
            let info = ProcessTerminationInfo(exitCode: 0, reason: reason)
            let data = try JSONEncoder().encode(info)
            let decoded = try JSONDecoder().decode(ProcessTerminationInfo.self, from: data)
            XCTAssertEqual(decoded.reason, reason)
        }
    }
}
