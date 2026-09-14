//
//  Writer.swift
//  PeekKit
//
//  A dataset back out, in a format something else reads.
//

import Foundation
import Yams

/// Writes a ``Dataset`` as CSV, TSV, JSON or NDJSON.
///
/// The point of this is not conversion for its own sake. It is that this
/// package is the only thing on the machine that reads `.xlsx` at all, so a
/// workbook is otherwise a dead end: openable, summarisable, and impossible to
/// hand to anything else.
public enum Writer {

    /// Renders `dataset` as `format`.
    ///
    /// - Parameters:
    ///   - fields: Restrict and order the columns. Names not present are
    ///     ignored rather than emitted empty, and an empty result throws —
    ///     silently writing a file of blank rows is the worst outcome here.
    /// - Throws: ``PeekError/cannotWrite(_:)`` for a read-only format,
    ///   ``PeekError/noSuchField(_:available:)`` when nothing matches.
    public static func write(
        _ dataset: Dataset,
        as format: DataFormat,
        fields: [String]? = nil
    ) throws -> String {

        let columns = try resolve(fields, in: dataset)

        switch format {
        case .csv:    return delimited(dataset, columns: columns, separator: ",")
        case .tsv:    return delimited(dataset, columns: columns, separator: "\t")
        case .json:   return try json(dataset, columns: columns, pretty: true)
        case .ndjson: return try json(dataset, columns: columns, pretty: false)
        case .yaml:   return try yaml(dataset, columns: columns)
        case .toml:   throw PeekError.cannotWrite("toml")
        case .xlsx:   throw PeekError.cannotWrite("xlsx")
        }
    }

    /// The columns to write, in order.
    private static func resolve(_ fields: [String]?, in dataset: Dataset) throws -> [String] {
        guard let fields, !fields.isEmpty else { return dataset.fields }
        let available = Set(dataset.fields)
        let kept = fields.filter { available.contains($0) }
        guard !kept.isEmpty else {
            throw PeekError.noSuchField(fields.joined(separator: ", "), available: dataset.fields)
        }
        return kept
    }

    // MARK: YAML

    /// Rows as a YAML sequence of mappings.
    ///
    /// Safe in this direction, and measured: JSON to YAML and back was
    /// lossless over every awkward case — `"NO"`, `"yes"`, `"22:22"`,
    /// `"0777"`, emoji, escapes, empty containers and keys containing
    /// spaces, colons and `#`. Yams quotes what needs quoting, so nothing
    /// reads back as a boolean or a number that was not one.
    ///
    /// TOML is deliberately not written. Its top level is a table, so rows
    /// would have to become an array-of-tables, and a caller wanting TOML
    /// almost always wants a hand-shaped config rather than a dump of rows.
    /// Reading it is the useful half.
    private static func yaml(_ dataset: Dataset, columns: [String]) throws -> String {
        let objects: [Any] = dataset.rows.map { row in
            var out: [String: Any] = [:]
            for column in columns {
                guard let value = Dataset.value(at: column, in: row), !value.isMissing else { continue }
                out[column] = native(value)
            }
            return out
        }
        do {
            return try Yams.dump(object: objects)
        } catch {
            throw PeekError.cannotWrite("yaml: \(error.localizedDescription)")
        }
    }

    /// Yams cannot represent Foundation's bridged types — `NSString`,
    /// `NSNumber` and `NSNull` all throw "Failed to represent", including a
    /// bare string. Everything has to be native Swift first.
    private static func native(_ value: Value) -> Any {
        switch value {
        case .string(let text): text
        case .number(let number): number == number.rounded() && abs(number) < 9e15 ? Int(number) : number
        case .boolean(let flag): flag
        case .null: NSNull()
        case .array(let items): items.map(native)
        case .object(let fields): fields.mapValues(native)
        }
    }

    // MARK: Delimited

    private static func delimited(
        _ dataset: Dataset, columns: [String], separator: String
    ) -> String {
        var lines = [columns.map { escape($0, separator: separator) }.joined(separator: separator)]
        for row in dataset.rows {
            lines.append(columns.map { column in
                escape(cell(Dataset.value(at: column, in: row)), separator: separator)
            }.joined(separator: separator))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One cell as text.
    ///
    /// Deliberately NOT `Value.text`, which renders an array as `[3]` and an
    /// object as `{2}`. Those are display summaries for a terminal; writing
    /// them to a file would throw the data away and look like it worked.
    /// Nested values are serialised as compact JSON, which round-trips.
    private static func cell(_ value: Value?) -> String {
        guard let value else { return "" }
        switch value {
        case .array, .object:
            guard let data = try? JSONSerialization.data(withJSONObject: plain(value)),
                  let text = String(data: data, encoding: .utf8) else { return value.text }
            return text
        default:
            return value.text
        }
    }

    /// RFC 4180: quote when the cell holds the separator, a quote or a
    /// newline, and double any interior quote.
    ///
    /// `"\r\n"` is ONE Swift `Character` and equal to neither `"\r"` nor
    /// `"\n"`, which is why this asks `isNewline` rather than comparing.
    private static func escape(_ text: String, separator: String) -> String {
        let needsQuoting = text.contains(separator)
            || text.contains("\"")
            || text.contains(where: \.isNewline)
        guard needsQuoting else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: JSON

    private static func json(
        _ dataset: Dataset, columns: [String], pretty: Bool
    ) throws -> String {
        let objects = dataset.rows.map { row in
            columns.reduce(into: [String: Any]()) { object, column in
                object[column] = plain(Dataset.value(at: column, in: row) ?? .null)
            }
        }

        if pretty {
            let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            guard let data = try? JSONSerialization.data(withJSONObject: objects, options: options),
                  let text = String(data: data, encoding: .utf8) else {
                throw PeekError.cannotWrite("json")
            }
            return text + "\n"
        }

        // One object per line, and no pretty printing — a pretty-printed
        // NDJSON line is a contradiction that breaks every reader of it.
        var lines: [String] = []
        for object in objects {
            guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]),
                  let text = String(data: data, encoding: .utf8) else {
                throw PeekError.cannotWrite("ndjson")
            }
            lines.append(text)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A ``Value`` as the Foundation types `JSONSerialization` accepts.
    private static func plain(_ value: Value) -> Any {
        switch value {
        case .number(let number): return number
        case .string(let text): return text
        case .boolean(let flag): return flag
        case .null: return NSNull()
        case .array(let values): return values.map(plain)
        case .object(let fields): return fields.mapValues(plain)
        }
    }
}
