import XCTest
@testable import SwiftBuffet

/// Tests targeting the generated `init?(proto:)` bodies.
final class ProtoInitTests: XCTestCase {

    private func makeField(
        name: String,
        type: String,
        isOptional: Bool = false,
        isRepeated: Bool = false,
        isMap: Bool = false
    ) -> ProtoField {
        ProtoField(
            swiftPrefix: "App",
            name: name,
            type: type,
            comment: nil,
            isOptional: isOptional,
            isRepeated: isRepeated,
            isMap: isMap,
            isDeprecated: false
        )
    }

    /// Asserts `code` contains `fragment`, ignoring formatting differences —
    /// the SwiftSyntax formatter may split expressions across lines.
    private func assertContains(
        _ code: String,
        _ fragment: String,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        func normalized(_ string: String) -> String {
            string.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        XCTAssertTrue(
            normalized(code).contains(normalized(fragment)),
            message.isEmpty ? "Missing fragment: \(fragment)" : message,
            file: file,
            line: line
        )
    }

    private func generate(fields: [ProtoField]) throws -> String {
        try generateSwiftCode(
            from: [ProtoMessage(name: "Person", fields: fields, parentName: nil)],
            enums: [],
            with: "App",
            includeProto: true,
            includeLocalIDFor: nil,
            includeBackingData: false,
            with: "Proto"
        )
    }

    func testSignedIntConversion() throws {
        let code = try generate(fields: [
            makeField(name: "age", type: "int32"),
            makeField(name: "score", type: "sint64")
        ])

        assertContains(code, "public let age: Int")
        assertContains(code, "self.age = Int(proto.age)")
        assertContains(code, "self.score = Int(proto.score)")
        XCTAssertFalse(code.contains("Int(exactly:"), "Generated code should not force-unwrap int conversions")
    }

    func testUnsignedIntConversion() throws {
        let code = try generate(fields: [
            makeField(name: "counter", type: "uint64"),
            makeField(name: "flags", type: "fixed32")
        ])

        assertContains(code, "public let counter: UInt")
        assertContains(code, "self.counter = UInt(proto.counter)", "Unsigned proto ints should convert via UInt, not Int")
        assertContains(code, "self.flags = UInt(proto.flags)")
        XCTAssertFalse(code.contains("Int(exactly:"))
    }

    func testOptionalFieldHasCheck() throws {
        let code = try generate(fields: [
            makeField(name: "nick_name", type: "string", isOptional: true)
        ])

        assertContains(code, "public let nickName: String?")
        assertContains(code, "if proto.hasNickName {")
        assertContains(code, "self.nickName = nil")
    }

    func testRepeatedFields() throws {
        let code = try generate(fields: [
            makeField(name: "scores", type: "int32", isRepeated: true),
            makeField(name: "addresses", type: "Address", isRepeated: true),
            makeField(name: "image_urls", type: "string", isRepeated: true)
        ])

        assertContains(code, "self.scores = proto.scores.compactMap { Int($0) }")
        assertContains(code, "self.addresses = proto.addresses.compactMap { AppAddress(proto: $0) }")
        assertContains(code, "public let imageURLs: [URL]")
        assertContains(code, "self.imageURLs = proto.imageURLs.compactMap { URL(string: $0) }", "Repeated URL fields should convert via URL(string:)")
    }

    func testMapField() throws {
        let code = try generate(fields: [
            makeField(name: "labels", type: "<string, string>", isMap: true)
        ])

        assertContains(code, "public let labels: [String: String]")
        assertContains(code, "self.labels = proto.labels.reduce(into: [String: String]()) { result, element in result[element.key] = element.value }")
    }

    func testURLFields() throws {
        let code = try generate(fields: [
            makeField(name: "home_url", type: "string"),
            makeField(name: "avatar_url", type: "string", isOptional: true)
        ])

        assertContains(code, "public let homeURL: URL")
        assertContains(code, "if let homeURL = URL(string: proto.homeURL) {")
        assertContains(code, "self.homeURL = homeURL")
        assertContains(code, "public let avatarURL: URL?")
        assertContains(code, "self.avatarURL = URL(string: proto.avatarURL)")
    }

    func testDescriptionFieldUsesProtoEscapedName() throws {
        let code = try generate(fields: [
            makeField(name: "description", type: "string"),
            makeField(name: "summary", type: "Summary")
        ])

        assertContains(code, "self.description = proto.description_p", "SwiftProtobuf escapes 'description' as 'description_p'")
        assertContains(code, "if let summary = AppSummary(proto: proto.summary) {")
        assertContains(code, "self.summary = summary", "The bound local, not the proto property name, should be assigned")
    }

    func testWellKnownTypeFields() throws {
        let code = try generate(fields: [
            makeField(name: "duration", type: "google.protobuf.Duration"),
            makeField(name: "created_at", type: "google.protobuf.Timestamp")
        ])

        assertContains(code, "self.duration = proto.duration.timeInterval")
        assertContains(code, "self.createdAt = proto.createdAt.date")
    }

    func testBackingDataProperty() throws {
        let messages = [ProtoMessage(
            name: "Person",
            fields: [makeField(name: "name", type: "string")],
            parentName: nil
        )]
        let code = try generateSwiftCode(
            from: messages,
            enums: [],
            with: "App",
            includeProto: true,
            includeLocalIDFor: nil,
            includeBackingData: true,
            with: "Proto"
        )

        assertContains(code, "public private(set) var _backingData: Data?")
        assertContains(code, "self._backingData = data")
    }
}
