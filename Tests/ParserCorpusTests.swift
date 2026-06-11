import XCTest
@testable import SwiftBuffet

/// Characterization corpus for `parseProto`.
///
/// These tests pin the parsing contract established before the regex →
/// recursive-descent migration, including inputs the regex parser mishandled.
final class ParserCorpusTests: XCTestCase {

    func testEmptyMessageSingleLine() throws {
        let proto = "message Empty {}"
        let (messages, enums) = try parseProto(proto, swiftPrefix: "")
        XCTAssertEqual(enums.count, 0)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.name, "Empty")
        XCTAssertEqual(messages.first?.fields.count, 0)
    }

    func testSimpleMessageFieldTypes() throws {
        let proto = """
        message Person {
        string name = 1;
        int32 age = 2;
        bool is_active = 3;
        }
        """
        let (messages, _) = try parseProto(proto, swiftPrefix: "")
        XCTAssertEqual(messages.count, 1)
        let fields = messages[0].fields
        XCTAssertEqual(fields.map(\.name), ["name", "age", "is_active"])
        XCTAssertEqual(fields.map(\.type), ["string", "int32", "bool"])
        XCTAssertTrue(fields.allSatisfy { $0.isOptional == false })
        XCTAssertTrue(fields.allSatisfy { $0.isRepeated == false })
        XCTAssertTrue(fields.allSatisfy { $0.isMap == false })
        XCTAssertTrue(fields.allSatisfy { $0.isDeprecated == false })
    }

    func testMultipleTopLevelDeclarations() throws {
        let proto = """
        message A {
        string x = 1;
        }

        enum Color {
        COLOR_UNSPECIFIED = 0;
        COLOR_RED = 1;
        }

        message B {
        int32 y = 1;
        }
        """
        let (messages, enums) = try parseProto(proto, swiftPrefix: "")
        XCTAssertEqual(Set(messages.map(\.name)), ["A", "B"])
        XCTAssertEqual(enums.map(\.name), ["Color"])
        XCTAssertEqual(enums.first?.cases.count, 2)
        XCTAssertNil(messages.first?.parentName)
        XCTAssertNil(enums.first?.parentName)
    }

    func testNestedMessageTwoLevels() throws {
        let proto = """
        message Outer {
        string a = 1;
        message Middle {
        string b = 1;
        message Inner {
        string c = 1;
        }
        }
        }
        """
        let (messages, _) = try parseProto(proto, swiftPrefix: "")
        XCTAssertEqual(messages.count, 3)
        let outer = messages.first { $0.name == "Outer" }
        let middle = messages.first { $0.name == "Middle" }
        let inner = messages.first { $0.name == "Inner" }
        XCTAssertNil(outer?.parentName)
        XCTAssertEqual(middle?.parentName, "Outer")
        XCTAssertEqual(inner?.parentName, "Middle")
        XCTAssertEqual(outer?.fields.map(\.name), ["a"])
        XCTAssertEqual(middle?.fields.map(\.name), ["b"])
        XCTAssertEqual(inner?.fields.map(\.name), ["c"])
    }

    func testNestedEnumInMessage() throws {
        let proto = """
        message Person {
        enum Gender {
        GENDER_UNKNOWN = 0;
        GENDER_MALE = 1;
        }
        Gender gender = 1;
        }
        """
        let (messages, enums) = try parseProto(proto, swiftPrefix: "")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(enums.count, 1)
        XCTAssertEqual(enums.first?.parentName, "Person")
        XCTAssertEqual(enums.first?.cases.map(\.value), [0, 1])
        XCTAssertEqual(messages.first?.fields.map(\.type), ["Gender"])
    }

    func testOptionalAndRepeatedFields() throws {
        let proto = """
        message Bag {
        optional string label = 1;
        repeated int32 counts = 2;
        }
        """
        let (messages, _) = try parseProto(proto, swiftPrefix: "")
        let fields = messages[0].fields
        XCTAssertTrue(fields[0].isOptional)
        XCTAssertFalse(fields[0].isRepeated)
        XCTAssertTrue(fields[1].isRepeated)
        XCTAssertFalse(fields[1].isOptional)
    }

    func testMapFields() throws {
        let proto = """
        message Lookup {
        map<string, int32> scores = 1;
        map<string, Person> people = 2;
        }

        message Person {
        string name = 1;
        }
        """
        let (messages, _) = try parseProto(proto, swiftPrefix: "")
        let lookup = messages.first { $0.name == "Lookup" }!
        XCTAssertTrue(lookup.fields[0].isMap)
        XCTAssertEqual(lookup.fields[0].caseCorrectedBaseType, "[String: Int]")
        XCTAssertTrue(lookup.fields[1].isMap)
        XCTAssertEqual(lookup.fields[1].caseCorrectedBaseType, "[String: Person]")
    }

    func testDeprecatedFieldOption() throws {
        let proto = """
        message Address {
        string street = 1 [deprecated = true];
        string city = 2;
        }
        """
        let (messages, _) = try parseProto(proto, swiftPrefix: "")
        XCTAssertTrue(messages[0].fields[0].isDeprecated)
        XCTAssertFalse(messages[0].fields[1].isDeprecated)
    }

    func testDocCommentOnField() throws {
        let proto = """
        message Person {
        /** The person's legal name. */
        string name = 1;
        int32 age = 2;
        }
        """
        let (messages, _) = try parseProto(proto, swiftPrefix: "")
        let nameField = messages[0].fields.first { $0.name == "name" }!
        XCTAssertNotNil(nameField.comment)
        XCTAssertTrue(nameField.comment?.contains("legal name") == true)
        let ageField = messages[0].fields.first { $0.name == "age" }!
        XCTAssertNil(ageField.comment)
    }

    func testEnumCommonPrefixCases() throws {
        let proto = """
        enum Gender {
        GENDER_UNKNOWN = 0;
        GENDER_MALE = 1;
        GENDER_FEMALE = 2;
        }
        """
        let (_, enums) = try parseProto(proto, swiftPrefix: "")
        XCTAssertEqual(enums.count, 1)
        XCTAssertEqual(enums[0].cases.map(\.name), ["GENDER_UNKNOWN", "GENDER_MALE", "GENDER_FEMALE"])
        XCTAssertEqual(enums[0].cases.map(\.value), [0, 1, 2])
        let stripped = stripCommonPrefix(from: enums[0].cases)
        XCTAssertEqual(stripped.map(\.name), ["unknown", "male", "female"])
    }

    func testHeaderStatementsIgnored() throws {
        let proto = """
        syntax = "proto3";
        package com.example.app;
        import "google/protobuf/timestamp.proto";
        option java_package = "com.example";

        message Person {
        google.protobuf.Timestamp created_at = 1;
        }
        """
        let (messages, enums) = try parseProto(proto, swiftPrefix: "")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(enums.count, 0)
        XCTAssertEqual(messages[0].fields[0].type, "google.protobuf.Timestamp")
    }

    func testVariedWhitespace() throws {
        let proto = "message A {\n\tstring x = 1;\n\n\n  int32   y   =   2 ;\n}"
        let (messages, _) = try parseProto(proto, swiftPrefix: "")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].fields.map(\.name), ["x", "y"])
    }

    func testClosingBraceOnSameLineAsField() throws {
        let proto = "message A { string x = 1; }"
        let (messages, _) = try parseProto(proto, swiftPrefix: "")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.fields.map(\.name), ["x"])
    }

    func testClosingBraceIndented() throws {
        let proto = """
        message A {
            string x = 1;
            }
        """
        let (messages, _) = try parseProto(proto, swiftPrefix: "")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.fields.map(\.name), ["x"])
    }

    func testDocCommentsInAllPositions() throws {
        let proto = """
        /** File-level overview comment. */
        message Person {
        /** first */
        /** second comment wins */
        string name = 1;
        int32 age = 2;
        /** dangling comment before close */
        }
        /** between declarations */
        enum Plan {
        /** case comment */
        PLAN_FREE = 0;
        /** dangling in enum */
        }
        """
        let (messages, enums) = try parseProto(proto, swiftPrefix: "")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(enums.count, 1)
        XCTAssertEqual(messages[0].fields.map(\.name), ["name", "age"])
        XCTAssertTrue(messages[0].fields[0].comment?.contains("second comment wins") == true)
        XCTAssertNil(messages[0].fields[1].comment)
        XCTAssertEqual(enums[0].cases.map(\.name), ["PLAN_FREE"])
    }

    func testCustomParenthesizedFieldOptions() throws {
        let proto = """
        message User {
        string email = 1 [(validate.rules).string.min_len = 1];
        string name = 2 [(validate.rules).string = { min_len: 1, max_len: 64 }];
        float ratio = 3 [some_option = 0.5];
        string street = 4 [deprecated = true, (custom.opt) = "x"];
        }
        """
        let (messages, _) = try parseProto(proto, swiftPrefix: "")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].fields.map(\.name), ["email", "name", "ratio", "street"])
        XCTAssertFalse(messages[0].fields[0].isDeprecated)
        XCTAssertFalse(messages[0].fields[2].isDeprecated)
        XCTAssertTrue(messages[0].fields[3].isDeprecated)
    }

    func testAggregateOptionValuesIgnored() throws {
        let proto = """
        syntax = "proto3";
        option (my.file_option) = { key: "value" nested: { flag: true } };

        message Api {
        string path = 1;
        }
        """
        let (messages, _) = try parseProto(proto, swiftPrefix: "")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].fields.map(\.name), ["path"])
    }

    func testOneofMembersBecomeFields() throws {
        let proto = """
        message Event {
        string id = 1;
        oneof payload {
        string click = 2;
        int32 view = 3;
        }
        string source = 4;
        }
        """
        let (messages, _) = try parseProto(proto, swiftPrefix: "")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(
            messages[0].fields.map(\.name),
            ["id", "click", "view", "source"]
        )
    }

    func testDeepNestingPreservesFullParentPath() throws {
        let proto = """
        message A {
        message B {
        enum Status {
        STATUS_UNSPECIFIED = 0;
        }
        Status status = 1;
        }
        }
        """
        let (messages, enums) = try parseProto(proto, swiftPrefix: "")
        let b = messages.first { $0.name == "B" }!
        XCTAssertEqual(b.parentName, "A")
        XCTAssertEqual(b.fullName, "A.B")
        let status = enums.first { $0.name == "Status" }!
        XCTAssertEqual(status.parentName, "B")
        XCTAssertEqual(status.fullName, "A.B.Status")
    }

    func testKeywordLikeFieldNames() throws {
        let proto = """
        message Config {
        string message_text = 1;
        string option = 2;
        }
        """
        let (messages, _) = try parseProto(proto, swiftPrefix: "")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].fields.map(\.name), ["message_text", "option"])
    }
}
