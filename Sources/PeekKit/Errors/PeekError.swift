//
//  PeekError.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What can go wrong reading or summarising data.
public enum PeekError: Error, Sendable, Equatable {

    /// The bytes are not any format this reads.
    case unreadable(String)

    /// The file parsed, but holds no rows.
    case empty(String)

    /// A field was asked for that the data does not have.
    case noSuchField(String, available: [String])

    /// A field was asked to be summarised as numbers and is not numeric.
    case notNumeric(String)
}

extension PeekError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .unreadable(let detail):
            "could not read this as JSON, NDJSON, CSV or TSV: \(detail)"
        case .empty(let source):
            "\(source) parsed but holds no rows"
        case .noSuchField(let name, let available):
            "no field \"\(name)\". Available: \(available.prefix(12).joined(separator: ", "))"
        case .notNumeric(let name):
            "\"\(name)\" holds no numbers to summarise"
        }
    }
}
