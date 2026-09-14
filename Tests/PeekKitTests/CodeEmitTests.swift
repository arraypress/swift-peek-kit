//
//  CodeEmitTests.swift
//  PeekKit
//
//  Created by David Sherlock on 2026.
//
//  Generating declarations from a measured shape. The claims worth holding
//  are that optionality is counted rather than guessed, that a string field
//  only becomes an enumeration when its values actually repeat, and that a
//  field reached through an array describes the element and not the list.
//

import XCTest
@testable import PeekKit

final class CodeEmitTests: XCTestCase {

    /// Ten rows: snake_case, kebab-case, a keyword, a leading digit, a field
    /// that goes missing, whole and fractional numbers, a nested object, an
    /// array of objects, one string that repeats and one that never does.
    private func dataset() throws -> Dataset {
        try DatasetReader.read("""
            [{"user_id":1,"full-name":"Ada","class":"x","score":1.0,"active":true,"status":"open","2fa":true,
              "address":{"city":"London","postcode":"P0"},"items":[{"sku":"S0","qty":1}]},
             {"user_id":2,"full-name":"Alan","class":"x","score":1.5,"active":false,"status":"closed","2fa":false,
              "email":"alan@x.com","address":{"city":"Leeds","postcode":"P1"},"items":[{"sku":"S1","qty":2}]},
             {"user_id":3,"full-name":"Grace","class":"x","score":2.0,"active":true,"status":"open","2fa":false,
              "email":"grace@x.com","address":{"city":"Bath","postcode":"P2"},"items":[{"sku":"S2","qty":3}]},
             {"user_id":4,"full-name":"Linus","class":"x","score":2.5,"active":false,"status":"closed","2fa":true,
              "email":"linus@x.com","address":{"city":"London","postcode":"P3"},"items":[{"sku":"S3","qty":4}]},
             {"user_id":5,"full-name":"Edsger","class":"x","score":3.0,"active":true,"status":"open","2fa":false,
              "address":{"city":"Leeds","postcode":"P4"},"items":[{"sku":"S4","qty":5}]},
             {"user_id":6,"full-name":"Barbara","class":"x","score":3.5,"active":false,"status":"closed","2fa":false,
              "email":"barbara@x.com","address":{"city":"Bath","postcode":"P5"},"items":[{"sku":"S5","qty":6}]},
             {"user_id":7,"full-name":"Donald","class":"x","score":4.0,"active":true,"status":"open","2fa":true,
              "email":"donald@x.com","address":{"city":"London","postcode":"P6"},"items":[{"sku":"S6","qty":7}]},
             {"user_id":8,"full-name":"Ken","class":"x","score":4.5,"active":false,"status":"closed","2fa":false,
              "email":"ken@x.com","address":{"city":"Leeds","postcode":"P7"},"items":[{"sku":"S7","qty":8}]},
             {"user_id":9,"full-name":"Dennis","class":"x","score":5.0,"active":true,"status":"open","2fa":false,
              "address":{"city":"Bath","postcode":"P8"},"items":[{"sku":"S8","qty":9}]},
             {"user_id":10,"full-name":"Margaret","class":"x","score":5.5,"active":false,"status":"closed","2fa":true,
              "email":"margaret@x.com","address":{"city":"London","postcode":"P9"},"items":[{"sku":"S9","qty":10}]}]
            """)
    }

    private func swiftSource() throws -> String {
        CodeEmitter.emit(try dataset(), as: .swift, rootName: "User")
    }

    // MARK: - Optionality is counted, not guessed

    func testMissingFieldBecomesOptional() throws {
        let source = try swiftSource()
        XCTAssertTrue(source.contains("let email: String?"), "email is absent in 3 of 10 rows")
        XCTAssertTrue(source.contains("let active: Bool\n"), "active is never absent")
        XCTAssertFalse(source.contains("let active: Bool?"))
    }

    func testGoMarksOptionalWithPointerAndOmitEmpty() throws {
        let source = CodeEmitter.emit(try dataset(), as: .go, rootName: "User")
        XCTAssertTrue(source.contains("*string `json:\"email,omitempty\"`"))
        XCTAssertTrue(source.contains("`json:\"active\"`"))
        XCTAssertFalse(source.contains("`json:\"active,omitempty\"`"))
    }

    // MARK: - An enumeration has to repeat

    func testRepeatingStringBecomesEnum() throws {
        let source = try swiftSource()
        XCTAssertTrue(source.contains("enum Status: String, Codable"))
        XCTAssertTrue(source.contains("case closed = \"closed\""))
    }

    func testNeverRepeatingStringStaysAString() throws {
        let source = try swiftSource()
        // 10 distinct names in 10 rows is a name, not a closed set. An early
        // version turned every one of these into an enumeration.
        XCTAssertTrue(source.contains("let fullName: String"))
        XCTAssertFalse(source.contains("enum FullName"))
        XCTAssertFalse(source.contains("enum Postcode"))
    }

    func testSingleValuedStringIsNotAnEnum() throws {
        XCTAssertTrue(try swiftSource().contains("let `class`: String"))
    }

