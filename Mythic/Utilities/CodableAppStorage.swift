//
//  CodableAppStorage.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 7/11/2025.
//

// Copyright © 2023-2025 vapidinfinity

import Foundation
import SwiftUI
import Combine
import OSLog

/// A property wrapper type that reflects a `Codable` value from `UserDefaults` and invalidates a view on a change when said value changes.
@MainActor
@frozen @propertyWrapper public struct CodableAppStorage<Value>: @MainActor DynamicProperty where Value: Codable & Equatable {
    @StateObject private var observer: CodableUserDefaultsObserver<Value>
    @State private var transaction: Transaction = .init()
    
    private let key: String
    private let store: UserDefaults
    
    public var wrappedValue: Value {
        get { observer.value }
        nonmutating set {
            withTransaction(transaction) {
                _ = try? store.encodeAndSet(newValue, forKey: key)
            }
        }
    }
    
    public var projectedValue: Binding<Value> {
        .init(
            get: { self.observer.value },
            set: { newValue in
                withTransaction(self.transaction) {
                    _ = try? store.encodeAndSet(newValue, forKey: key)
                }
            }
        )
    }
    
    public mutating func update() {
        _observer.update()
        _transaction.update()
    }
}

extension CodableAppStorage {
    /**
     Creates a property that can read and write to a codable user default.
     
     - Parameters:
     - wrappedValue: The default value if a codable value is not specified for the given key.
     - key: The key to read and write the value to in the user defaults store.
     - store: The user defaults store to read and write to. A value of `nil` will use the `.standard` store.
     */
    public init(wrappedValue: Value, _ key: String, store: UserDefaults = .standard) {
        self.key = key
        self.store = store
        
        let stored = self.store.decodePersistedValue(Value.self, forKey: key)
        let initialValue: Value

        switch stored {
        case let .value(actualValue):
            initialValue = actualValue
        case .malformed:
            // Leave the undecodable payload in place; seeding the default here
            // would destroy it.
            Logger.app.error("""
                CodableAppStorage found an undecodable value for "\(key, privacy: .public)". \
                Using the default in memory and leaving the stored payload untouched.
                """)
            initialValue = wrappedValue
        case .absent:
            do {
                try self.store.encodeAndSet(wrappedValue, forKey: key)
            } catch {
                Logger.app.error("""
                    CodableAppStorage was unable to re-encode wrappedValue as a fallback.
                    This may cause unintended behaviour.
                    """)
            }
            initialValue = wrappedValue
        }
        
        let capturedStore: UserDefaults = self.store
        self._observer = .init(
            wrappedValue: .init(key: key,
                                defaultValue: wrappedValue,
                                store: capturedStore,
                                initialValue: initialValue,
                                isStoredValueMalformed: stored.isMalformed)
        )
        
        self._transaction = .init(initialValue: .init())
    }
}

extension CodableAppStorage where Value: ExpressibleByNilLiteral {
    /**
     Creates a property that can read and write an Optional codable user
     default.
     
     Defaults to nil if there is no restored value.
     
     - Parameters:
     - key: The key to read and write the value to in the user defaults store.
     - store: The user defaults store to read and write to. A value of `nil` will use the user default store from the environment.
     */
    public init(_ key: String, store: UserDefaults = .standard) {
        self.key = key
        self.store = store
        
        let initialValue: Value = (try? self.store.decodeAndGet(Value.self, forKey: key)) ?? nil
        
        let capturedStore: UserDefaults = self.store
        self._observer = .init(
            wrappedValue: .init(key: key,
                                defaultValue: nil,
                                store: capturedStore,
                                initialValue: initialValue)
        )
        self._transaction = .init(initialValue: .init())
    }
}

/// Internal observable object that monitors UserDefaults changes for Codable types.
@MainActor
@usableFromInline final class CodableUserDefaultsObserver<T>: ObservableObject where T: Codable & Equatable {
    @Published public private(set) var value: T

    /// `true` when the store holds a value for `key` that could not be decoded.
    ///
    /// While this is set, `value` retains the last good value rather than
    /// silently reverting to `defaultValue` — the undecodable payload is still
    /// on disk and callers must not overwrite it with a default.
    @Published public private(set) var isStoredValueMalformed: Bool = false

    private let key: String
    private let defaultValue: T
    private let store: UserDefaults
    private var cancellable: AnyCancellable?
    
    private let log: Logger = .custom(category: "CodableUserDefaultsObserver")
    
    @MainActor deinit {
        _ = withExtendedLifetime(cancellable, { $0?.cancel() })
    }
    
    convenience init(key: String, defaultValue: T, store: UserDefaults = .standard) {
        let stored = store.decodePersistedValue(T.self, forKey: key)
        self.init(key: key,
                  defaultValue: defaultValue,
                  store: store,
                  initialValue: stored.decoded ?? defaultValue,
                  isStoredValueMalformed: stored.isMalformed)
    }
    
    /**
     Creates an observer that monitors a `UserDefaults` key for changes.
     
     - Parameters:
        - key: The `UserDefaults` key to monitor.
        - defaultValue: The fallback value if decoding fails or the key doesn't exist.
        - store: The `UserDefaults` store to monitor.
        - initialValue: The initial value to use, typically loaded from `UserDefaults` before initialization.
     */
    public init(key: String,
                defaultValue: T,
                store: UserDefaults = .standard,
                initialValue: T,
                isStoredValueMalformed: Bool = false) {
        self.key = key
        self.defaultValue = defaultValue
        self.store = store
        self.value = initialValue
        self.isStoredValueMalformed = isStoredValueMalformed
        
        self.cancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: store)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFromDefaults()
            }
    }
    
    private func updateFromDefaults() {
        let newValue: T

        switch store.decodePersistedValue(T.self, forKey: key) {
        case .absent:
            newValue = defaultValue
            if isStoredValueMalformed { isStoredValueMalformed = false }
        case let .value(decoded):
            newValue = decoded
            if isStoredValueMalformed { isStoredValueMalformed = false }
        case let .malformed(error):
            /*
             Real data is present but unreadable. Keep the value we already have
             so a transient/unknown payload cannot present itself as "empty",
             and flag it so persistence can refuse to overwrite the payload.
             */
            if !isStoredValueMalformed {
                log.error("""
                    Stored value for "\(self.key, privacy: .public)" could not be decoded \
                    and has been left untouched: \(error.localizedDescription, privacy: .public)
                    """)
                isStoredValueMalformed = true
            }
            return
        }

        guard newValue != value else { return }
        value = newValue
    }
}
