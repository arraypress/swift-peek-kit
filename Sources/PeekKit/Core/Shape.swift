//
//  Shape.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Describes what a dataset holds, field by field.
public enum Shape {

    /// The shape of every field, in the order the data presents them.
    ///
    /// - Parameters:
    ///   - dataset: The data to describe.
    ///   - examples: How many sample values to keep per field.
    ///   - nested: Whether to describe fields inside nested objects too.
    public static func of(_ dataset: Dataset, examples: Int = 3, nested: Bool = false) -> [FieldShape] {
        let paths = nested ? dataset.paths() : dataset.fields
        return paths.map { shape(of: $0, in: dataset, examples: examples) }
    }

    /// The shape of one field.
    public static func shape(of path: String, in dataset: Dataset, examples: Int = 3) -> FieldShape {
        describe(name: path, values: dataset.column(path), examples: examples)
    }

    /// The shape of a column of values, whatever produced them.
    ///
    /// Split out from `shape(of:in:)` so that callers who assemble a column
    /// themselves — flattening one that reached through an array, say —
    /// describe it by exactly the same rules rather than a second copy.
    public static func describe(name: String, values: [Value], examples: Int = 3) -> FieldShape {
        var kindTally: [ValueKind: Int] = [:]
        var distinct: Set<String> = []
        var samples: [String] = []
        var present = 0
        var minimum: Double?
        var maximum: Double?
        var numericCount = 0

        for value in values {
            guard !value.isMissing else { continue }
            present += 1
            kindTally[value.kind, default: 0] += 1

            let text = value.text
            distinct.insert(text)
            if samples.count < examples, !text.isEmpty, !samples.contains(text) {
                samples.append(text)
            }
            if let number = value.numeric {
                numericCount += 1
                minimum = Swift.min(minimum ?? number, number)
                maximum = Swift.max(maximum ?? number, number)
            }
        }

        // Only call a field numeric when every present value is a number. One
        // "n/a" in a column of prices means maths on it would quietly skip a
        // row, and the shape should say so rather than imply it is safe.
        //
        // Booleans are excluded even though they read as 0 and 1. A range of
        // "0 … 1" beside a type of "boolean" tells the reader nothing, and
        // auto-discovered statistics should not fill up with true/false
        // columns. `stats --field ok` still summarises one on request, where
        // the mean is the share that are true.
        let onlyBooleans = kindTally[.boolean] == present
        let allNumeric = present > 0 && numericCount == present && !onlyBooleans

        return FieldShape(
            name: name,
            kinds: kindTally.sorted { ($0.value, $1.key.rawValue) > ($1.value, $0.key.rawValue) }.map(\.key),
            present: present,
            missing: values.count - present,
            distinct: distinct.count,
            examples: samples,
            minimum: allNumeric ? minimum : nil,
            maximum: allNumeric ? maximum : nil
        )
    }
}
