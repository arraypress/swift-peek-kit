//
//  CodeLanguage.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// A language `Shape` can be emitted as.
///
/// Deliberately short. These are the three that answer "I have this data,
/// give me something to decode it into"; adding a fourth is an emitter, not
/// a redesign.
public enum CodeLanguage: String, Sendable, CaseIterable, Codable {
    case swift
    case typescript
    case go

    /// What to call the file this would live in.
    public var fileExtension: String {
        switch self {
        case .swift: "swift"
        case .typescript: "ts"
        case .go: "go"
        }
    }

    public init?(argument: String) {
        switch argument.lowercased() {
        case "swift": self = .swift
        case "typescript", "ts": self = .typescript
        case "go", "golang": self = .go
        default: return nil
        }
    }
}
