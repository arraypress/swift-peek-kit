//
//  Comparison.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Compares two datasets row by row.
public enum Comparison {

    /// What changed between `before` and `after`, matched on a key field.
    ///
    /// The key is what makes this a diff rather than a text comparison: two
    /// runs of the same tool emit the same rows in a possibly different
    /// order, and only a stable identifier says which row is which. Rows
    /// whose key repeats are compared in the order they appear.
    ///
    /// - Parameters:
    ///   - before: The earlier dataset.
    ///   - after: The later one.
    ///   - key: The field identifying a row.
    ///   - fields: Fields to compare; empty means every field they share.
    ///   - tolerance: Numeric differences at or below this are not changes.
    ///     Measured data is noisy, and a diff that reports every last digit
    ///     of float drift buries the changes that mean something.
    public static func diff(
        before: Dataset,
        after: Dataset,
        key: String,
        fields: [String] = [],
        tolerance: Double = 0
    ) throws -> [RowChange] {
        let old = try index(before, by: key)
        let new = try index(after, by: key)

        let compared = fields.isEmpty
            ? before.fields.filter { after.fields.contains($0) && $0 != key }
            : fields

        var changes: [RowChange] = []

        for identifier in new.keys.sorted() where old[identifier] == nil {
            changes.append(RowChange(key: identifier, kind: .added))
        }
        for identifier in old.keys.sorted() where new[identifier] == nil {
            changes.append(RowChange(key: identifier, kind: .removed))
        }

        for identifier in old.keys.sorted() {
            guard let oldRow = old[identifier], let newRow = new[identifier] else { continue }
            var differences: [FieldChange] = []

            for field in compared {
                let a = Dataset.value(at: field, in: oldRow) ?? .null
                let b = Dataset.value(at: field, in: newRow) ?? .null
                guard let change = compare(field: field, a, b, tolerance: tolerance) else { continue }
                differences.append(change)
            }

            if !differences.isEmpty {
                changes.append(RowChange(key: identifier, kind: .changed, fields: differences))
            }
        }
        return changes
    }

    // MARK: - Internals

    /// One field's difference, or nil when it did not meaningfully move.
    static func compare(field: String, _ a: Value, _ b: Value, tolerance: Double) -> FieldChange? {
        if let x = a.numeric, let y = b.numeric {
            let delta = y - x
            guard abs(delta) > tolerance else { return nil }
            return FieldChange(field: field, before: a.text, after: b.text, delta: delta)
        }
        guard a.text != b.text else { return nil }
        return FieldChange(field: field, before: a.text, after: b.text)
    }

    /// Rows by key, first occurrence winning.
    static func index(_ dataset: Dataset, by key: String) throws -> [String: Dataset.Row] {
        var indexed: [String: Dataset.Row] = [:]
        for row in dataset.rows {
            guard let value = Dataset.value(at: key, in: row), !value.isMissing else { continue }
            let identifier = value.text
            if indexed[identifier] == nil { indexed[identifier] = row }
        }
        guard !indexed.isEmpty else {
            throw PeekError.noSuchField(key, available: dataset.paths())
        }
        return indexed
    }
}
