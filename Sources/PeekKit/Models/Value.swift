//
//  Value.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One cell.
///
/// A closed set rather than `Any`, so that a column's kind is a fact the
/// reader establishes once instead of a cast every call site repeats.
public enum Value: Sendable, Equatable {

    case number(Double)
    case string(String)
    case boolean(Bool)
    case null
    case array([Value])
    case object([String: Value])

    /// What this is.
    public var kind: ValueKind {
        switch self {
        case .number: .number
        case .string: .string
        case .boolean: .boolean
        case .null: .null
        case .array: .array
        case .object: .object
        }
    }

    /// The number this is, or the number a string spells.
    ///
    /// CSV has no types: every cell arrives as text, and a column of prices
    /// is a column of strings until somebody reads them as numbers. Doing
    /// that here means `stats` works on a CSV without the caller converting
    /// anything first.
    public var numeric: Double? {
        switch self {
        case .number(let value): value
        case .boolean(let value): value ? 1 : 0
        case .string(let text): Self.parseNumber(text)
        default: nil
        }
    }

    /// The text of this, for grouping and display.
    public var text: String {
        switch self {
        case .number(let value): Self.format(value)
        case .string(let value): value
        case .boolean(let value): value ? "true" : "false"
        case .null: ""
        case .array(let values): "[\(values.count)]"
        case .object(let fields): "{\(fields.count)}"
        }
    }

    /// Whether this counts as absent — null, or the empty string a CSV uses
    /// to mean the same thing.
    public var isMissing: Bool {
        switch self {
        case .null: true
        case .string(let text): text.isEmpty
        default: false
        }
    }

    // MARK: - Building

    /// Wraps whatever `JSONSerialization` produced.
    public init(json: Any) {
        switch json {
        case let number as NSNumber:
            // NSNumber erases Bool into a number; the ObjC type encoding is
            // the only thing that still remembers which it was.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .boolean(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let text as String:
            self = .string(text)
        case let items as [Any]:
            self = .array(items.map(Value.init(json:)))
        case let fields as [String: Any]:
            self = .object(fields.mapValues(Value.init(json:)))
        default:
            self = .null
        }
    }

    // MARK: - Internals

    /// Parses a number the way a spreadsheet column tends to spell one.
    static func parseNumber(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let value = Double(trimmed) { return value }

        // Thousands separators, currency marks and a trailing percent are
        // presentation, not data. A column written "1,234" is still numeric.
        var cleaned = trimmed.replacingOccurrences(of: ",", with: "")
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "$£€¥ "))
        if cleaned.hasSuffix("%"), let value = Double(cleaned.dropLast()) { return value / 100 }
        return Double(cleaned)
    }

    /// Prints a number without the decimal point an integer does not need.
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return String(value) }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }
}

extension Value: Encodable {

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let values): try container.encode(values)
        case .object(let fields): try container.encode(fields)
        }
    }
}
