//
//  TOMLReader.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation
import TOMLKit

/// Turns TOML into rows.
public enum TOMLReader {

    /// Options that make toml++ emit **valid** JSON.
    ///
    /// Its defaults are TOML-oriented and are passed to every format, so hex,
    /// octal and binary integers go out verbatim (`"weight": 0xDEADBEEF`) and
    /// non-finite floats go out bare (`Infinity`, `NaN`). None of that is
    /// JSON. Measured: one file in 195 exposed it — rare enough to pass
    /// casual testing, common enough to be real.
    /// A computed property rather than a stored one: `FormatOptions` is an
    /// OptionSet from a module without Sendable annotations, and building it
    /// per call costs nothing.
    static var jsonSafe: FormatOptions { [.quoteDateAndTimes, .quoteInfinitesAndNaNs] }

    public static func rows(from text: String) throws -> (rows: [Dataset.Row], fields: [String]?) {
        let table: TOMLTable
        do {
            table = try TOMLTable(string: text)
        } catch {
            throw PeekError.unreadable("TOML: \(error.localizedDescription)")
        }

        let json = table.convert(to: .json, options: jsonSafe)
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else {
            throw PeekError.unreadable("TOML converted to JSON this could not read back")
        }

        // toml++ stores tables as a sorted map, so key order is alphabetical
        // and cannot be turned off. Saying so beats implying the file's order
        // survived — unlike YAML and CSV, where it does.
        return (JSONReader.rows(fromParsed: object), Array(table.keys))
    }
}
