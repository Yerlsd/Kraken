//
//  ProcessMonitor.swift
//  Kraken
//
// Copyright © 2026 Kraken contributors
//

import Foundation

/// Protocol for monitoring launch processes and tracking active sessions.
protocol ProcessMonitoring: Sendable {
    func register(session: LaunchSession)
    func unregister(sessionId: UUID)
    func session(for id: UUID) -> LaunchSession?
    var activeSessionCount: Int { get }
}

/// Central event-driven monitor managing active launch sessions and Foundation Process lifecycle.
final class ProcessMonitor: ProcessMonitoring, @unchecked Sendable {
    static let shared = ProcessMonitor()

    private let lock = NSLock()
    private var sessions: [UUID: LaunchSession] = [:]

    init() {}

    func register(session: LaunchSession) {
        lock.lock()
        defer { lock.unlock() }
        sessions[session.id] = session
    }

    func unregister(sessionId: UUID) {
        lock.lock()
        defer { lock.unlock() }
        sessions.removeValue(forKey: sessionId)
    }

    func session(for id: UUID) -> LaunchSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[id]
    }

    var activeSessionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sessions.values.filter { !$0.state.isTerminal }.count
    }

    /// Attaches event-driven termination observation to a Process without polling.
    func observe(
        process: Process,
        session: LaunchSession,
        onTermination: (@Sendable (ProcessTerminationInfo) -> Void)? = nil
    ) {
        register(session: session)

        let existingTerminationHandler = process.terminationHandler

        process.terminationHandler = { [weak self, weak session] terminatedProcess in
            existingTerminationHandler?(terminatedProcess)

            let exitCode = terminatedProcess.terminationStatus
            let reason: ProcessTerminationReason = (terminatedProcess.terminationReason == .exit) ? .normalExit : .uncaughtSignal
            let terminationInfo = ProcessTerminationInfo(exitCode: exitCode, reason: reason)

            session?.recordTermination(exitCode: exitCode, reason: reason)
            if let sessionId = session?.id {
                self?.unregister(sessionId: sessionId)
            }

            onTermination?(terminationInfo)
        }
    }
}
