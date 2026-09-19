//
//  PersistenceTests.swift
//  KrakenTests
//
// Copyright © 2026 Kraken contributors

import XCTest
@testable import Kraken

/// Tests for game library persistence corruption safety.
///
/// These tests verify the critical invariant that malformed persisted data cannot
/// be silently overwritten, protecting against the data-loss vulnerability where
/// a corrupted game library could be replaced with an empty or partial library.
@MainActor
final class PersistenceTests: XCTestCase {

    var testDefaults: UserDefaults!
    var testStore: GameDataStore!

    override func setUp() async throws {
        try await super.setUp()

        // Use isolated UserDefaults domain for tests
        let suiteName = "com.yerlsd.kraken.tests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!

        // Clean slate
        testDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        // Clean up test domain
        if let suiteName = testDefaults.dictionaryRepresentation().keys.first {
            testDefaults.removePersistentDomain(forName: suiteName)
        }
        testDefaults = nil
        testStore = nil

        try await super.tearDown()
    }

    // MARK: - Basic Persistence

    func testAbsentKeyProducesEmptyLibrary() throws {
        // When no games key exists
        testStore = GameDataStore(store: testDefaults)

        // Then library is empty
        XCTAssertTrue(testStore.library.isEmpty)
        XCTAssertEqual(testStore.persistenceState, .healthy)
        XCTAssertFalse(testStore.isPersistenceSuspended)
    }

    func testValidLibraryLoadsSuccessfully() throws {
        // Given a valid game library
        let game = LocalGame(
            id: "test.game",
            title: "Test Game",
            installationState: .installed(location: URL(fileURLWithPath: "/tmp/test.app"), platform: .macOS)
        )

        let encoded = try PropertyListEncoder().encode([AnyGame(game)])
        testDefaults.set(encoded, forKey: GameDataStore.libraryKey)

        // When store loads
        testStore = GameDataStore(store: testDefaults)

        // Then library contains the game
        XCTAssertEqual(testStore.library.count, 1)
        XCTAssertEqual(testStore.library.first?.id, "test.game")
        XCTAssertEqual(testStore.persistenceState, .healthy)
        XCTAssertFalse(testStore.isPersistenceSuspended)
    }

    // MARK: - Malformed Data Detection

    func testMalformedPayloadDetectedAtInit() throws {
        // Given a malformed payload (invalid property list)
        let malformedData = Data("not a valid plist".utf8)
        testDefaults.set(malformedData, forKey: GameDataStore.libraryKey)

        // When store loads
        testStore = GameDataStore(store: testDefaults)

        // Then degraded state is entered
        XCTAssertTrue(testStore.isPersistenceSuspended)
        XCTAssertEqual(testStore.persistenceState, .unreadable)

        // And library remains empty rather than silently becoming []
        XCTAssertTrue(testStore.library.isEmpty)

        // And malformed payload is still on disk
        let stillThere = testDefaults.data(forKey: GameDataStore.libraryKey)
        XCTAssertEqual(stillThere, malformedData)
    }

    func testPartiallyMalformedPayloadDetected() throws {
        // Given a payload with one valid and one invalid record
        let validGame = LocalGame(
            id: "valid.game",
            title: "Valid Game",
            installationState: .uninstalled
        )

        // Encode valid game to get its dictionary representation
        let validEncoded = try PropertyListEncoder().encode(AnyGame(validGame))
        let validDict = try PropertyListSerialization.propertyList(from: validEncoded, format: nil)

        // Create invalid dictionary (missing required AnyGame keys)
        let invalidDict: [String: Any] = ["invalid": "structure", "missing": "required keys"]

        // Construct array with valid + invalid elements
        let corruptArray: [Any] = [validDict, invalidDict]

        let arrayData = try PropertyListSerialization.data(
            fromPropertyList: corruptArray,
            format: .binary,
            options: 0
        )

        testDefaults.set(arrayData, forKey: GameDataStore.libraryKey)

        // When store loads
        testStore = GameDataStore(store: testDefaults)

        // Then partial degradation is detected
        if case .partiallyReadable(let lost) = testStore.persistenceState {
            XCTAssertEqual(lost, 1)
        } else {
            XCTFail("Expected partiallyReadable state, got \(testStore.persistenceState)")
        }

        XCTAssertTrue(testStore.isPersistenceSuspended)

        // And valid game is recovered
        XCTAssertEqual(testStore.library.count, 1)
        XCTAssertEqual(testStore.library.first?.id, "valid.game")
    }

