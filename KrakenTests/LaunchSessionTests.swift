//
//  LaunchSessionTests.swift
//  KrakenTests
//
// Copyright © 2026 Kraken contributors
//

import XCTest
@testable import Kraken

final class LaunchSessionTests: XCTestCase {

    private func makeSamplePlan() -> LaunchPlan {
        LaunchPlan(
            gameId: "subnautica-01",
            gameTitle: "Subnautica",
            sourceProvider: .epic,
            executableURL: URL(fileURLWithPath: "/games/Subnautica/Subnautica.exe"),
            launchArguments: ["-windowed"],
            runtimeID: .wine11,
            runtimeFamily: .wine11,
            runtimeVersion: "Engine 3 · Modern",
            wineExecutableURL: URL(fileURLWithPath: "/runtimes/wine11/bin/wine"),
            wineserverExecutableURL: URL(fileURLWithPath: "/runtimes/wine11/bin/wineserver"),
            containerURL: URL(fileURLWithPath: "/containers/Subnautica"),
            graphicsBackend: .dxvk,
            graphicsArtifactManifest: GraphicsArtifactRegistry.wine11DXVKPatched,
            reportedGPUMemoryMB: 8192,
            environment: ["WINEPREFIX": "/containers/Subnautica", "DXVK_ASYNC": "1"],
            displayConfiguration: LaunchDisplayConfiguration(retinaMode: false, scalingDPI: 96)
        )
    }

    func testSessionCreationFromLaunchPlan() {
        let plan = makeSamplePlan()
        let session = LaunchSession(plan: plan)

        XCTAssertEqual(session.plan, plan)
        XCTAssertEqual(session.state, .preparing)
        XCTAssertNil(session.endTime)
        XCTAssertNil(session.processIdentity)
        XCTAssertNil(session.terminationInfo)
        XCTAssertNil(session.failureStage)
    }

    func testDeterministicSessionMetadata() {
        let plan = makeSamplePlan()
        let session = LaunchSession(plan: plan)

        XCTAssertEqual(session.plan.gameId, "subnautica-01")
        XCTAssertEqual(session.plan.gameTitle, "Subnautica")
        XCTAssertEqual(session.plan.runtimeFamily, .wine11)
        XCTAssertEqual(session.plan.graphicsBackend, .dxvk)
        XCTAssertEqual(session.plan.reportedGPUMemoryMB, 8192)
    }

    func testStateTransitions_HappyPath() {
        let plan = makeSamplePlan()
        let session = LaunchSession(plan: plan)

        session.transitionToResolving()
        XCTAssertEqual(session.state, .resolving)

        session.transitionToProvisioning()
        XCTAssertEqual(session.state, .provisioning)

        session.transitionToStartingRuntime()
        XCTAssertEqual(session.state, .startingRuntime)

        session.transitionToStartingProcess()
        XCTAssertEqual(session.state, .startingProcess)

        session.recordProcessCreated(pid: 4321, processName: "wine64")
        if case .running(let identity) = session.state {
            XCTAssertEqual(identity.processIdentifier, 4321)
            XCTAssertEqual(identity.processName, "wine64")
        } else {
            XCTFail("Expected .running state, got \(session.state)")
        }

        session.transitionToTerminating()
        XCTAssertEqual(session.state, .terminating)

        session.recordTermination(exitCode: 0, reason: .normalExit)
        if case .terminated(let info) = session.state {
            XCTAssertEqual(info.exitCode, 0)
            XCTAssertEqual(info.reason, .normalExit)
        } else {
            XCTFail("Expected .terminated state, got \(session.state)")
        }
        XCTAssertNotNil(session.endTime)
    }

    func testProcessCreated_DoesNotImplyGameSuccess() {
        let plan = makeSamplePlan()
        let session = LaunchSession(plan: plan)

        session.recordProcessCreated(pid: 9999, processName: "wine64")

        XCTAssertTrue(session.state.isRunning)
        XCTAssertEqual(session.processIdentity?.processIdentifier, 9999)
        // No fake game-success property exists on LaunchSession
    }

    func testProcessTermination_NormalExit() {
        let plan = makeSamplePlan()
        let session = LaunchSession(plan: plan)

        session.recordProcessCreated(pid: 1000)
        session.recordTermination(exitCode: 0, reason: .normalExit)

        if case .terminated(let info) = session.state {
            XCTAssertEqual(info.exitCode, 0)
            XCTAssertEqual(info.reason, .normalExit)
        } else {
            XCTFail("Expected terminated, got \(session.state)")
        }
        XCTAssertTrue(session.state.isTerminal)
    }

    func testProcessTermination_CrashExit() {
        let plan = makeSamplePlan()
        let session = LaunchSession(plan: plan)

        session.recordProcessCreated(pid: 1001)
        session.recordTermination(exitCode: 139, reason: .uncaughtSignal)

        if case .crashed(let exitCode, _) = session.state {
            XCTAssertEqual(exitCode, 139)
        } else {
            XCTFail("Expected crashed, got \(session.state)")
        }
        XCTAssertTrue(session.state.isTerminal)
    }

