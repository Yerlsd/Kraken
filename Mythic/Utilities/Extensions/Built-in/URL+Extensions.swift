//
//  URL.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 28/1/2024.
//

// Copyright © 2023-2025 vapidinfinity

import Foundation

extension URL {
    public var prettyPath: String {
        var displayPath = path(percentEncoded: false)
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            displayPath = displayPath.replacingOccurrences(of: bundleIdentifier, with: "(Kraken)")
        }
        return displayPath
            .replacingOccurrences(of: "/Users/\(NSUserName())", with: "~")
            .replacingOccurrences(of: "file://", with: "")
    }
}