    func testEnumNeedsEnoughRows() {
        // Perfectly repeating, but only four observations: too few to claim
        // the set is closed.
        let tiny = FieldShape(name: "status", kinds: [.string], present: 4, missing: 0,
                              distinct: 2, examples: ["open", "closed"])
        XCTAssertNil(TypeInference.enumCases(tiny, limit: 24))

        let enough = FieldShape(name: "status", kinds: [.string], present: 10, missing: 0,
                                distinct: 2, examples: ["open", "closed"])
        XCTAssertEqual(TypeInference.enumCases(enough, limit: 24), ["closed", "open"])
    }

    func testEnumNeedsEveryValueObserved() {
        // Nine distinct values but only three sampled: a case list here would
        // fail to decode the other six.
        let undersampled = FieldShape(name: "code", kinds: [.string], present: 90, missing: 0,
                                      distinct: 9, examples: ["a", "b", "c"])
        XCTAssertNil(TypeInference.enumCases(undersampled, limit: 24))
    }

    // MARK: - Reaching through an array describes the element

    func testArrayOfObjectsGivesScalarElementFields() throws {
        let source = try swiftSource()
        XCTAssertTrue(source.contains("let items: [Item]"))
        // Not `[String]`: `items.sku` resolves to every sku in the row, but
        // the declaration wants the element's type.
        XCTAssertTrue(source.contains("let sku: String"))
        XCTAssertTrue(source.contains("let qty: Int"))
        XCTAssertFalse(source.contains("let sku: [String]"))
    }

    // MARK: - Numbers

    func testWholeNumbersAreIntAndFractionalAreDouble() throws {
        let source = try swiftSource()
        XCTAssertTrue(source.contains("let userId: Int"))
        XCTAssertTrue(source.contains("let score: Double"))
    }

    // MARK: - Names a compiler will accept

    func testKeywordsAreEscaped() throws {
        let source = try swiftSource()
        XCTAssertTrue(source.contains("let `class`:"))
        XCTAssertTrue(source.contains("case `open` = \"open\""))
    }

    func testLeadingDigitIsGuarded() throws {
        XCTAssertTrue(try swiftSource().contains("let _2fa: Bool"))
        XCTAssertTrue(try swiftSource().contains("case _2fa = \"2fa\""))
    }

    func testCodingKeysOnlyWhenNamesDiffer() {
        let same = [GeneratedField(wireName: "id", type: .integer, isOptional: false)]
        XCTAssertNil(SwiftEmitter.codingKeys(same), "a block restating every name is noise")

        let differs = [GeneratedField(wireName: "user_id", type: .integer, isOptional: false)]
        XCTAssertNotNil(SwiftEmitter.codingKeys(differs))
    }

    func testTypeScriptQuotesKeysThatAreNotIdentifiers() throws {
        let source = CodeEmitter.emit(try dataset(), as: .typescript, rootName: "User")
        XCTAssertTrue(source.contains("\"full-name\": string;"))
        XCTAssertTrue(source.contains("\"2fa\": boolean;"))
        XCTAssertTrue(source.contains("active: boolean;"))
        XCTAssertTrue(source.contains("export type Status = \"closed\" | \"open\";"))
    }

    func testGoUsesInitialisms() {
        XCTAssertEqual(GoEmitter.name("user_id"), "UserID")
        XCTAssertEqual(GoEmitter.name("api_url"), "APIURL")
        XCTAssertEqual(GoEmitter.name("full-name"), "FullName")
    }

    // MARK: - Word splitting

    func testAcronymRunsSplitProperly() {
        XCTAssertEqual(Identifiers.words("HTTPServerError"), ["http", "server", "error"])
        XCTAssertEqual(Identifiers.words("user_id"), ["user", "id"])
        XCTAssertEqual(Identifiers.words("full-name"), ["full", "name"])
        XCTAssertEqual(Identifiers.camelCase("Content-Type"), "contentType")
    }

    func testSingularNamesArrayElements() {
        XCTAssertEqual(Identifiers.singular("items"), "Item")
        XCTAssertEqual(Identifiers.singular("addresses"), "Address")
        XCTAssertEqual(Identifiers.singular("entries"), "Entry")
        XCTAssertEqual(Identifiers.singular("status"), "Status", "not every -s is a plural")
        XCTAssertEqual(Identifiers.singular("analysis"), "Analysis")
        XCTAssertEqual(Identifiers.singular("address"), "Address")
    }

    // MARK: - Mixed kinds are not papered over

    func testMixedKindsAreMarkedRatherThanGuessed() {
        let mixed = FieldShape(name: "value", kinds: [.string, .number], present: 10, missing: 0,
                               distinct: 10, examples: ["a", "1"])
        let type = TypeInference.scalar(mixed, enumName: { "Value" }, enumLimit: 24)
        XCTAssertEqual(type, .unknown)

        let source = CodeEmitter.emit([mixed], as: .swift, rootName: "Row")
        XCTAssertTrue(source.contains("// mixed or unobserved"))
    }
}
