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
    public static func read(contentsOf url: URL, format: DataFormat? = nil) throws -> Dataset {
        let text = try String(contentsOf: url, encoding: .utf8)
        let chosen = format ?? DataFormat.inferred(fromExtension: url.pathExtension) ?? DataFormat.sniffed(text)
        return try read(text, format: chosen, source: url.lastPathComponent)
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
        }
    }

    /// Reads everything on standard input.
    public static func readStandardInput(format: DataFormat? = nil) throws -> Dataset {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else {
            throw PeekError.unreadable("standard input is not UTF-8")
        }
        return try read(text, format: format, source: "-")
    }
}
