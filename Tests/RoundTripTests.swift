import XCTest
import SwiftParser
@testable import SwiftBuffet

/// Round-trip validation: every proto in the corpus must generate Swift that
/// parses with zero diagnostics, across all generator flag combinations.
final class RoundTripTests: XCTestCase {

    private let corpus: [String: String] = [
        "empty message": "message Empty {}",
        "simple": """
        message Person {
        string name = 1;
        int32 age = 2;
        bool is_active = 3;
        }
        """,
        "nested messages": """
        message Outer {
        string a = 1;
        message Middle {
        string b = 1;
        message Inner {
        string c = 1;
        }
        }
        Middle middle = 2;
        }
        """,
        "nested enum": """
        message Person {
        enum Gender {
        GENDER_UNKNOWN = 0;
        GENDER_MALE = 1;
        }
        Gender gender = 1;
        }
        """,
        "modifiers and maps": """
        message Bag {
        optional string label = 1;
        repeated int32 counts = 2;
        map<string, int32> scores = 3;
        optional bool flag = 4;
        repeated Person friends = 5;
        }

        message Person {
        string name = 1;
        }
        """,
        "well-known types and URL": """
        message Profile {
        /** Doc comment here. */
        string avatar_url = 1;
        optional string website_url = 2;
        google.protobuf.Duration session = 3;
        google.protobuf.Timestamp created_at = 4;
        string description = 5 [deprecated = true];
        }
        """,
        "top-level enum": """
        enum Plan {
        PLAN_UNSPECIFIED = 0;
        PLAN_FREE = 1;
        PLAN_PAID = 2;
        }
        """,
        "keyword-named field with optional message": """
        message Config {
        string message_text = 1;
        optional Inner inner = 2;
        message Inner {
        int32 x = 1;
        }
        }
        """,
    ]

    func testGeneratedSwiftParsesCleanly() throws {
        for (label, proto) in corpus {
            let (messages, enums) = try parseProto(proto, swiftPrefix: "App")
            for includeProto in [false, true] {
                for backingData in [false, true] {
                    let generated = try generateSwiftCode(
                        from: messages,
                        enums: enums,
                        with: "App",
                        includeProto: includeProto,
                        includeLocalIDFor: messages.map(\.name),
                        includeBackingData: backingData,
                        with: "Proto"
                    )
                    let tree = Parser.parse(source: generated)
                    XCTAssertFalse(
                        tree.hasError,
                        "Generated Swift for corpus entry '\(label)' (includeProto: \(includeProto), backingData: \(backingData)) has syntax errors:\n\(generated)"
                    )
                }
            }
        }
    }
}