    // MARK: - Write Protection

    func testMalformedPayloadNotOverwrittenByMutation() throws {
        // Given malformed data is detected at init
        let malformedData = Data("corrupted library".utf8)
        testDefaults.set(malformedData, forKey: GameDataStore.libraryKey)
        testStore = GameDataStore(store: testDefaults)

        XCTAssertTrue(testStore.isPersistenceSuspended)

        // When a game is added to the in-memory library
        let newGame = LocalGame(
            id: "new.game",
            title: "New Game",
            installationState: .uninstalled
        )
        testStore.library.insert(newGame)

        // Then the malformed stored payload is NOT overwritten
        let afterMutation = testDefaults.data(forKey: GameDataStore.libraryKey)
        XCTAssertEqual(afterMutation, malformedData, "Malformed payload was overwritten despite suspended persistence")
    }

    func testRuntimeDetectedCorruptionSuspendsWrites() throws {
        // Given store starts with valid data
        let game = LocalGame(id: "test", title: "Test", installationState: .uninstalled)
        let encoded = try PropertyListEncoder().encode([AnyGame(game)])
        testDefaults.set(encoded, forKey: GameDataStore.libraryKey)

        testStore = GameDataStore(store: testDefaults)
        XCTAssertFalse(testStore.isPersistenceSuspended)

        // When external corruption occurs (simulated by writing malformed data)
        let malformedData = Data("runtime corruption".utf8)
        testDefaults.set(malformedData, forKey: GameDataStore.libraryKey)

        // Trigger the observer update
        testDefaults.synchronize()
        NotificationCenter.default.post(
            name: UserDefaults.didChangeNotification,
            object: testDefaults
        )

        // Give observer time to process (it runs on main queue)
        let expectation = expectation(description: "Observer processes change")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Then GameDataStore enters degraded state
        XCTAssertTrue(testStore.isPersistenceSuspended, "Runtime-detected corruption should suspend persistence")
        XCTAssertEqual(testStore.persistenceState, .unreadable)

        // And subsequent mutations don't overwrite the malformed data
        let anotherGame = LocalGame(id: "another", title: "Another", installationState: .uninstalled)
        testStore.library.insert(anotherGame)

        let afterMutation = testDefaults.data(forKey: GameDataStore.libraryKey)
        XCTAssertEqual(afterMutation, malformedData, "Malformed payload overwritten after runtime detection")
    }

    // MARK: - Explicit Recovery

    func testExplicitRecoveryAllowsRewrite() throws {
        // Given degraded state from malformed data
        let malformedData = Data("corrupted".utf8)
        testDefaults.set(malformedData, forKey: GameDataStore.libraryKey)
        testStore = GameDataStore(store: testDefaults)

        XCTAssertTrue(testStore.isPersistenceSuspended)

        // When explicit recovery is authorized
        testStore.authoriseLibraryRewrite()

        // Then persistence is restored
        XCTAssertFalse(testStore.isPersistenceSuspended)
        XCTAssertEqual(testStore.persistenceState, .healthy)

        // And the payload is now valid (empty library was written)
        let afterRecovery = testDefaults.data(forKey: GameDataStore.libraryKey)
        XCTAssertNotEqual(afterRecovery, malformedData)

        // And subsequent mutations work
        let game = LocalGame(id: "recovered", title: "Recovered", installationState: .uninstalled)
        testStore.library.insert(game)

        let afterMutation = testDefaults.data(forKey: GameDataStore.libraryKey)
        XCTAssertNotNil(afterMutation)

        // Verify the game was actually persisted
        let decoded = try PropertyListDecoder().decode([AnyGame].self, from: afterMutation!)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.base.id, "recovered")
    }

    func testRecoveryOnHealthyStateIsNoop() throws {
        // Given healthy state
        testStore = GameDataStore(store: testDefaults)
        XCTAssertEqual(testStore.persistenceState, .healthy)

        // When authoriseLibraryRewrite is called
        testStore.authoriseLibraryRewrite()

        // Then state remains healthy (no-op)
        XCTAssertEqual(testStore.persistenceState, .healthy)
    }
}
