//
//  JSONReader.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Turns JSON and NDJSON into rows.
public enum JSONReader {

    /// Reads a JSON document.
    ///
    /// Accepts the three shapes data actually arrives in: an array of
    /// objects, a single object, and an object wrapping the array under some
    /// key. The last is worth handling rather than refusing — an enormous
    /// number of APIs return `{"results": [...]}` and making the caller dig
    /// it out first is the kind of friction this tool exists to remove.
    public static func rows(from text: String) throws -> [Dataset.Row] {
        guard let data = salvage(text) else {
            throw PeekError.unreadable("no JSON value found")
        }
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return rows(fromParsed: object)
    }

    /// Reads one JSON document per line.
    ///
    /// Blank lines are skipped and a line that will not parse is skipped
    /// rather than fatal: NDJSON is a streaming format and a truncated last
    /// line is the normal way a capture ends.
    public static func ndjsonRows(from text: String) -> [Dataset.Row] {
        var rows: [Dataset.Row] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            else { continue }
            rows.append(contentsOf: self.rows(fromParsed: object))
        }
        return rows
    }

    // MARK: - Internals

    /// Normalises a parsed JSON value into rows.
    static func rows(fromParsed object: Any) -> [Dataset.Row] {
        switch Value(json: object) {
        case .array(let items):
            return items.map { item in
                if case .object(let fields) = item { return fields }
                // An array of bare values is still a column; name it so it
                // can be summarised like any other.
                return ["value": item]
            }
        case .object(let fields):
            // One object wrapping exactly one array of objects is a envelope,
            // not a row. Unwrap it; anything else is a single row.
            let arrays = fields.filter { if case .array = $0.value { return true } else { return false } }
            if arrays.count == 1, case .array(let items) = arrays.first!.value,
               items.contains(where: { if case .object = $0 { return true } else { return false } }) {
                return items.map { item in
                    if case .object(let inner) = item { return inner }
                    return ["value": item]
                }
            }
            return [fields]
        case let single:
            return [["value": single]]
        }
    }

    /// Finds the first complete JSON value in text that may hold other things.
    ///
    /// Tool output is rarely clean. A plug-in writes to stderr, a framework
    /// logs a warning, a shell prints a banner — and the JSON sits somewhere
    /// in the middle. Every ad-hoc analysis script starts by finding the
    /// first `[` and decoding from there, so that behaviour belongs in the
    /// reader rather than in every caller.
    static func salvage(_ text: String) -> Data? {
        if let data = text.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
            return data
        }

        let characters = Array(text)
        for (index, character) in characters.enumerated() where character == "[" || character == "{" {
            guard let end = balancedEnd(of: characters, from: index) else { continue }
            let candidate = String(characters[index...end])
            if let data = candidate.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return data
            }
        }
        return nil
    }

    /// The index closing the bracket opened at `start`, honouring strings and
    /// escapes so that a bracket inside a string value does not count.
    static func balancedEnd(of characters: [Character], from start: Int) -> Int? {
        let opening = characters[start]
        let closing: Character = opening == "[" ? "]" : "}"
        var depth = 0
        var inString = false
        var escaped = false

        for index in start..<characters.count {
            let character = characters[index]
            if escaped { escaped = false; continue }
            if character == "\\" , inString { escaped = true; continue }
            if character == "\"" { inString.toggle(); continue }
            guard !inString else { continue }
            if character == opening { depth += 1 }
            else if character == closing {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }
}
