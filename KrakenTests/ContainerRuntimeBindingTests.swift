//
//  ContainerRuntimeBindingTests.swift
//  KrakenTests
//
// Copyright © 2026 Kraken contributors
//

import XCTest
@testable import Kraken

final class ContainerRuntimeBindingTests: XCTestCase {

    // MARK: - 1. Legacy Container Backward Compatibility

    func testLegacyContainerPlistDecodesToMythicEngine() throws {
        let originalContainer = Wine.Container(
            name: "Legacy Container",
            url: URL(fileURLWithPath: "/tmp/legacy_container"),
            id: UUID(),
            settings: .init(),
            runtimeID: .mythicEngine
        )

        let encoded = try PropertyListEncoder().encode(originalContainer)
        var plist = try PropertyListSerialization.propertyList(from: encoded, format: nil) as! [String: Any]
        // Strip runtimeID to simulate legacy plist from previous Kraken version
        plist.removeValue(forKey: "runtimeID")
        let legacyData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)

        let decoded = try PropertyListDecoder().decode(Wine.Container.self, from: legacyData)
        XCTAssertEqual(decoded.name, "Legacy Container")
        XCTAssertEqual(decoded.runtimeID, .mythicEngine, "Legacy container without runtimeID in plist must decode to .mythicEngine")
    }

    // MARK: - 2. Modern Container Plist Roundtrip

    func testWine11ContainerPlistRoundtrip() throws {
        let originalContainer = Wine.Container(
            name: "Wine 11 Test Container",
            url: URL(fileURLWithPath: "/tmp/wine11_test_container"),
            id: UUID(),
            settings: .init(),
            runtimeID: .wine11
        )

        let encoded = try PropertyListEncoder().encode(originalContainer)
        let decoded = try PropertyListDecoder().decode(Wine.Container.self, from: encoded)

        XCTAssertEqual(decoded.name, "Wine 11 Test Container")
        XCTAssertEqual(decoded.runtimeID, .wine11)
    }

    func testGPTKContainerPlistRoundtrip() throws {
        let originalContainer = Wine.Container(
            name: "GPTK 4 Test Container",
            url: URL(fileURLWithPath: "/tmp/gptk_test_container"),
            id: UUID(),
            settings: .init(),
            runtimeID: .gptk
        )

        let encoded = try PropertyListEncoder().encode(originalContainer)
        let decoded = try PropertyListDecoder().decode(Wine.Container.self, from: encoded)

        XCTAssertEqual(decoded.name, "GPTK 4 Test Container")
        XCTAssertEqual(decoded.runtimeID, .gptk)
    }

    // MARK: - 3. Container Reference & Resolution Binding

    func testContainerReferenceIdentity() {
        let url1 = URL(fileURLWithPath: "/Users/test/ContainerA")
        let url2 = URL(fileURLWithPath: "/Users/test/ContainerA")
        let url3 = URL(fileURLWithPath: "/Users/test/ContainerB")

        let ref1 = ContainerReference(url: url1)
        let ref2 = ContainerReference(url: url2)
        let ref3 = ContainerReference(url: url3)

        XCTAssertEqual(ref1, ref2)
        XCTAssertNotEqual(ref1, ref3)
        XCTAssertEqual(ref1.hashValue, ref2.hashValue)
    }
}
