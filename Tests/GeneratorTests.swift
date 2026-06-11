import XCTest
@testable import SwiftBuffet

final class GeneratorTests: XCTestCase {
    func testGenerateSimpleMessage() throws {
        let simpleMessageProtoMessage = ProtoMessage(
            name: "Person",
            fields: [
                ProtoField(
                    swiftPrefix: "App",
                    name: "name",
                    type: "string",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                ),
                ProtoField(
                    swiftPrefix: "App",
                    name: "age",
                    type: "int32",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                ),
                ProtoField(
                    swiftPrefix: "App",
                    name: "is_active",
                    type: "bool",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                )
            ],
            parentName: nil
        )

        let messages = [simpleMessageProtoMessage]
        let enums: [ProtoEnum] = []

        let generatedCode = try generateSwiftCode(
            from: messages,
            enums: enums,
            with: "App",
            includeProto: true,
            includeLocalIDFor: ["Person"],
            includeBackingData: false,
            with: "Proto"
        )

        XCTAssertTrue(generatedCode.contains("public struct AppPerson"), "The generated code should contain the 'AppPerson' struct")
        XCTAssertTrue(generatedCode.contains("public let name: String"), "The generated code should contain the 'name' property")
        XCTAssertTrue(generatedCode.contains("public let age: Int"), "The generated code should contain the 'age' property")
        XCTAssertTrue(generatedCode.contains("public let isActive: Bool"), "The generated code should contain the 'isActive' property")
        XCTAssertTrue(generatedCode.contains("public init("), "The generated code should contain the 'init' method")
        XCTAssertTrue(generatedCode.contains("self.name = name"), "The generated code should initialize the 'name' property")
        XCTAssertTrue(generatedCode.contains("self.age = age"), "The generated code should initialize the 'age' property")
        XCTAssertTrue(generatedCode.contains("self.isActive = isActive"), "The generated code should initialize the 'isActive' property")
        XCTAssertTrue(generatedCode.contains("internal init?(proto: ProtoPerson)"), "The generated code should contain the 'init?(proto:)' method")
        XCTAssertTrue(generatedCode.contains("public let _localID = UUID()"), "The generated code should a `localID` property")
    }

    func testGenerateNestedMessage() throws {
        let addressProtoMessage = ProtoMessage(
            name: "Address",
            fields: [
                ProtoField(
                    swiftPrefix: "App",
                    name: "street",
                    type: "string",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                ),
                ProtoField(
                    swiftPrefix: "App",
                    name: "city",
                    type: "string",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                ),
                ProtoField(
                    swiftPrefix: "App",
                    name: "state",
                    type: "string",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                )
            ],
            parentName: nil
        )

        let personProtoMessage = ProtoMessage(
            name: "Person",
            fields: [
                ProtoField(
                    swiftPrefix: "App",
                    name: "name",
                    type: "string",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                ),
                ProtoField(
                    swiftPrefix: "App",
                    name: "age",
                    type: "int32",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                ),
                ProtoField(
                    swiftPrefix: "App",
                    name: "address",
                    type: "Address",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                )
            ],
            parentName: nil
        )

        let messages = [personProtoMessage, addressProtoMessage]
        let enums: [ProtoEnum] = []

        let generatedCode = try generateSwiftCode(
            from: messages,
            enums: enums,
            with: "App",
            includeProto: true,
            includeLocalIDFor: nil,
            includeBackingData: false,
            with: "Proto"
        )

        XCTAssertTrue(generatedCode.contains("public struct AppPerson"), "The generated code should contain the 'AppPerson' struct")
        XCTAssertTrue(generatedCode.contains("public let name: String"), "The generated code should contain the 'name' property")
        XCTAssertTrue(generatedCode.contains("public let age: Int"), "The generated code should contain the 'age' property")
        XCTAssertTrue(generatedCode.contains("public let address: AppAddress"), "The generated code should contain the 'address' property")
        XCTAssertTrue(generatedCode.contains("public struct AppAddress"), "The generated code should contain the 'AppAddress' struct")
        XCTAssertTrue(generatedCode.contains("public let street: String"), "The generated code should contain the 'street' property")
        XCTAssertTrue(generatedCode.contains("public let city: String"), "The generated code should contain the 'city' property")
        XCTAssertTrue(generatedCode.contains("public let state: String"), "The generated code should contain the 'state' property")
        XCTAssertTrue(generatedCode.contains("public init("), "The generated code should contain the 'init' method")
        XCTAssertTrue(generatedCode.contains("internal init?(proto: ProtoPerson)"), "The generated code should contain the 'init?(proto:)' method for 'ProtoPerson'")
        XCTAssertTrue(generatedCode.contains("internal init?(proto: ProtoAddress)"), "The generated code should contain the 'init?(proto:)' method for 'ProtoAddress'")
    }

