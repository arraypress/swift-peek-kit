//
//  ReadingTests.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//
//  Getting the bytes in is where this library earns its keep, so the reading
//  tests are the adversarial ones: quoted commas, embedded newlines, CRLF,
//  duplicate headers, and JSON buried in the noise a real tool writes around
//  it. Splitting on commas passes none of these.
//

import XCTest
@testable import PeekKit

final class ReadingTests: XCTestCase {

    // MARK: Delimited text

    func testAQuotedFieldKeepsItsCommas() throws {
        let (rows, fields) = try CSVReader.rows(from: "name,address\nAda,\"12 High St, Bath\"\n")
        XCTAssertEqual(fields, ["name", "address"])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["address"], .string("12 High St, Bath"))
    }

    func testAQuotedFieldKeepsItsNewlines() throws {
        let (rows, _) = try CSVReader.rows(from: "id,note\n1,\"line one\nline two\"\n")
        XCTAssertEqual(rows.count, 1, "the newline is inside quotes and does not end the record")
        XCTAssertEqual(rows[0]["note"], .string("line one\nline two"))
    }

    func testADoubledQuoteIsOneQuote() throws {
        let (rows, _) = try CSVReader.rows(from: "id,said\n1,\"she said \"\"no\"\"\"\n")
        XCTAssertEqual(rows[0]["said"], .string("she said \"no\""))
    }

    func testCarriageReturnsDoNotSurviveIntoTheData() throws {
        let (rows, fields) = try CSVReader.rows(from: "a,b\r\n1,2\r\n")
        XCTAssertEqual(fields, ["a", "b"])
        XCTAssertEqual(rows[0]["b"], .string("2"), "a Windows export must not leave \\r on the last field")
    }

    func testATrailingNewlineIsNotAnEmptyRow() throws {
        let (rows, _) = try CSVReader.rows(from: "a\n1\n2\n")
        XCTAssertEqual(rows.count, 2)
    }

    func testBlankAndRepeatedHeadersStillAddressAColumn() throws {
        let (rows, fields) = try CSVReader.rows(from: "name,,name\nx,y,z\n")
        XCTAssertEqual(fields, ["name", "column2", "name_2"], "every column has to be reachable")
        XCTAssertEqual(rows[0]["name_2"], .string("z"))
    }

    func testTabsSeparateATSV() throws {
        let dataset = try DatasetReader.read("a\tb\n1\t2\n")
        XCTAssertEqual(dataset.format, .tsv)
        XCTAssertEqual(dataset.rows[0]["b"], .string("2"))
    }

    // MARK: Sniffing

    func testFormatIsRecognisedFromContent() {
        XCTAssertEqual(DataFormat.sniffed("[{\"a\":1}]"), .json)
        XCTAssertEqual(DataFormat.sniffed("{\"a\":1}"), .json)
        XCTAssertEqual(DataFormat.sniffed("{\"a\":1}\n{\"a\":2}"), .ndjson)
        XCTAssertEqual(DataFormat.sniffed("a,b\n1,2"), .csv)
        XCTAssertEqual(DataFormat.sniffed("a\tb\n1\t2"), .tsv)
    }

    func testAnExtensionIsBelievedWhenThereIsOne() {
        XCTAssertEqual(DataFormat.inferred(fromExtension: "jsonl"), .ndjson)
        XCTAssertEqual(DataFormat.inferred(fromExtension: "CSV"), .csv)
        XCTAssertNil(DataFormat.inferred(fromExtension: "txt"))
    }

    // MARK: JSON

    func testJSONBuriedInToolNoiseIsStillFound() throws {
        // The case this library exists for. A plug-in logs to stdout, a
        // framework warns, and the payload sits in the middle of it.
        let noisy = """
            CFData warning: something the audio unit felt strongly about
            [{"file":"a.fxp","peak":0.5},{"file":"b.fxp","peak":1.2}]
            done in 16.4s
            """
        let dataset = try DatasetReader.read(noisy, format: .json)
        XCTAssertEqual(dataset.count, 2)
        XCTAssertEqual(dataset.rows[1]["file"], .string("b.fxp"))
    }

    func testABracketInsideAStringDoesNotEndTheValue() throws {
        let noisy = "log line\n[{\"note\":\"an [unclosed bracket\"}]\ntrailing"
        let dataset = try DatasetReader.read(noisy, format: .json)
        XCTAssertEqual(dataset.count, 1)
        XCTAssertEqual(dataset.rows[0]["note"], .string("an [unclosed bracket"))
    }

    func testAnEnvelopeAroundTheArrayIsUnwrapped() throws {
        let dataset = try DatasetReader.read("{\"results\":[{\"a\":1},{\"a\":2}],\"total\":2}")
        XCTAssertEqual(dataset.count, 2, "{results: [...]} is an envelope, not a single row")
    }

    func testASingleObjectIsOneRow() throws {
        let dataset = try DatasetReader.read("{\"a\":1,\"b\":2}")
        XCTAssertEqual(dataset.count, 1)
    }

    func testAnArrayOfBareValuesIsStillAColumn() throws {
        let dataset = try DatasetReader.read("[1,2,3]")
        XCTAssertEqual(dataset.count, 3)
        XCTAssertEqual(dataset.rows[0]["value"], .number(1))
    }

    func testNDJSONSkipsABrokenLastLine() throws {
        let dataset = try DatasetReader.read("{\"a\":1}\n{\"a\":2}\n{\"a\":", format: .ndjson)
        XCTAssertEqual(dataset.count, 2, "a truncated line is how a stream normally ends")
    }

    func testUnreadableBytesAreRefused() {
        XCTAssertThrowsError(try DatasetReader.read("not data at all", format: .json))
    }
}
