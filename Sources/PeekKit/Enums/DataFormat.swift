//
//  DataFormat.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// The shapes of tabular data this reads.
public enum DataFormat: String, Sendable, CaseIterable, Codable {

    /// A JSON array of objects, or a single object.
    case json

    /// One JSON document per line.
    case ndjson

    /// Comma-separated, RFC 4180.
    case csv

    /// Tab-separated.
    case tsv

    /// The format a file extension implies, when it implies one.
    public static func inferred(fromExtension ext: String) -> DataFormat? {
        switch ext.lowercased() {
        case "json": .json
        case "ndjson", "jsonl": .ndjson
        case "csv": .csv
        case "tsv", "tab": .tsv
        default: nil
        }
    }

    /// The format the content itself looks like.
    ///
    /// Extensions lie, and a great deal of this data arrives through a pipe
    /// with no name at all, so the content is the more reliable witness.
    public static func sniffed(_ text: String) -> DataFormat {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return .json }

        if first == "[" { return .json }
        if first == "{" {
            // One object is JSON; many objects one per line is NDJSON. The
            // difference is whether a newline ever separates two of them.
            let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: true)
            if lines.count > 1, lines.dropFirst().allSatisfy({ $0.trimmingCharacters(in: .whitespaces).hasPrefix("{") }) {
                return .ndjson
            }
            return .json
        }

        let firstLine = trimmed.prefix(while: { $0 != "\n" })
        return firstLine.contains("\t") ? .tsv : .csv
    }
}