    func testGenerateNestedEnumAndWellKnownTypes() throws {
        let personProtoMessage = ProtoMessage(
            name: "Person",
            fields: [
                ProtoField(
                    swiftPrefix: "App",
                    name: "name",
                    type: "string",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                ),
                ProtoField(
                    swiftPrefix: "App",
                    name: "age",
                    type: "int32",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                ),
                ProtoField(
                    swiftPrefix: "App",
                    name: "is_active",
                    type: "bool",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                ),
                ProtoField(
                    swiftPrefix: "App",
                    name: "gender",
                    type: "Gender",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                ),
                ProtoField(
                    swiftPrefix: "App",
                    name: "last_active",
                    type: "google.protobuf.Duration",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                ),
                ProtoField(
                    swiftPrefix: "App",
                    name: "created_at",
                    type: "google.protobuf.Timestamp",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                )
            ],
            parentName: nil
        )

        let genderProtoEnum = ProtoEnum(
            name: "Gender",
            cases: [
                ProtoEnumCase(name: "UNKNOWN", value: 0),
                ProtoEnumCase(name: "MALE", value: 1),
                ProtoEnumCase(name: "FEMALE", value: 2)
            ],
            parentName: nil
        )

        let messages = [personProtoMessage]
        let enums = [genderProtoEnum]

        let generatedCode = try generateSwiftCode(
            from: messages,
            enums: enums,
            with: "App",
            includeProto: true,
            includeLocalIDFor: nil,
            includeBackingData: false,
            with: "Proto"
        )

        XCTAssertTrue(generatedCode.contains("public struct AppPerson"), "The generated code should contain the 'AppPerson' struct")
        XCTAssertTrue(generatedCode.contains("public let name: String"), "The generated code should contain the 'name' property")
        XCTAssertTrue(generatedCode.contains("public let age: Int"), "The generated code should contain the 'age' property")
        XCTAssertTrue(generatedCode.contains("public let isActive: Bool"), "The generated code should contain the 'isActive' property")
        XCTAssertTrue(generatedCode.contains("public enum AppGender: Int"), "The generated code should contain the 'Gender' enum")
        XCTAssertTrue(generatedCode.contains("case unknown = 0"), "The 'Gender' enum should contain the 'unknown' case")
        XCTAssertTrue(generatedCode.contains("case male = 1"), "The 'Gender' enum should contain the 'male' case")
        XCTAssertTrue(generatedCode.contains("case female = 2"), "The 'Gender' enum should contain the 'female' case")
        XCTAssertTrue(generatedCode.contains("public let gender: AppGender"), "The generated code should contain the 'gender' property")
        XCTAssertTrue(generatedCode.contains("public let lastActive: TimeInterval"), "The generated code should contain the 'lastActive' property")
        XCTAssertTrue(generatedCode.contains("public let createdAt: Date"), "The generated code should contain the 'createdAt' property")
        XCTAssertTrue(generatedCode.contains("internal init?(proto: ProtoPerson)"), "The generated code should contain the 'init?(proto:)' method")
    }

    func testIntegerConversionIsFailableNotForceUnwrapped() throws {
        let message = ProtoMessage(
            name: "Stats",
            fields: [
                ProtoField(
                    swiftPrefix: "App",
                    name: "view_count",
                    type: "uint64",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                ),
                ProtoField(
                    swiftPrefix: "App",
                    name: "rank",
                    type: "int32",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                )
            ],
            parentName: nil
        )

        let generated = try generateSwiftCode(
            from: [message],
            enums: [],
            with: "App",
            includeProto: true,
            includeLocalIDFor: nil,
            includeBackingData: false,
            with: "Proto"
        )

        XCTAssertFalse(generated.contains("!"), "Integer conversion must not force-unwrap")
        XCTAssertTrue(generated.contains("if let viewCount = UInt(exactly: proto.viewCount)"),
                      "uint64 must convert via its own Swift type, not Int")
        XCTAssertTrue(generated.contains("if let rank = Int(exactly: proto.rank)"))
    }

    func testMessageTypeNameContainingIntIsNotTreatedAsInteger() throws {
        let message = ProtoMessage(
            name: "Job",
            fields: [
                ProtoField(
                    swiftPrefix: "App",
                    name: "print_job",
                    type: "PrintJob",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                )
            ],
            parentName: nil
        )

        let generated = try generateSwiftCode(
            from: [message],
            enums: [],
            with: "App",
            includeProto: true,
            includeLocalIDFor: nil,
            includeBackingData: false,
            with: "Proto"
        )

        XCTAssertFalse(generated.contains("Int(exactly:"),
                       "A message type whose name contains 'int' must not take the integer branch")
        XCTAssertTrue(generated.contains("if let printJob = AppPrintJob(proto: proto.printJob)"))
    }

