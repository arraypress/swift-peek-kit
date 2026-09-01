//
//  DatasetReader.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Reads a dataset from a file, a pipe, or a string.
public enum DatasetReader {

    /// Reads a file, choosing the format from its content.
    ///
    /// - Parameters:
    ///   - url: The file to read.
    ///   - format: A format to force, when the caller knows better than the
    ///     sniffer does.
    ///   - sheet: Which worksheet, for a workbook. Ignored otherwise.
    public static func read(
        contentsOf url: URL,
        format: DataFormat? = nil,
        sheet: String? = nil
    ) throws -> Dataset {
        let data = try Data(contentsOf: url)

        // Bytes decide before text does. A workbook is a zip, and trying to
        // decode one as UTF-8 loses the useful answer before any sniffing.
        let chosen = format
            ?? DataFormat.sniffed(data: data)
            ?? DataFormat.inferred(fromExtension: url.pathExtension)

        if chosen == .xlsx {
            return try XLSXReader.read(contentsOf: url, sheet: sheet)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw PeekError.unreadable("\(url.lastPathComponent) is not UTF-8 text")
        }
        return try read(text, format: chosen ?? DataFormat.sniffed(text), source: url.lastPathComponent)
    }

    /// Reads text already in hand.
    public static func read(_ text: String, format: DataFormat? = nil, source: String? = nil) throws -> Dataset {
        let chosen = format ?? DataFormat.sniffed(text)

        switch chosen {
        case .json:
            return Dataset(rows: try JSONReader.rows(from: text), source: source, format: .json)
        case .ndjson:
            return Dataset(rows: JSONReader.ndjsonRows(from: text), source: source, format: .ndjson)
        case .csv, .tsv:
            let (rows, fields) = try CSVReader.rows(from: text, delimiter: chosen == .tsv ? "\t" : ",")
            return Dataset(rows: rows, fields: fields, source: source, format: chosen)
        case .xlsx:
            // A workbook is a file, not a string; the caller has to hand over
            // bytes or a path.
            throw PeekError.unreadable("a workbook cannot be read from text")
        }
    }

    /// Reads everything on standard input.
    ///
    /// A workbook is spooled to a temporary file first, because the format is
    /// a zip and its readers seek: they cannot work from a pipe. That is an
    /// implementation detail rather than a restriction on the caller, who
    /// should be able to pipe whatever they have.
    public static func readStandardInput(format: DataFormat? = nil, sheet: String? = nil) throws -> Dataset {
        let data = FileHandle.standardInput.readDataToEndOfFile()

        if format == .xlsx || DataFormat.sniffed(data: data) == .xlsx {
            let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("peek-\(UUID().uuidString).xlsx")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try data.write(to: temporary)
            var dataset = try XLSXReader.read(contentsOf: temporary, sheet: sheet)
            dataset = Dataset(rows: dataset.rows, fields: dataset.fields, source: "-", format: .xlsx)
            return dataset
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw PeekError.unreadable("standard input is not UTF-8")
        }
        return try read(text, format: format, source: "-")
    }
}
