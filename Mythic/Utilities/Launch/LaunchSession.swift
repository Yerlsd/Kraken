//
//  LaunchSession.swift
//  Kraken
//
// Copyright © 2026 Kraken contributors
//

import Foundation

/// Represents the discrete technical stages where a launch sequence can encounter failure.
enum LaunchFailureStage: String, Codable, Equatable, Hashable, Sendable {
    case resolutionFailure
    case runtimeUnavailable
    case containerFailure
    case artifactFailure
    case environmentFailure
    case storageValidationFailure
    case storageMaterializationPending
    case processCreationFailure
    case processTerminationFailure
    case unknown
}

/// Identifies the operating system process executing a launch session.
struct ProcessIdentity: Codable, Equatable, Hashable, Sendable {
    let processIdentifier: Int32
    let processName: String

    init(processIdentifier: Int32, processName: String = "wine64") {
        self.processIdentifier = processIdentifier
        self.processName = processName
    }
}

/// Reason explaining why a process terminated.
enum ProcessTerminationReason: String, Codable, Equatable, Hashable, Sendable {
    case normalExit
    case uncaughtSignal
    case userCancelled
    case startupFailed
    case unknown
}

/// Information recorded upon process termination.
struct ProcessTerminationInfo: Codable, Equatable, Hashable, Sendable {
    let exitCode: Int32
    let reason: ProcessTerminationReason
    let terminationTimestamp: Date

    init(
        exitCode: Int32,
        reason: ProcessTerminationReason = .normalExit,
        terminationTimestamp: Date = Date()
    ) {
        self.exitCode = exitCode
        self.reason = reason
        self.terminationTimestamp = terminationTimestamp
    }
}

/// Observable lifecycle state of a launch session.
enum LaunchSessionState: Equatable, Sendable {
    case preparing
    case resolving
    case provisioning
    case startingRuntime
    case startingProcess
    case running(ProcessIdentity)
    case terminating
    case terminated(ProcessTerminationInfo)
    case crashed(exitCode: Int32, signal: Int32?)
    case failed(stage: LaunchFailureStage, message: String)

    var isTerminal: Bool {
        switch self {
        case .terminated, .crashed, .failed:
            return true
        case .preparing, .resolving, .provisioning, .startingRuntime, .startingProcess, .running, .terminating:
            return false
        }
    }

    var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }
}

/// Diagnostic report generated from a launch session for debugging and user remediation.
struct SessionDiagnostics: Codable, Equatable, Hashable, Sendable {
    let sessionId: UUID
    let gameId: String
    let gameTitle: String
    let sourceProvider: LaunchSourceProvider
    let executablePath: String
    let runtimeFamily: RuntimeFamily
    let runtimeVersion: String
    let containerPath: String
    let graphicsBackend: GraphicsBackend
    let graphicsArtifactVersion: String?
    let reportedGPUMemoryMB: Int
    let processID: Int32?
    let exitCode: Int32?
    let failureStage: LaunchFailureStage?
    let failureMessage: String?
    let timestamp: Date

    init(
        sessionId: UUID,
        gameId: String,
        gameTitle: String,
        sourceProvider: LaunchSourceProvider,
        executablePath: String,
        runtimeFamily: RuntimeFamily,
        runtimeVersion: String,
        containerPath: String,
        graphicsBackend: GraphicsBackend,
        graphicsArtifactVersion: String?,
        reportedGPUMemoryMB: Int,
        processID: Int32? = nil,
        exitCode: Int32? = nil,
        failureStage: LaunchFailureStage? = nil,
        failureMessage: String? = nil,
        timestamp: Date = Date()
    ) {
        self.sessionId = sessionId
        self.gameId = gameId
        self.gameTitle = gameTitle
        self.sourceProvider = sourceProvider
        self.executablePath = executablePath
        self.runtimeFamily = runtimeFamily
        self.runtimeVersion = runtimeVersion
        self.containerPath = containerPath
        self.graphicsBackend = graphicsBackend
        self.graphicsArtifactVersion = graphicsArtifactVersion
        self.reportedGPUMemoryMB = reportedGPUMemoryMB
        self.processID = processID
        self.exitCode = exitCode
        self.failureStage = failureStage
        self.failureMessage = failureMessage
        self.timestamp = timestamp
    }

