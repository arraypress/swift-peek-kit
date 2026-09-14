//
//  ConfigFormatTests.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//
//  YAML and TOML. Most of this is not "does it parse" — both libraries do
//  that well — but the scalar resolution, which is where stock YAML 1.1
//  silently corrupts ordinary data.
//

import XCTest
@testable import PeekKit

final class ConfigFormatTests: XCTestCase {

    private func first(_ text: String, format: DataFormat) throws -> Dataset.Row {
        let dataset = try DatasetReader.read(text, format: format)
        return try XCTUnwrap(dataset.rows.first)
    }

    // MARK: - YAML 1.1 would get these wrong

    func testTheNorwayProblemIsFixed() throws {
        // Stock Yams reads `NO` as false. A country code is not a boolean.
        let row = try first("country: NO\nother: yes\nthird: off", format: .yaml)
        XCTAssertEqual(row["country"], .string("NO"))
        XCTAssertEqual(row["other"], .string("yes"))
        XCTAssertEqual(row["third"], .string("off"))
    }

    func testSexagesimalAndOctalAreNotApplied() throws {
        // `22:22` is 1342 in YAML 1.1, and `0777` is 511.
        let row = try first("at: 22:22\nmode: 0777", format: .yaml)
        XCTAssertEqual(row["at"], .string("22:22"))
        XCTAssertEqual(row["mode"], .string("0777"),
                       "the float rule has to be replaced too, or this arrives as 777.0")
    }

    func testDatesStayTextSoTheDocumentCanBeEncoded() throws {
        // Resolved as a Date, the row becomes unencodable as JSON.
        let row = try first("released: 2024-01-01", format: .yaml)
        XCTAssertEqual(row["released"], .string("2024-01-01"))
    }

    func testRealBooleansAndNumbersStillWork() throws {
        let row = try first("a: true\nb: false\nc: 42\nd: -7\ne: 1.5\nf: null", format: .yaml)
        XCTAssertEqual(row["a"], .boolean(true))
        XCTAssertEqual(row["b"], .boolean(false))
        XCTAssertEqual(row["c"], .number(42))
        XCTAssertEqual(row["d"], .number(-7))
        XCTAssertEqual(row["e"], .number(1.5))
        XCTAssertTrue(row["f"]?.isMissing ?? false)
    }

    // MARK: - Shapes

    func testASequenceOfMappingsBecomesRows() throws {
        let dataset = try DatasetReader.read("""
            - name: a
              size: 1
            - name: b
              size: 2
            """, format: .yaml)
        XCTAssertEqual(dataset.count, 2)
        XCTAssertEqual(dataset.rows[1]["name"], .string("b"))
    }

    func testMultipleDocumentsAllBecomeRows() throws {
        // 4% of real files are multi-document; reading only the first would
        // silently drop the rest.
        let dataset = try DatasetReader.read("---\nname: a\n---\nname: b\n", format: .yaml)
        XCTAssertEqual(dataset.count, 2)
    }

    func testKeyOrderIsTheFilesOrderNotAlphabetical() throws {
        let dataset = try DatasetReader.read("zebra: 1\napple: 2\nmiddle: 3", format: .yaml)
        XCTAssertEqual(dataset.fields, ["zebra", "apple", "middle"])
    }

    func testBlockScalarsSurvive() throws {
        // 42% of real files use one.
        let row = try first("script: |\n  line one\n  line two\n", format: .yaml)
        XCTAssertEqual(row["script"], .string("line one\nline two\n"))
    }

    // MARK: - TOML

    func testTOMLReadsTablesAndTypes() throws {
        let row = try first("""
            title = "Config"
            enabled = true
            port = 5432
            ratio = 30.5
            hex = 0xDEADBEEF
            """, format: .toml)
        XCTAssertEqual(row["title"], .string("Config"))
        XCTAssertEqual(row["enabled"], .boolean(true))
        XCTAssertEqual(row["port"], .number(5432))
        XCTAssertEqual(row["ratio"], .number(30.5))
        // toml++ emits hex verbatim into JSON unless told not to, which is
        // not valid JSON at all.
        XCTAssertEqual(row["hex"], .number(3735928559))
    }

    func testTOMLLocalDatesDoNotCrash() throws {
        // These SIGSEGV'd the other TOML library when driven generically.
        let row = try first("d = 1979-05-27\nt = 07:32:00\ndt = 1979-05-27T07:32:00Z", format: .toml)
        XCTAssertEqual(row["d"], .string("1979-05-27"))
        XCTAssertEqual(row["t"], .string("07:32:00"))
    }

    func testTOMLNonFinitesBecomeStringsRatherThanBrokenJSON() throws {
        let row = try first("a = inf\nb = nan", format: .toml)
        XCTAssertEqual(row["a"], .string("Infinity"))
        XCTAssertEqual(row["b"], .string("NaN"))
    }

    func testTOMLArrayOfTablesBecomesRows() throws {
        let dataset = try DatasetReader.read("""
            [[product]]
            name = "Hammer"
            [[product]]
            name = "Nail"
            """, format: .toml)
        XCTAssertEqual(dataset.count, 2)
        XCTAssertEqual(dataset.rows[0]["name"], .string("Hammer"))
    }

    // MARK: - Sniffing

    func testFormatsAreRecognisedWithoutAnExtension() {
        XCTAssertEqual(DataFormat.sniffed("name: value\nother: 2"), .yaml)
        XCTAssertEqual(DataFormat.sniffed("---\nname: value"), .yaml)
        XCTAssertEqual(DataFormat.sniffed("- one\n- two"), .yaml)
        XCTAssertEqual(DataFormat.sniffed("# a comment\n[table]\nkey = 1"), .toml)
        XCTAssertEqual(DataFormat.sniffed("key = 1"), .toml)
        XCTAssertEqual(DataFormat.inferred(fromExtension: "yml"), .yaml)
    }

    func testSniffingStillPrefersTheOlderFormats() {
        // The rules must not start eating CSV headers or JSON.
        XCTAssertEqual(DataFormat.sniffed("name,age\na,1"), .csv)
        XCTAssertEqual(DataFormat.sniffed("name\tage\na\t1"), .tsv)
        XCTAssertEqual(DataFormat.sniffed("{\"a\":1}"), .json)
        XCTAssertEqual(DataFormat.sniffed("[{\"a\":1}]"), .json)
        XCTAssertEqual(DataFormat.sniffed("time,note\n12:30,hi"), .csv, "a colon inside a CSV is not YAML")
    }

    // MARK: - Writing

    func testYAMLIsWrittenAndReadsBackUnchanged() throws {
        let original = try DatasetReader.read(#"[{"name":"NO","n":1},{"name":"yes","n":2}]"#, format: .json)
        let yaml = try Writer.write(original, as: .yaml)
        let round = try DatasetReader.read(yaml, format: .yaml)
        XCTAssertEqual(round.count, 2)
        // The values that YAML 1.1 would have destroyed survive a round trip.
        XCTAssertEqual(round.rows[0]["name"], .string("NO"))
        XCTAssertEqual(round.rows[1]["name"], .string("yes"))
        XCTAssertEqual(round.rows[0]["n"], .number(1))
    }

    func testTOMLWritingIsRefusedRatherThanHalfDone() throws {
        let dataset = try DatasetReader.read(#"[{"a":1}]"#, format: .json)
        XCTAssertThrowsError(try Writer.write(dataset, as: .toml))
    }
}
