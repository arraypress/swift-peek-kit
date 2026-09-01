//
//  SummaryTests.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//
//  What the numbers mean once the bytes are in: paths that reach through
//  nesting, percentiles that report values which actually occurred, a shape
//  that refuses to call a column numeric when one cell says "n/a", and a
//  diff that ignores drift and reports movement.
//

import XCTest
@testable import PeekKit

final class SummaryTests: XCTestCase {

    /// Shaped like a real `verify` run: a name, a measurement, a nested
    /// array of issues, and one row with a field missing.
    private func makeDataset() throws -> Dataset {
        try DatasetReader.read("""
            [{"file":"a.fxp","peak":0.5,"rms":0.1,"ok":true,"issues":[],"meta":{"kind":"pad"}},
             {"file":"b.fxp","peak":1.5,"rms":0.2,"ok":false,"issues":[{"code":"hot"}],"meta":{"kind":"bass"}},
             {"file":"c.fxp","peak":2.5,"rms":0.3,"ok":false,"issues":[{"code":"hot"},{"code":"quiet"}],"meta":{"kind":"pad"}},
             {"file":"d.fxp","rms":0.4,"ok":true,"issues":[],"meta":{"kind":"pad"}}]
            """)
    }

    // MARK: Paths

    func testADottedPathReachesIntoNestedObjects() throws {
        let dataset = try makeDataset()
        XCTAssertEqual(dataset.column("meta.kind").map(\.text), ["pad", "bass", "pad", "pad"])
    }

    func testAPathThroughAnArrayMapsOverIt() throws {
        // "issues.code" is every code in the row, not the first one: a row
        // with two issues has to answer for both.
        let dataset = try makeDataset()
        XCTAssertEqual(dataset.column("issues.code")[2], .array([.string("hot"), .string("quiet")]))
    }

    func testANumericPathComponentIndexes() throws {
        let dataset = try makeDataset()
        XCTAssertEqual(Dataset.value(at: "issues.0.code", in: dataset.rows[2]), .string("hot"))
    }

    func testNestedPathsAreDiscoverable() throws {
        let dataset = try makeDataset()
        XCTAssertTrue(dataset.paths().contains("meta.kind"))
    }

    // MARK: Statistics

    func testPercentilesReportValuesThatActuallyOccurred() throws {
        let dataset = try DatasetReader.read("[{\"v\":1},{\"v\":2},{\"v\":3},{\"v\":4},{\"v\":100}]")
        let summary = try Statistics.summary(of: "v", in: dataset)
        XCTAssertEqual(summary.median, 3, "nearest rank, so the answer is a real observation")
        XCTAssertEqual(summary.minimum, 1)
        XCTAssertEqual(summary.maximum, 100)
        XCTAssertEqual(summary.count, 5)
        XCTAssertEqual(summary.sum, 110)
        XCTAssertEqual(summary.mean, 22)
    }