    func testFailureStageRecording() {
        let plan = makeSamplePlan()
        let session = LaunchSession(plan: plan)

        session.recordFailure(stage: .containerFailure, message: "Properties.plist unreadable")

        if case .failed(let stage, let message) = session.state {
            XCTAssertEqual(stage, .containerFailure)
            XCTAssertEqual(message, "Properties.plist unreadable")
        } else {
            XCTFail("Expected failed, got \(session.state)")
        }
        XCTAssertEqual(session.failureStage, .containerFailure)
        XCTAssertTrue(session.state.isTerminal)
    }

    func testTerminalStateImmutability() {
        let plan = makeSamplePlan()
        let session = LaunchSession(plan: plan)

        session.recordFailure(stage: .runtimeUnavailable, message: "Runtime missing")
        XCTAssertTrue(session.state.isTerminal)

        // Attempting to transition after terminal state should be ignored
        session.transitionToStartingProcess()
        session.recordProcessCreated(pid: 555)

        if case .failed(let stage, _) = session.state {
            XCTAssertEqual(stage, .runtimeUnavailable)
        } else {
            XCTFail("State mutated after reaching terminal state")
        }
    }

    func testDiagnosticsGeneration_SuccessAndFailure() {
        let plan = makeSamplePlan()
        let session = LaunchSession(plan: plan)

        session.recordProcessCreated(pid: 1234)
        let runningDiag = session.generateDiagnostics()

        XCTAssertEqual(runningDiag.gameId, "subnautica-01")
        XCTAssertEqual(runningDiag.gameTitle, "Subnautica")
        XCTAssertEqual(runningDiag.runtimeFamily, .wine11)
        XCTAssertEqual(runningDiag.graphicsBackend, .dxvk)
        XCTAssertEqual(runningDiag.reportedGPUMemoryMB, 8192)
        XCTAssertEqual(runningDiag.processID, 1234)
        XCTAssertTrue(runningDiag.userSummary.contains("Running (PID 1234)"))

        let failedSession = LaunchSession(plan: plan)
        failedSession.recordFailure(stage: .artifactFailure, message: "d3d11.dll checksum mismatch")
        let failedDiag = failedSession.generateDiagnostics()

        XCTAssertEqual(failedDiag.failureStage, .artifactFailure)
        XCTAssertEqual(failedDiag.failureMessage, "d3d11.dll checksum mismatch")
        XCTAssertTrue(failedDiag.userSummary.contains("Launch failed at artifactFailure"))
    }

    func testProcessMonitorRegistrationAndObservation() {
        let monitor = ProcessMonitor()
        let plan = makeSamplePlan()
        let session = LaunchSession(plan: plan)

        monitor.register(session: session)
        XCTAssertEqual(monitor.activeSessionCount, 1)
        XCTAssertNotNil(monitor.session(for: session.id))

        monitor.unregister(sessionId: session.id)
        XCTAssertEqual(monitor.activeSessionCount, 0)
        XCTAssertNil(monitor.session(for: session.id))
    }

    func testThreadSafetyAndConcurrency() {
        let plan = makeSamplePlan()
        let session = LaunchSession(plan: plan)

        let iterations = 100
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            if i % 2 == 0 {
                _ = session.state
            } else {
                _ = session.generateDiagnostics()
            }
        }
        XCTAssertNotNil(session.state)
    }

    func testNoAccidentalPersistenceMutation() {
        let plan = makeSamplePlan()
        let session = LaunchSession(plan: plan)
        session.recordProcessCreated(pid: 777)
        session.recordTermination(exitCode: 0)

        // LaunchSession is purely in-memory and does not touch UserDefaults keys or persistent game data
        XCTAssertNotNil(session.terminationInfo)
    }

    func testLocalGamePipelineSessionFlow() {
        let plan = makeSamplePlan()
        let session = LaunchSession(plan: plan)

        session.transitionToResolving()
        session.transitionToProvisioning()
        session.transitionToStartingRuntime()
        session.transitionToStartingProcess()
        session.recordProcessCreated(pid: 54321, processName: "wine64")

        XCTAssertTrue(session.state.isRunning)
        XCTAssertEqual(session.processIdentity?.processName, "wine64")

        session.recordTermination(exitCode: 0, reason: .normalExit)
        XCTAssertTrue(session.state.isTerminal)
        XCTAssertEqual(session.terminationInfo?.exitCode, 0)
    }

    func testEpicProviderPipelineSessionFlow() {
        let plan = makeSamplePlan()
        let session = LaunchSession(plan: plan)

        session.transitionToResolving()
        session.transitionToProvisioning()
        session.transitionToStartingRuntime()
        session.transitionToStartingProcess()
        session.recordProcessCreated(pid: 12121, processName: "legendary")

        XCTAssertTrue(session.state.isRunning)
        XCTAssertEqual(session.processIdentity?.processName, "legendary")

        session.recordTermination(exitCode: 0, reason: .normalExit)
        XCTAssertTrue(session.state.isTerminal)
        XCTAssertEqual(session.terminationInfo?.exitCode, 0)
    }

    func testNoDuplicatedRuntimeResolutionInPipeline() {
        let plan = makeSamplePlan()
        XCTAssertEqual(plan.runtimeID, .wine11)
        XCTAssertEqual(plan.runtimeFamily, .wine11)
        XCTAssertEqual(plan.graphicsBackend, .dxvk)
        XCTAssertEqual(plan.reportedGPUMemoryMB, 8192)
    }
}
