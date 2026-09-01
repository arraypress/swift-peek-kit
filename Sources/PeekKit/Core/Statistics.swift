//
//  Statistics.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Distributions and tallies over a dataset's columns.
public enum Statistics {

    /// Summarises one numeric field.
    ///
    /// - Throws: ``PeekError/noSuchField(_:available:)`` when the path is not
    ///   in the data, and ``PeekError/notNumeric(_:)`` when it is but holds
    ///   nothing that reads as a number.
    public static func summary(of path: String, in dataset: Dataset) throws -> NumericSummary {
        let column = try resolve(path, in: dataset)
        let numbers = column.flatMap(numbers(in:)).sorted()
        guard !numbers.isEmpty else { throw PeekError.notNumeric(path) }

        let total = numbers.reduce(0, +)
        return NumericSummary(
            field: path,
            count: numbers.count,
            missing: dataset.count - numbers.count,
            minimum: numbers[0],
            p10: percentile(numbers, 0.10),
            p25: percentile(numbers, 0.25),
            median: percentile(numbers, 0.50),
            p75: percentile(numbers, 0.75),
            p90: percentile(numbers, 0.90),
            maximum: numbers[numbers.count - 1],
            mean: total / Double(numbers.count),
            sum: total
        )
    }

    /// Counts how often each value of a field occurs, commonest first.
    ///
    /// An array-valued field is counted element by element rather than as a
    /// whole: a row carrying three issue codes contributes to three tallies,
    /// which is what "how often does this code appear" means. Shares are
    /// therefore taken against the row count and can exceed 1 in total, which
    /// is honest — the alternative is a percentage that hides multiples.
    /// - Parameters:
    ///   - path: The field or dotted path to tally.
    ///   - dataset: The data.
    ///   - limit: Keep only this many of the commonest values.
    ///   - truncatingAt: Characters that end the part worth counting.
    ///     Messages carry their variable half after a separator — `"hot:
    ///     +6.74 dBFS"` and `"hot: +6.97 dBFS"` are one finding reported
    ///     twice, and tallying them whole produces a list as long as the
    ///     data. Cutting at `":("` groups them under `hot`.
    public static func counts(
        of path: String,
        in dataset: Dataset,
        limit: Int? = nil,
        truncatingAt separators: String = ""
    ) throws -> [ValueCount] {
        let column = try resolve(path, in: dataset)
        let cutSet = Set(separators)
        var tally: [String: Int] = [:]

        for value in column {
            for leaf in flatten(value) {
                tally[truncate(leaf, at: cutSet), default: 0] += 1
            }
        }

        let rows = max(dataset.count, 1)
        let sorted = tally
            .map { ValueCount(value: $0.key, count: $0.value, share: Double($0.value) / Double(rows)) }
            .sorted { ($0.count, $1.value) > ($1.count, $0.value) }

        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
    }

    // MARK: - Internals

    /// The value at `percentile` by nearest rank, on already-sorted numbers.
    ///
    /// Nearest rank rather than interpolation, so every number reported is a
    /// number that actually occurred. For "what does the 90th percentile
    /// preset measure" an interpolated value nothing produced is a worse
    /// answer than a real one.
    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Int((fraction * Double(sorted.count)).rounded(.down))
        return sorted[min(max(index, 0), sorted.count - 1)]
    }

    /// Every number inside a value, reaching into arrays.
    static func numbers(in value: Value) -> [Double] {
        switch value {
        case .array(let items): items.flatMap(numbers(in:))
        default: value.numeric.map { [$0] } ?? []
        }
    }

    /// The part of a label before the first separator, trimmed.
    static func truncate(_ text: String, at separators: Set<Character>) -> String {
        guard !separators.isEmpty else { return text }
        let head = text.prefix { !separators.contains($0) }
        let trimmed = head.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? text : trimmed
    }

    /// Every countable leaf inside a value, as text.
    static func flatten(_ value: Value) -> [String] {
        switch value {
        case .array(let items): items.flatMap(flatten)
        case .null: []
        default: [value.text]
        }
    }

    /// The column for a path, or a helpful refusal naming what does exist.
    static func resolve(_ path: String, in dataset: Dataset) throws -> [Value] {
        let column = dataset.column(path)
        guard column.contains(where: { !$0.isMissing }) else {
            throw PeekError.noSuchField(path, available: dataset.paths())
        }
        return column
    }
}