    func testNestedMessageProtoInitUsesFullProtoTypeName() throws {
        let inner = ProtoMessage(
            name: "Inner",
            fields: [
                ProtoField(
                    swiftPrefix: "App",
                    name: "value",
                    type: "string",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                )
            ],
            parentPath: ["Outer", "Middle"]
        )

        let generated = try generateSwiftCode(
            from: [inner],
            enums: [],
            with: "App",
            includeProto: true,
            includeLocalIDFor: nil,
            includeBackingData: false,
            with: "Proto"
        )

        XCTAssertTrue(generated.contains("internal init?(proto: ProtoOuter.Middle.Inner)"),
                      "Nested messages must reference the fully-qualified SwiftProtobuf type")
        XCTAssertTrue(generated.contains("try? ProtoOuter.Middle.Inner(serializedBytes: data)"))
        XCTAssertFalse(generated.contains("ProtoInner"))
    }

    func testDuplicateSwiftTypeNamesThrow() {
        let field = ProtoField(
            swiftPrefix: "App",
            name: "value",
            type: "string",
            comment: nil,
            isOptional: false,
            isRepeated: false,
            isMap: false,
            isDeprecated: false
        )
        let first = ProtoMessage(name: "Item", fields: [field], parentPath: ["Order"])
        let second = ProtoMessage(name: "Item", fields: [field], parentPath: ["Invoice"])

        XCTAssertThrowsError(
            try generateSwiftCode(
                from: [first, second],
                enums: [],
                with: "App",
                includeProto: false,
                includeLocalIDFor: nil,
                includeBackingData: false,
                with: "Proto"
            )
        ) { error in
            let description = String(describing: error)
            XCTAssertTrue(description.contains("AppItem"))
            XCTAssertTrue(description.contains("Order.Item"))
            XCTAssertTrue(description.contains("Invoice.Item"))
        }
    }

    func testMessageAndTopLevelEnumNameCollisionThrows() {
        let nestedMessage = ProtoMessage(
            name: "Status",
            fields: [],
            parentPath: ["Person"]
        )
        let topLevelEnum = ProtoEnum(
            name: "Status",
            cases: [ProtoEnumCase(name: "S_UNKNOWN", value: 0)],
            parentPath: []
        )

        XCTAssertThrowsError(
            try generateSwiftCode(
                from: [nestedMessage],
                enums: [topLevelEnum],
                with: "App",
                includeProto: false,
                includeLocalIDFor: nil,
                includeBackingData: false,
                with: "Proto"
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("AppStatus"))
        }
    }

    func testNestedEnumDoesNotCollideWithTopLevelType() throws {
        // A nested enum lives inside an extension of its parent, so it
        // occupies a different namespace than top-level types.
        let message = ProtoMessage(name: "Status", fields: [], parentPath: [])
        let nestedEnum = ProtoEnum(
            name: "Status",
            cases: [ProtoEnumCase(name: "S_UNKNOWN", value: 0)],
            parentPath: ["Person"]
        )
        let parent = ProtoMessage(name: "Person", fields: [], parentPath: [])

        XCTAssertNoThrow(
            try generateSwiftCode(
                from: [message, parent],
                enums: [nestedEnum],
                with: "App",
                includeProto: false,
                includeLocalIDFor: nil,
                includeBackingData: false,
                with: "Proto"
            )
        )
    }

    func testLocalIDs() throws {
        let simpleMessageProtoMessage = ProtoMessage(
            name: "Person",
            fields: [
                ProtoField(
                    swiftPrefix: "App",
                    name: "name",
                    type: "string",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                )
            ],
            parentName: nil
        )

        let simpleMessageProtoMessageNoLocalID = ProtoMessage(
            name: "Dog",
            fields: [
                ProtoField(
                    swiftPrefix: "App",
                    name: "breed",
                    type: "string",
                    comment: nil,
                    isOptional: false,
                    isRepeated: false,
                    isMap: false,
                    isDeprecated: false
                )
            ],
            parentName: nil
        )


        let messages = [simpleMessageProtoMessage, simpleMessageProtoMessageNoLocalID]
        let enums: [ProtoEnum] = []

        let generatedCode = try generateSwiftCode(
            from: messages,
            enums: enums,
            with: "App",
            includeProto: true,
            includeLocalIDFor: ["Person"],
            includeBackingData: false,
            with: "Proto"
        )

        func containsExactlyOneInstance(of substring: String, in string: String) -> Bool {
            let components = string.components(separatedBy: substring)
            return components.count == 2
        }

        XCTAssert(containsExactlyOneInstance(of: "public let _localID = UUID()", in: generatedCode))
    }
}