    /// Clean, user-actionable summary suitable for UI presentation.
    var userSummary: String {
        if let failureStage = failureStage, let message = failureMessage {
            return "Launch failed at \(failureStage.rawValue): \(message)"
        } else if let exitCode = exitCode {
            return "Process exited with code \(exitCode)"
        } else if let pid = processID {
            return "Running (PID \(pid)) on \(runtimeFamily.rawValue) via \(graphicsBackend.displayName)"
        } else {
            return "Ready to launch \(gameTitle)"
        }
    }
}

/// Thread-safe, concrete launch session managing process lifecycle and state transitions.
final class LaunchSession: Identifiable, @unchecked Sendable {
    let id: UUID
    let plan: LaunchPlan
    let startTime: Date

    // Thread-safe state access
    private let lock = NSLock()
    private var _state: LaunchSessionState
    private var _endTime: Date?
    private var _processIdentity: ProcessIdentity?
    private var _terminationInfo: ProcessTerminationInfo?
    private var _failureStage: LaunchFailureStage?
    private var _failureMessage: String?

    init(plan: LaunchPlan, id: UUID = UUID(), startTime: Date = Date()) {
        self.id = id
        self.plan = plan
        self.startTime = startTime
        self._state = .preparing
    }

    var state: LaunchSessionState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    var endTime: Date? {
        lock.lock()
        defer { lock.unlock() }
        return _endTime
    }

    var processIdentity: ProcessIdentity? {
        lock.lock()
        defer { lock.unlock() }
        return _processIdentity
    }

    var terminationInfo: ProcessTerminationInfo? {
        lock.lock()
        defer { lock.unlock() }
        return _terminationInfo
    }

    var failureStage: LaunchFailureStage? {
        lock.lock()
        defer { lock.unlock() }
        return _failureStage
    }

    // MARK: - State Transitions

    func transitionToResolving() {
        lock.lock()
        defer { lock.unlock() }
        guard !_state.isTerminal else { return }
        _state = .resolving
    }

    func transitionToProvisioning() {
        lock.lock()
        defer { lock.unlock() }
        guard !_state.isTerminal else { return }
        _state = .provisioning
    }

    func transitionToStartingRuntime() {
        lock.lock()
        defer { lock.unlock() }
        guard !_state.isTerminal else { return }
        _state = .startingRuntime
    }

    func transitionToStartingProcess() {
        lock.lock()
        defer { lock.unlock() }
        guard !_state.isTerminal else { return }
        _state = .startingProcess
    }

    func recordProcessCreated(pid: Int32, processName: String = "wine64") {
        lock.lock()
        defer { lock.unlock() }
        guard !_state.isTerminal else { return }
        let identity = ProcessIdentity(processIdentifier: pid, processName: processName)
        _processIdentity = identity
        _state = .running(identity)
    }

    func transitionToTerminating() {
        lock.lock()
        defer { lock.unlock() }
        guard !_state.isTerminal else { return }
        _state = .terminating
    }

    func recordTermination(exitCode: Int32, reason: ProcessTerminationReason = .normalExit) {
        lock.lock()
        defer { lock.unlock() }
        guard !_state.isTerminal else { return }
        let now = Date()
        _endTime = now
        let info = ProcessTerminationInfo(exitCode: exitCode, reason: reason, terminationTimestamp: now)
        _terminationInfo = info
        if exitCode == 0 || reason == .userCancelled {
            _state = .terminated(info)
        } else {
            _state = .crashed(exitCode: exitCode, signal: nil)
        }
    }

    func recordFailure(stage: LaunchFailureStage, message: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !_state.isTerminal else { return }
        _endTime = Date()
        _failureStage = stage
        _failureMessage = message
        _state = .failed(stage: stage, message: message)
    }

    // MARK: - Diagnostics Generation

    func generateDiagnostics() -> SessionDiagnostics {
        lock.lock()
        defer { lock.unlock() }

        return SessionDiagnostics(
            sessionId: id,
            gameId: plan.gameId,
            gameTitle: plan.gameTitle,
            sourceProvider: plan.sourceProvider,
            executablePath: plan.executableURL.path(percentEncoded: false),
            runtimeFamily: plan.runtimeFamily,
            runtimeVersion: plan.runtimeVersion,
            containerPath: plan.containerURL.path(percentEncoded: false),
            graphicsBackend: plan.graphicsBackend,
            graphicsArtifactVersion: plan.graphicsArtifactManifest?.version,
            reportedGPUMemoryMB: plan.reportedGPUMemoryMB,
            processID: _processIdentity?.processIdentifier,
            exitCode: _terminationInfo?.exitCode,
            failureStage: _failureStage,
            failureMessage: _failureMessage,
            timestamp: startTime
        )
    }
}
