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

    private func generate(fields: [ProtoField]) -> String {
        generateSwiftCode(
            from: [ProtoMessage(name: "Person", fields: fields, parentName: nil)],
            enums: [],
            with: "App",
            includeProto: true,
            includeLocalIDFor: nil,
            includeBackingData: false,
            with: "Proto"
        )
    }

    func testSignedIntConversion() {
        let code = generate(fields: [
            makeField(name: "age", type: "int32"),
            makeField(name: "score", type: "sint64")
        ])

        XCTAssertTrue(code.contains("public let age: Int"))
        XCTAssertTrue(code.contains("self.age = Int(proto.age)"))
        XCTAssertTrue(code.contains("self.score = Int(proto.score)"))
        XCTAssertFalse(code.contains("Int(exactly:"), "Generated code should not force-unwrap int conversions")
    }

    func testUnsignedIntConversion() {
        let code = generate(fields: [
            makeField(name: "counter", type: "uint64"),
            makeField(name: "flags", type: "fixed32")
        ])

        XCTAssertTrue(code.contains("public let counter: UInt"))
        XCTAssertTrue(code.contains("self.counter = UInt(proto.counter)"), "Unsigned proto ints should convert via UInt, not Int")
        XCTAssertTrue(code.contains("self.flags = UInt(proto.flags)"))
        XCTAssertFalse(code.contains("Int(exactly:"))
    }

    func testOptionalFieldHasCheck() {
        let code = generate(fields: [
            makeField(name: "nick_name", type: "string", isOptional: true)
        ])

        XCTAssertTrue(code.contains("public let nickName: String?"))
        XCTAssertTrue(code.contains("if proto.hasNickName {"))
        XCTAssertTrue(code.contains("self.nickName = nil"))
    }

    func testRepeatedFields() {
        let code = generate(fields: [
            makeField(name: "scores", type: "int32", isRepeated: true),
            makeField(name: "addresses", type: "Address", isRepeated: true),
            makeField(name: "image_urls", type: "string", isRepeated: true)
        ])

        XCTAssertTrue(code.contains("self.scores = proto.scores.compactMap { Int($0) }"))
        XCTAssertTrue(code.contains("self.addresses = proto.addresses.compactMap { AppAddress(proto: $0) }"))
        XCTAssertTrue(code.contains("public let imageURLs: [URL]"))
        XCTAssertTrue(code.contains("self.imageURLs = proto.imageURLs.compactMap { URL(string: $0) }"), "Repeated URL fields should convert via URL(string:)")
    }

    func testMapField() {
        let code = generate(fields: [
            makeField(name: "labels", type: "<string, string>", isMap: true)
        ])

        XCTAssertTrue(code.contains("public let labels: [String: String]"))
        XCTAssertTrue(code.contains("self.labels = proto.labels.reduce(into: [String: String]()) { $0[$1.key] = $1.value }"))
    }

    func testURLFields() {
        let code = generate(fields: [
            makeField(name: "home_url", type: "string"),
            makeField(name: "avatar_url", type: "string", isOptional: true)
        ])

        XCTAssertTrue(code.contains("public let homeURL: URL"))
        XCTAssertTrue(code.contains("if let homeURL = URL(string: proto.homeURL) {"))
        XCTAssertTrue(code.contains("self.homeURL = homeURL"))
        XCTAssertTrue(code.contains("public let avatarURL: URL?"))
        XCTAssertTrue(code.contains("self.avatarURL = URL(string: proto.avatarURL)"))
    }

    func testDescriptionFieldUsesProtoEscapedName() {
        let code = generate(fields: [
            makeField(name: "description", type: "string"),
            makeField(name: "summary", type: "Summary")
        ])

        XCTAssertTrue(code.contains("self.description = proto.description_p"), "SwiftProtobuf escapes 'description' as 'description_p'")
        XCTAssertTrue(code.contains("if let summary = AppSummary(proto: proto.summary) {"))
        XCTAssertTrue(code.contains("self.summary = summary"), "The bound local, not the proto property name, should be assigned")
    }

    func testWellKnownTypeFields() {
        let code = generate(fields: [
            makeField(name: "duration", type: "google.protobuf.Duration"),
            makeField(name: "created_at", type: "google.protobuf.Timestamp")
        ])

        XCTAssertTrue(code.contains("self.duration = proto.duration.timeInterval"))
        XCTAssertTrue(code.contains("self.createdAt = proto.createdAt.date"))
    }

    func testBackingDataProperty() {
        let messages = [ProtoMessage(
            name: "Person",
            fields: [makeField(name: "name", type: "string")],
            parentName: nil
        )]
        let code = generateSwiftCode(
            from: messages,
            enums: [],
            with: "App",
            includeProto: true,
            includeLocalIDFor: nil,
            includeBackingData: true,
            with: "Proto"
        )

        XCTAssertTrue(code.contains("public private(set) var _backingData: Data?"))
        XCTAssertTrue(code.contains("self._backingData = data"))
    }
}
