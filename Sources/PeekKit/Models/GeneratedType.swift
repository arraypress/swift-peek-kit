//
//  GeneratedType.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What a field became, once the shape was read.
///
/// One level above `ValueKind`, which is deliberately coarse: a generated
/// type has to separate whole numbers from fractional ones and name the
/// types it nests, because a declaration cannot say "number".
public indirect enum GeneratedFieldType: Sendable, Equatable {

    /// Every observed value was a whole number.
    case integer

    /// At least one observed value was fractional.
    case double

    case string
    case boolean

    /// A list of something.
    case array(GeneratedFieldType)

    /// A nested object, by generated type name.
    case object(String)

    /// A string field whose every distinct value was observed, so the set is
    /// known rather than guessed.
    case enumeration(name: String, cases: [String])

    /// The field held more than one kind, or nothing at all, and no single
    /// declaration is honest about it.
    case unknown
}

/// One field of a generated declaration.
public struct GeneratedField: Sendable, Equatable {

    /// The name as the data spells it — the wire name.
    public let wireName: String

    /// What it holds.
    public let type: GeneratedFieldType

    /// Whether the field ever went missing, so the declaration must allow it.
    public let isOptional: Bool

    public init(wireName: String, type: GeneratedFieldType, isOptional: Bool) {
        self.wireName = wireName
        self.type = type
        self.isOptional = isOptional
    }
}

/// A declaration to emit.
public struct GeneratedType: Sendable, Equatable {

    /// The type's name, already in the shape a type name takes.
    public let name: String

    /// Its fields, in the order the data presented them.
    public let fields: [GeneratedField]

    public init(name: String, fields: [GeneratedField]) {
        self.name = name
        self.fields = fields
    }
}
