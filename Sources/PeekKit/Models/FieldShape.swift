//
//  FieldShape.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What one field holds across every row.
public struct FieldShape: Sendable, Encodable, Equatable {

    /// The field's name or dotted path.
    public let name: String

    /// The kinds seen, commonest first.
    public let kinds: [ValueKind]

    /// Rows where the field was present and not empty.
    public let present: Int

    /// Rows where it was absent, null, or an empty string.
    public let missing: Int

    /// How many different values it took.
    public let distinct: Int

    /// A few real values, for recognising the column at a glance.
    public let examples: [String]

    /// Range, when the field is numeric.
    public let minimum: Double?

    /// Range, when the field is numeric.
    public let maximum: Double?

    public init(
        name: String,
        kinds: [ValueKind],
        present: Int,
        missing: Int,
        distinct: Int,
        examples: [String],
        minimum: Double? = nil,
        maximum: Double? = nil
    ) {
        self.name = name
        self.kinds = kinds
        self.present = present
        self.missing = missing
        self.distinct = distinct
        self.examples = examples
        self.minimum = minimum
        self.maximum = maximum
    }

    /// The kind this field mostly is.
    public var kind: ValueKind { kinds.first ?? .null }

    /// Whether every present value is a number, so maths on it is meaningful.
    public var isNumeric: Bool { minimum != nil }
}
