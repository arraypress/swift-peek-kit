//
//  RowChange.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What happened to one row between two datasets.
public struct RowChange: Sendable, Encodable, Equatable {

    /// What kind of change it was.
    public enum Kind: String, Sendable, Encodable, CaseIterable {
        case added
        case removed
        case changed
    }

    /// The key identifying the row.
    public let key: String

    /// What happened.
    public let kind: Kind

    /// Field by field, what it was and what it became. Empty for added and
    /// removed rows, where the whole row is the change.
    public let fields: [FieldChange]

    public init(key: String, kind: Kind, fields: [FieldChange] = []) {
        self.key = key
        self.kind = kind
        self.fields = fields
    }
}

/// One field that differs between two versions of a row.
public struct FieldChange: Sendable, Encodable, Equatable {

    public let field: String
    public let before: String
    public let after: String

    /// The numeric movement, when both sides are numbers. Absent for text,
    /// where "how much did it change" has no answer.
    public let delta: Double?

    public init(field: String, before: String, after: String, delta: Double? = nil) {
        self.field = field
        self.before = before
        self.after = after
        self.delta = delta
    }
}
