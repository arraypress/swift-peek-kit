//
//  Dataset.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Rows of named values, however they arrived.
///
/// Everything downstream works on this, so a CSV and a JSON array of objects
/// are the same problem once they are through the door.
public struct Dataset: Sendable {

    /// One row.
    public typealias Row = [String: Value]

    /// The rows, in file order.
    public let rows: [Row]

    /// Field names in the order they were first seen.
    ///
    /// Insertion order, not alphabetical: a CSV's header order is meaningful
    /// and sorting it throws that away.
    public let fields: [String]

    /// Where this came from, when it came from a file.
    public let source: String?

    /// What it was read as.
    public let format: DataFormat

    public init(rows: [Row], fields: [String]? = nil, source: String? = nil, format: DataFormat) {
        self.rows = rows
        self.source = source
        self.format = format
        if let fields {
            self.fields = fields
        } else {
            var seen: Set<String> = []
            var ordered: [String] = []
            for row in rows {
                for key in row.keys.sorted() where seen.insert(key).inserted {
                    ordered.append(key)
                }
            }
            self.fields = ordered
        }
    }

    /// How many rows there are.
    public var count: Int { rows.count }

    /// Every value of one field, missing entries included as `.null`.
    ///
    /// - Parameter path: A field name, or a dotted path into nested objects.
    public func column(_ path: String) -> [Value] {
        rows.map { Self.value(at: path, in: $0) ?? .null }
    }

    /// Reads a dotted path out of one row.
    ///
    /// Fleet payloads nest — `check` returns an array of issues under each
    /// file — so `issues.severity` has to reach through an object, and an
    /// array of objects has to answer for all of its elements at once.
    public static func value(at path: String, in row: Row) -> Value? {
        var current: Value = .object(row)
        for part in path.split(separator: ".") {
            let key = String(part)
            switch current {
            case .object(let fields):
                guard let next = fields[key] else { return nil }
                current = next
            case .array(let items):
                // Reaching into an array either indexes it or maps over it.
                if let index = Int(key) {
                    guard index >= 0, index < items.count else { return nil }
                    current = items[index]
                } else {
                    let mapped = items.compactMap { item -> Value? in
                        guard case .object(let fields) = item else { return nil }
                        return fields[key]
                    }
                    guard !mapped.isEmpty else { return nil }
                    current = .array(mapped)
                }
            default:
                return nil
            }
        }
        return current
    }

    /// Every dotted path this data offers, including those inside nested
    /// objects, so a caller can discover what is addressable.
    public func paths(maxDepth: Int = 3) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        func walk(_ value: Value, prefix: String, depth: Int) {
            guard depth <= maxDepth else { return }
            switch value {
            case .object(let fields):
                for key in fields.keys.sorted() {
                    let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                    if seen.insert(path).inserted { ordered.append(path) }
                    walk(fields[key]!, prefix: path, depth: depth + 1)
                }
            case .array(let items):
                if let first = items.first { walk(first, prefix: prefix, depth: depth) }
            default:
                break
            }
        }

        for row in rows { walk(.object(row), prefix: "", depth: 1) }
        return ordered
    }
}