    func testAMissingFieldIsCountedNotSilentlyDropped() throws {
        let dataset = try makeDataset()
        let summary = try Statistics.summary(of: "peak", in: dataset)
        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.missing, 1, "d.fxp has no peak and the summary has to say so")
    }

    func testNumbersWrittenAsTextAreStillNumbers() throws {
        // A CSV has no types; every cell is a string until read as a number.
        let dataset = try DatasetReader.read("price\n\"1,234\"\n$99\n50%\n")
        let summary = try Statistics.summary(of: "price", in: dataset)
        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.maximum, 1234)
        XCTAssertEqual(summary.minimum, 0.5, "50% is a half")
    }

    func testATextColumnCannotBeSummarised() throws {
        let dataset = try makeDataset()
        XCTAssertThrowsError(try Statistics.summary(of: "file", in: dataset)) { error in
            XCTAssertEqual(error as? PeekError, .notNumeric("file"))
        }
    }

    func testAnUnknownFieldSaysWhatDoesExist() throws {
        let dataset = try makeDataset()
        XCTAssertThrowsError(try Statistics.summary(of: "nope", in: dataset)) { error in
            guard case .noSuchField(let name, let available) = error as? PeekError else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(name, "nope")
            XCTAssertTrue(available.contains("file"), "a refusal that lists the options costs a round trip less")
        }
    }

    // MARK: Counting

    func testCountingReachesIntoArraysElementByElement() throws {
        let dataset = try makeDataset()
        let counts = try Statistics.counts(of: "issues.code", in: dataset)
        XCTAssertEqual(counts.first?.value, "hot")
        XCTAssertEqual(counts.first?.count, 2, "two rows carry hot, and one of them carries two codes")
        XCTAssertEqual(counts.count, 2)
    }

    func testSharesAreTakenAgainstRows() throws {
        let dataset = try makeDataset()
        let counts = try Statistics.counts(of: "ok", in: dataset)
        XCTAssertEqual(counts.map(\.value).sorted(), ["false", "true"])
        XCTAssertEqual(counts.first(where: { $0.value == "true" })?.share, 0.5)
    }

    // MARK: Shape

    func testAColumnIsNumericOnlyWhenEveryValueIs() throws {
        let clean = try DatasetReader.read("v\n1\n2\n")
        XCTAssertTrue(Shape.shape(of: "v", in: clean).isNumeric)

        let dirty = try DatasetReader.read("v\n1\nn/a\n")
        XCTAssertFalse(
            Shape.shape(of: "v", in: dirty).isNumeric,
            "one unparseable cell means maths would quietly skip a row"
        )
    }

    func testAnEmptyCellCountsAsMissingRatherThanAsAValue() throws {
        let dataset = try DatasetReader.read("id,v\n1,10\n2,\n3,30\n")
        let shape = Shape.shape(of: "v", in: dataset)
        XCTAssertEqual(dataset.count, 3)
        XCTAssertEqual(shape.present, 2)
        XCTAssertEqual(shape.missing, 1, "an empty cell is an absent value, not the empty string")
        XCTAssertEqual(shape.distinct, 2)
    }

    func testAWhollyBlankLineIsNotARow() throws {
        // Different from an empty cell: a line with nothing on it is
        // whitespace between records, which is how files end and how people
        // separate blocks. Counting it as a row of nulls would inflate every
        // total by however many blank lines the file happens to carry.
        let dataset = try DatasetReader.read("v\n1\n\n3\n")
        XCTAssertEqual(dataset.count, 2)
    }

    func testShapeFollowsTheHeaderOrder() throws {
        let dataset = try DatasetReader.read("zebra,apple\n1,2\n")
        XCTAssertEqual(Shape.of(dataset).map(\.name), ["zebra", "apple"], "header order is meaningful")
    }

    // MARK: Diff

    func testADiffMatchesRowsByKeyNotByPosition() throws {
        let before = try DatasetReader.read("[{\"id\":\"a\",\"n\":1},{\"id\":\"b\",\"n\":2}]")
        let after = try DatasetReader.read("[{\"id\":\"b\",\"n\":2},{\"id\":\"a\",\"n\":5}]")
        let changes = try Comparison.diff(before: before, after: after, key: "id")
        XCTAssertEqual(changes.count, 1, "reordering is not a change")
        XCTAssertEqual(changes[0].key, "a")
        XCTAssertEqual(changes[0].fields.first?.delta, 4)
    }

    func testAddedAndRemovedRowsAreReported() throws {
        let before = try DatasetReader.read("[{\"id\":\"a\"},{\"id\":\"b\"}]")
        let after = try DatasetReader.read("[{\"id\":\"b\"},{\"id\":\"c\"}]")
        let changes = try Comparison.diff(before: before, after: after, key: "id")
        XCTAssertEqual(Set(changes.map { "\($0.kind.rawValue):\($0.key)" }), ["added:c", "removed:a"])
    }

    func testToleranceSuppressesDriftButNotMovement() throws {
        let before = try DatasetReader.read("[{\"id\":\"a\",\"db\":-4.30}]")
        let after = try DatasetReader.read("[{\"id\":\"a\",\"db\":-4.35}]")
        XCTAssertTrue(
            try Comparison.diff(before: before, after: after, key: "id", tolerance: 0.5).isEmpty,
            "measured data is noisy; 0.05 dB is not news"
        )
        XCTAssertEqual(try Comparison.diff(before: before, after: after, key: "id", tolerance: 0.01).count, 1)
    }

    func testComparingOnAKeyNothingHasIsRefused() throws {
        let dataset = try makeDataset()
        XCTAssertThrowsError(try Comparison.diff(before: dataset, after: dataset, key: "missing"))
    }
}

extension SummaryTests {

    func testCountingCanGroupMessagesByTheirCode() throws {
        // Findings carry a variable tail: "hot: +6.74 dBFS" and "hot: +6.97
        // dBFS" are one finding twice. Counted whole they produce a list as
        // long as the data and tell you nothing.
        let dataset = try DatasetReader.read("""
            [{"issues":["hot: +6.74 dBFS","quiet: -50 dBFS"]},
             {"issues":["hot: +6.97 dBFS"]},
             {"issues":["mod wheel moves nothing (0.95x)"]},
             {"issues":["mod wheel moves nothing (1.11x)"]}]
            """)
        XCTAssertEqual(try Statistics.counts(of: "issues", in: dataset).count, 5, "whole strings barely group")

        let grouped = try Statistics.counts(of: "issues", in: dataset, truncatingAt: ":(")
        XCTAssertEqual(grouped.map(\.value), ["hot", "mod wheel moves nothing", "quiet"])
        XCTAssertEqual(grouped[0].count, 2)
        XCTAssertEqual(grouped[1].count, 2)
    }

    func testTruncatingNeverProducesAnEmptyLabel() {
        // A value that begins with the separator would otherwise tally under
        // "", which is unreadable and merges unrelated rows.
        XCTAssertEqual(Statistics.truncate(": leading", at: [":"]), ": leading")
    }

    func testBooleansAreNotOfferedAsNumericColumns() throws {
        let dataset = try DatasetReader.read("[{\"ok\":true},{\"ok\":false}]")
        XCTAssertFalse(Shape.shape(of: "ok", in: dataset).isNumeric, "a range of 0 … 1 beside \"boolean\" says nothing")
        XCTAssertEqual(try Statistics.summary(of: "ok", in: dataset).mean, 0.5, "but asking directly still works")
    }

    func testDisplayRoundsWhereJSONKeepsPrecision() {
        XCTAssertEqual(Value.number(0.6797419190406799).display, "0.679742")
        XCTAssertEqual(Value.number(0.6797419190406799).text, "0.6797419190406799")
        XCTAssertEqual(Value.number(42).display, "42", "an integer needs no decimal point")
    }
}

extension SummaryTests {

    func testADiffReportsRoundedValuesAndAnExactDelta() throws {
        let before = try DatasetReader.read("[{\"id\":\"a\",\"v\":0.40611106157302856}]")
        let after = try DatasetReader.read("[{\"id\":\"a\",\"v\":0.5655805468559265}]")
        let change = try Comparison.diff(before: before, after: after, key: "id")[0].fields[0]
        XCTAssertEqual(change.before, "0.406111")
        XCTAssertEqual(change.after, "0.565581")
        XCTAssertEqual(change.delta ?? 0, 0.15946948528289795, accuracy: 1e-12, "the movement stays exact")
    }
}
