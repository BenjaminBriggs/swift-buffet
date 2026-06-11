import XCTest
@testable import SwiftBuffet

final class UtilitiesTests: XCTestCase {

    func testStripCommonPrefixAtUnderscoreBoundary() {
        let cases = [
            ProtoEnumCase(name: "GENDER_UNKNOWN", value: 0),
            ProtoEnumCase(name: "GENDER_MALE", value: 1),
            ProtoEnumCase(name: "GENDER_FEMALE", value: 2)
        ]

        let stripped = stripCommonPrefix(from: cases)
        XCTAssertEqual(stripped.map(\.name), ["unknown", "male", "female"])
        XCTAssertEqual(stripped.map(\.value), [0, 1, 2])
    }

    func testStripCommonPrefixIgnoresPartialWordPrefix() {
        let cases = [
            ProtoEnumCase(name: "MALE", value: 0),
            ProtoEnumCase(name: "MARRIED", value: 1)
        ]

        let stripped = stripCommonPrefix(from: cases)
        XCTAssertEqual(stripped.map(\.name), ["male", "married"], "A shared 'MA' is not a word prefix and should not be stripped")
    }

    func testStripCommonPrefixSingleCaseIsUntouched() {
        let cases = [ProtoEnumCase(name: "UNKNOWN", value: 0)]

        let stripped = stripCommonPrefix(from: cases)
        XCTAssertEqual(stripped.map(\.name), ["unknown"], "A single case should not be stripped to an empty name")
    }

    func testStripCommonPrefixDoesNotProduceDigitLeadingNames() {
        let cases = [
            ProtoEnumCase(name: "VERSION_1", value: 0),
            ProtoEnumCase(name: "VERSION_2", value: 1)
        ]

        let stripped = stripCommonPrefix(from: cases)
        XCTAssertEqual(stripped.map(\.name), ["version1", "version2"], "Stripping must not leave identifiers starting with a digit")
    }

    func testSnakeToCamelCase() {
        XCTAssertEqual(snakeToCamelCase("is_active"), "isActive")
        XCTAssertEqual(snakeToCamelCase("name"), "name")
        XCTAssertEqual(snakeToCamelCase("HOME_URL"), "homeUrl")
    }
}
