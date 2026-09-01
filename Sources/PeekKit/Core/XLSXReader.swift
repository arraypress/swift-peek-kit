//
//  XLSXReader.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import CoreXLSX
import Foundation

/// Turns an Excel workbook into rows.
///
/// Reading only. Writing an `.xlsx` means assembling OOXML parts by hand, and
/// the output half of this problem is already solved: every tool here can
/// emit CSV, which spreadsheets open.
public enum XLSXReader {

    /// Reads one worksheet, taking the first row as the header.
    ///
    /// - Parameters:
    ///   - url: The workbook.
    ///   - sheet: A sheet name, or a 1-based index as text. The first sheet
    ///     when absent.
    public static func read(contentsOf url: URL, sheet: String? = nil) throws -> Dataset {
        guard let file = XLSXFile(filepath: url.path) else {
            throw PeekError.unreadable("\(url.lastPathComponent) is not a readable workbook")
        }

        let paths = try file.parseWorksheetPaths()
        guard !paths.isEmpty else { throw PeekError.empty(url.lastPathComponent) }

        let names = (try? file.parseWorkbooks())?
            .flatMap { $0.sheets.items }
            .compactMap(\.name) ?? []

        let index = try resolve(sheet, names: names, count: paths.count)
        let shared = try? file.parseSharedStrings()
        let worksheet = try file.parseWorksheet(at: paths[index])
        let (rows, fields) = try rows(in: worksheet, shared: shared)

        return Dataset(rows: rows, fields: fields, source: url.lastPathComponent, format: .xlsx)
    }

    /// The sheet names in a workbook, for reporting and for choosing.
    public static func sheetNames(contentsOf url: URL) -> [String] {
        guard let file = XLSXFile(filepath: url.path) else { return [] }
        return (try? file.parseWorkbooks())?.flatMap { $0.sheets.items }.compactMap(\.name) ?? []
    }

    // MARK: - Internals

    /// Turns a worksheet into rows, keyed by the header row.
    static func rows(in worksheet: Worksheet, shared: SharedStrings?) throws -> ([Dataset.Row], [String]) {
        let sheetRows = worksheet.data?.rows ?? []
        guard let header = sheetRows.first else { throw PeekError.unreadable("the sheet has no header row") }

        // Columns are addressed by letter, and a row simply omits a cell it
        // has no value for -- row 3 of a real export jumps from B to D. So
        // the header is a letter-to-name map rather than a list, and a body
        // row is placed by letter. Zipping the two by position would slide
        // every value after a gap into the wrong column.
        var namesByColumn: [String: String] = [:]
        var fields: [String] = []
        var used: Set<String> = []

        for cell in header.cells {
            let column = cell.reference.column.value
            let raw = text(of: cell, shared: shared).trimmingCharacters(in: .whitespacesAndNewlines)
            var name = raw.isEmpty ? "column\(column)" : raw
            var suffix = 2
            while !used.insert(name).inserted {
                name = "\(raw.isEmpty ? "column\(column)" : raw)_\(suffix)"
                suffix += 1
            }
            namesByColumn[column] = name
            fields.append(name)
        }

        let body = sheetRows.dropFirst().compactMap { sheetRow -> Dataset.Row? in
            var row: Dataset.Row = [:]
            for field in fields { row[field] = .null }
            var any = false
            for cell in sheetRow.cells {
                guard let name = namesByColumn[cell.reference.column.value] else { continue }
                let value = value(of: cell, shared: shared)
                if !value.isMissing { any = true }
                row[name] = value
            }
            return any ? row : nil
        }
        return (body, fields)
    }

    /// One cell as a typed value.
    ///
    /// A workbook knows its own types, unlike a CSV, so a number arrives as a
    /// number rather than as text that happens to parse. Dates are the
    /// exception and are left as the serial number they are stored as:
    /// resolving one needs the cell's format record, and a date silently
    /// rendered under the wrong epoch is worse than a visible number.
    static func value(of cell: Cell, shared: SharedStrings?) -> Value {
        let raw = text(of: cell, shared: shared)
        guard !raw.isEmpty else { return .null }

        switch cell.type {
        case .sharedString, .inlineStr, .string:
            return .string(raw)
        case .bool:
            return .boolean(raw == "1" || raw.lowercased() == "true")
        case .error:
            // #DIV/0! and friends. Not a value, and not worth pretending is.
            return .null
        default:
            return Double(raw).map(Value.number) ?? .string(raw)
        }
    }

    /// One cell's text, resolving a shared string when that is what it is.
    static func text(of cell: Cell, shared: SharedStrings?) -> String {
        if let shared, let resolved = cell.stringValue(shared) { return resolved }
        if let inline = cell.inlineString?.text { return inline }
        return cell.value ?? ""
    }

    /// Which worksheet was asked for.
    static func resolve(_ sheet: String?, names: [String], count: Int) throws -> Int {
        guard let sheet, !sheet.isEmpty else { return 0 }

        if let match = names.firstIndex(where: { $0.caseInsensitiveCompare(sheet) == .orderedSame }),
           match < count {
            return match
        }
        // A bare number means the nth sheet, counting the way a spreadsheet's
        // own tabs are counted rather than the way an array is.
        if let ordinal = Int(sheet), ordinal >= 1, ordinal <= count {
            return ordinal - 1
        }
        throw PeekError.noSuchSheet(sheet, available: names)
    }
}
