//
//  PersistedValue.swift
//  Mythic
//
// Copyright © 2026 Kraken contributors

import Foundation
import OSLog

/// The outcome of reading a `Codable` value out of a `UserDefaults` store.
///
/// The three cases must stay distinct. A *missing* key legitimately means
/// "use the default value", but a *malformed* value means real user data is
/// present and simply could not be understood. Collapsing those two into a
/// single `nil` is what allowed a whole game library to read as empty and then
/// be overwritten by that emptiness on the next mutation.
enum PersistedValue<Value> {
    /// The key is not present in the store at all.
    case absent

    /// The key is present and decoded successfully.
    case value(Value)

    /// The key is present but could not be decoded. The payload is still on disk.
    case malformed(Error)

    var decoded: Value? {
        guard case let .value(value) = self else { return nil }
        return value
    }

    var isMalformed: Bool {
        if case .malformed = self { return true }
        return false
    }
}

extension UserDefaults {
    /// Read a `Codable` value, distinguishing absent from malformed.
    ///
    /// Mirrors `decodeAndGet(_:forKey:)`'s tolerance of values that
    /// `encodeAndSet(_:forKey:)` wrapped in a single-element array, but reports
    /// a decode failure instead of erasing it.
    func decodePersistedValue<T>(_ type: T.Type, forKey key: String) -> PersistedValue<T> where T: Decodable {
        guard let data = self.data(forKey: key) else { return .absent }
        return Self.decodePersistedValue(T.self, from: data)
    }

    static func decodePersistedValue<T>(_ type: T.Type, from data: Data) -> PersistedValue<T> where T: Decodable {
        let decoder: PropertyListDecoder = .init()

        do {
            return .value(try decoder.decode(T.self, from: data))
        } catch let directFailure {
            /*
             PropertyListCoders require an array or dictionary at the top level,
             so non-collection values are wrapped in an array before encoding.
             Unwrap that before concluding the payload is malformed.
             */
            if let unwrapped = try? decoder.decode([T].self, from: data),
               let first = unwrapped.first {
                return .value(first)
            }

            return .malformed(directFailure)
        }
    }
}

// MARK: - Resilient game library decoding

/// Result of decoding the persisted game library one record at a time.
struct DecodedGameLibrary {
    /// Records that decoded successfully.
    let games: [AnyGame]

    /// Number of records that were present but could not be decoded.
    let unreadableRecordCount: Int

    /// Errors from unreadable records, for diagnostics.
    let failures: [Error]

    var isComplete: Bool { unreadableRecordCount == 0 }
}

/// Decodes the `games` blob without letting one bad record destroy the rest.
///
/// A plain `decode([AnyGame].self, from:)` is all-or-nothing: a single record
/// carrying an unknown `RuntimeID` (or any other undecodable field) throws and
/// the entire library reads as empty. Records are therefore re-serialised and
/// decoded individually.
enum GameLibraryCoder {
    struct NotAnArrayError: LocalizedError {
        var errorDescription: String? {
            "The stored game library is not a property-list array."
        }
    }

    static func decodeResilient(from data: Data) throws -> DecodedGameLibrary {
        let root = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )

        guard let records = root as? [Any] else { throw NotAnArrayError() }

        let decoder: PropertyListDecoder = .init()
        var games: [AnyGame] = []
        var failures: [Error] = []
        games.reserveCapacity(records.count)

        for record in records {
            do {
                // Each record is a plist dictionary, which is a valid plist root.
                let recordData = try PropertyListSerialization.data(
                    fromPropertyList: record,
                    format: .binary,
                    options: 0
                )
                games.append(try decoder.decode(AnyGame.self, from: recordData))
            } catch {
                failures.append(error)
            }
        }

        return .init(
            games: games,
            unreadableRecordCount: failures.count,
            failures: failures
        )
    }
}
