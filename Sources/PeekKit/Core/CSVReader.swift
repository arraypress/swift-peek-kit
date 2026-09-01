//
//  CSVReader.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Turns delimited text into rows.
///
/// A real RFC 4180 parser rather than `split(separator: ",")`, because the
/// separator-splitting version is wrong on the first quoted address it meets
/// and wrong silently: it produces rows of the wrong width that everything
/// downstream then reports confidently.
public enum CSVReader {

    /// Reads delimited text, taking the first line as the header.
    ///
    /// - Parameters:
    ///   - text: The file's contents.
    ///   - delimiter: `,` for CSV, `\t` for TSV.
    public static func rows(from text: String, delimiter: Character = ",") throws -> (rows: [Dataset.Row], fields: [String]) {
        let records = parse(text, delimiter: delimiter)
        guard let header = records.first else { throw PeekError.unreadable("no header row") }

        // Blank and duplicate headers are common in exported spreadsheets and
        // must still address a column, so they are named rather than dropped.
        var used: Set<String> = []
        let fields: [String] = header.enumerated().map { index, name in
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            var candidate = trimmed.isEmpty ? "column\(index + 1)" : trimmed
            var suffix = 2
            while !used.insert(candidate).inserted {
                candidate = "\(trimmed.isEmpty ? "column\(index + 1)" : trimmed)_\(suffix)"
                suffix += 1
            }
            return candidate
        }

        let rows = records.dropFirst().compactMap { record -> Dataset.Row? in
            // A trailing newline yields one empty record; that is not a row.
            guard record.contains(where: { !$0.isEmpty }) else { return nil }
            var row: Dataset.Row = [:]
            for (index, field) in fields.enumerated() {
                row[field] = index < record.count ? .string(record[index]) : .null
            }
            return row
        }
        return (rows, fields)
    }

    // MARK: - Internals

    /// Splits delimited text into records of fields.
    ///
    /// Handles quoted fields, delimiters and newlines inside quotes, and the
    /// doubled quote that escapes a quote.
    ///
    /// Line endings are matched with `isNewline` rather than against `"\n"`.
    /// Swift's `Character` is a grapheme cluster, so a CRLF is **one**
    /// character equal to neither `"\r"` nor `"\n"`: comparing against them
    /// leaves a Windows export as a single unsplit record, and the header
    /// then swallows the whole file.
    static func parse(_ text: String, delimiter: Character) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func nextCharacter() -> Character? {
            if let held = pending { pending = nil; return held }
            return iterator.next()
        }

        while let character = nextCharacter() {
            if inQuotes {
                if character == "\"" {
                    if let following = nextCharacter() {
                        if following == "\"" { field.append("\"") } else { inQuotes = false; pending = following }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }

            switch character {
            case "\"":
                inQuotes = true
            case delimiter:
                record.append(field); field = ""
            case let newline where newline.isNewline:
                record.append(field); field = ""
                records.append(record); record = []
            default:
                field.append(character)
            }
        }

        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records
    }
}
