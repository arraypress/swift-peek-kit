//
//  WriterTests.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//
//  Round trips, and the escaping that a naive join gets wrong.
//

import XCTest
@testable import PeekKit

final class WriterTests: XCTestCase {

    private func dataset(_ rows: [[String: Value]], fields: [String]) -> Dataset {
        Dataset(rows: rows, fields: fields, source: "test", format: .json)
    }

    // MARK: Round trips

    func testCSVRoundTrips() throws {
        let original = dataset([
            ["id": .string("1"), "name": .string("widget"), "price": .number(19.98)],
            ["id": .string("2"), "name": .string("gizmo"), "price": .number(5)],
        ], fields: ["id", "name", "price"])

        let csv = try Writer.write(original, as: .csv)
        let back = try DatasetReader.read(csv, format: .csv)

        XCTAssertEqual(back.count, 2)
        XCTAssertEqual(back.fields, ["id", "name", "price"])
        XCTAssertEqual(back.column("price").compactMap(\.numeric), [19.98, 5])
    }

    func testNDJSONRoundTripsAndKeepsTypes() throws {
        // CSV loses types; NDJSON must not.
        let original = dataset([
            ["n": .number(42), "flag": .boolean(true), "nothing": .null],
        ], fields: ["n", "flag", "nothing"])

        let text = try Writer.write(original, as: .ndjson)
        let back = try DatasetReader.read(text, format: .ndjson)

        XCTAssertEqual(back.column("n").first?.kind, .number)
        XCTAssertEqual(back.column("flag").first?.kind, .boolean)
        XCTAssertEqual(back.column("nothing").first?.kind, .null)
    }

    func testNDJSONIsOneObjectPerLine() throws {
        let text = try Writer.write(dataset([
            ["a": .number(1)], ["a": .number(2)], ["a": .number(3)],
        ], fields: ["a"]), as: .ndjson)
        // A pretty-printed NDJSON line is a contradiction that breaks every
        // reader of it.
        XCTAssertEqual(text.split(separator: "\n").count, 3)
    }

    // MARK: Escaping

    func testCellsHoldingTheSeparatorAreQuoted() throws {
        let csv = try Writer.write(dataset([
            ["address": .string("221B Baker Street, London")],
        ], fields: ["address"]), as: .csv)
        XCTAssertTrue(csv.contains("\"221B Baker Street, London\""), csv)
        XCTAssertEqual(try DatasetReader.read(csv, format: .csv).column("address").first?.text,
                       "221B Baker Street, London")
    }

    func testInteriorQuotesAreDoubled() throws {
        let csv = try Writer.write(dataset([
            ["quote": .string("she said \"no\"")],
        ], fields: ["quote"]), as: .csv)
        XCTAssertTrue(csv.contains("\"\"no\"\""), csv)
        XCTAssertEqual(try DatasetReader.read(csv, format: .csv).column("quote").first?.text,
                       "she said \"no\"")
    }

    func testNewlinesInsideACellSurvive() throws {
        // "\r\n" is ONE Swift Character and equal to neither "\r" nor "\n",
        // which is why the check asks isNewline rather than comparing.
        let csv = try Writer.write(dataset([
            ["note": .string("line one\nline two")],
        ], fields: ["note"]), as: .csv)
        XCTAssertEqual(try DatasetReader.read(csv, format: .csv).column("note").first?.text,
                       "line one\nline two")
    }

    func testTSVUsesTabs() throws {
        let tsv = try Writer.write(dataset([
            ["a": .string("x"), "b": .string("y")],
        ], fields: ["a", "b"]), as: .tsv)
        XCTAssertTrue(tsv.contains("a\tb"), tsv)
    }

    // MARK: Nesting

    func testNestedValuesAreSerialisedNotSummarised() throws {
        // Value.text renders an array as "[3]" — a display summary. Writing
        // that to a file throws the data away and looks like it worked.
        let csv = try Writer.write(dataset([
            ["codes": .array([.string("a"), .string("b")])],
        ], fields: ["codes"]), as: .csv)
        XCTAssertFalse(csv.contains("[2]"), csv)
        XCTAssertTrue(csv.contains("a"), csv)
        XCTAssertTrue(csv.contains("b"), csv)
    }

    func testObjectsSurviveJSON() throws {
        let text = try Writer.write(dataset([
            ["meta": .object(["k": .string("v")])],
        ], fields: ["meta"]), as: .json)
        XCTAssertTrue(text.contains("\"k\""), text)
        XCTAssertTrue(text.contains("\"v\""), text)
    }

    // MARK: Columns

    func testFieldsSelectAndOrder() throws {
        let csv = try Writer.write(dataset([
            ["a": .string("1"), "b": .string("2"), "c": .string("3")],
        ], fields: ["a", "b", "c"]), as: .csv, fields: ["c", "a"])
        XCTAssertTrue(csv.hasPrefix("c,a"), csv)
        XCTAssertFalse(csv.contains("b"), csv)
    }

    func testAMissingRowValueBecomesAnEmptyCell() throws {
        let csv = try Writer.write(dataset([
            ["a": .string("1"), "b": .string("2")],
            ["a": .string("3")],
        ], fields: ["a", "b"]), as: .csv)
        XCTAssertTrue(csv.hasSuffix("3,\n"), csv)
    }

    func testNoMatchingFieldThrowsRatherThanWritingBlankRows() {
        // A file of empty rows is the worst outcome: it looks like a result.
        XCTAssertThrowsError(try Writer.write(dataset([["a": .string("1")]], fields: ["a"]),
                                              as: .csv, fields: ["nope"]))
    }

    func testXLSXIsRefusedNotFaked() {
        XCTAssertThrowsError(try Writer.write(dataset([["a": .string("1")]], fields: ["a"]),
                                              as: .xlsx)) { error in
            guard case PeekError.cannotWrite = error else {
                return XCTFail("expected cannotWrite, got \(error)")
            }
        }
    }
}
