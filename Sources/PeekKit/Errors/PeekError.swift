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

    /// A worksheet was asked for that the workbook does not have.
    case noSuchSheet(String, available: [String])

    /// A format this can read but cannot write.
    ///
    /// Reading a workbook is cheap; writing one means hand-assembling OOXML
    /// for something callers rarely need, since every tool here already emits
    /// CSV and every spreadsheet opens it.
    case cannotWrite(String)
}

extension PeekError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .unreadable(let detail):
            // Derived from the cases rather than written out: this line named
            // four formats for as long as there were four, and went stale the
            // moment YAML and TOML arrived.
            "could not read this as \(DataFormat.allCases.map { $0.rawValue.uppercased() }.joined(separator: ", ")): \(detail)"
        case .empty(let source):
            "\(source) parsed but holds no rows"
        case .noSuchField(let name, let available):
            "no field \"\(name)\". Available: \(available.prefix(12).joined(separator: ", "))"
        case .notNumeric(let name):
            "\"\(name)\" holds no numbers to summarise"
        case .cannotWrite(let format):
            "cannot write \(format) — read-only. Write csv, tsv, json or ndjson instead."
        case .noSuchSheet(let name, let available):
            "no sheet \"\(name)\". Available: \(available.joined(separator: ", "))"
        }
    }
}
