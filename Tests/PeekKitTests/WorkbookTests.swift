//
//  WorkbookTests.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//
//  Against a real .xlsx, built to look like an export rather than like a
//  demo: a gap in the column letters, a row that omits a cell entirely, a
//  blank row, booleans, and a second sheet.
//

import XCTest
@testable import PeekKit

final class WorkbookTests: XCTestCase {

    private var workbook: URL {
        get throws {
            guard let url = Bundle.module.url(forResource: "Fixtures/workbook", withExtension: "xlsx") else {
                throw XCTSkip("fixture missing")
            }
            return url
        }
    }

    func testAWorkbookIsRecognisedFromItsBytesNotItsName() throws {
        let data = try Data(contentsOf: try workbook)
        XCTAssertEqual(DataFormat.sniffed(data: data), .xlsx, "a workbook is a zip and begins PK")
        XCTAssertEqual(DataFormat.inferred(fromExtension: "xlsx"), .xlsx)
        XCTAssertNil(DataFormat.sniffed(data: Data("name,price\n".utf8)), "text is not claimed by the binary sniffer")
    }

    func testTheFirstSheetIsReadWithItsHeader() throws {
        let dataset = try DatasetReader.read(contentsOf: try workbook)
        XCTAssertEqual(dataset.format, .xlsx)
        XCTAssertEqual(dataset.fields, ["name", "price", "stocked", "note"])
        XCTAssertEqual(dataset.count, 3, "the blank row is not a row")
    }

    func testAMissingCellDoesNotSlideTheRestOfTheRowAcross() throws {
        // The row for Grace has no C cell at all. Zipping cells to headers by
        // position would put "gap in C" under `stocked` and lose `note`.
        let dataset = try DatasetReader.read(contentsOf: try workbook)
        let grace = dataset.rows.first { $0["name"] == .string("Grace") }
        XCTAssertEqual(grace?["note"], .string("gap in C"))
        XCTAssertEqual(grace?["stocked"], .null)
    }

    func testAGapInTheHeaderLettersIsNotAColumn() throws {
        // The header uses A, B, C and E — there is no D. The sheet has four
        // columns, not five.
        let dataset = try DatasetReader.read(contentsOf: try workbook)
        XCTAssertEqual(dataset.fields.count, 4)
        XCTAssertFalse(dataset.fields.contains { $0.hasPrefix("column") })
    }

    func testAWorkbookCarriesItsOwnTypes() throws {
        // Unlike a CSV, where everything arrives as text and has to be
        // re-read as a number.
        let dataset = try DatasetReader.read(contentsOf: try workbook)
        let ada = dataset.rows.first { $0["name"] == .string("Ada") }
        XCTAssertEqual(ada?["price"], .number(1234.5))
        XCTAssertEqual(ada?["stocked"], .boolean(true))
        XCTAssertEqual(Shape.shape(of: "price", in: dataset).kind, .number)
    }

    func testAWorkbookSummarisesLikeAnythingElse() throws {
        let dataset = try DatasetReader.read(contentsOf: try workbook)
        let summary = try Statistics.summary(of: "price", in: dataset)
        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.minimum, 0.5)
        XCTAssertEqual(summary.maximum, 1234.5)
    }

    // MARK: Choosing a sheet

    func testSheetNamesAreReadable() throws {
        XCTAssertEqual(XLSXReader.sheetNames(contentsOf: try workbook), ["Prices", "Notes"])
    }

    func testASheetCanBeChosenByName() throws {
        let dataset = try DatasetReader.read(contentsOf: try workbook, sheet: "Notes")
        XCTAssertEqual(dataset.fields, ["comment"])
        XCTAssertEqual(dataset.rows.first?["comment"], .string("second sheet"))
    }

    func testASheetNameIsMatchedWithoutRegardToCase() throws {
        XCTAssertEqual(try DatasetReader.read(contentsOf: try workbook, sheet: "notes").fields, ["comment"])
    }

    func testASheetCanBeChosenByItsTabNumber() throws {
        // One-based, the way the tabs are counted rather than the way an
        // array is indexed.
        XCTAssertEqual(try DatasetReader.read(contentsOf: try workbook, sheet: "2").fields, ["comment"])
        XCTAssertEqual(try DatasetReader.read(contentsOf: try workbook, sheet: "1").fields.first, "name")
    }

    func testAnUnknownSheetSaysWhichOnesExist() throws {
        XCTAssertThrowsError(try DatasetReader.read(contentsOf: try workbook, sheet: "Sales")) { error in
            guard case .noSuchSheet(let name, let available) = error as? PeekError else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(name, "Sales")
            XCTAssertEqual(available, ["Prices", "Notes"])
        }
    }

    func testAWorkbookCannotBeReadFromAString() throws {
        XCTAssertThrowsError(try DatasetReader.read("anything", format: .xlsx))
    }
}
