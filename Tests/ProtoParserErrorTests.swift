import XCTest
@testable import SwiftBuffet

final class ProtoParserErrorTests: XCTestCase {

    private func parseError(_ source: String) -> ParseError? {
        do {
            _ = try ProtoParser.parse(source, quite: true)
            return nil
        } catch let error as ParseError {
            return error
        } catch {
            XCTFail("Expected ParseError, got \(error)")
            return nil
        }
    }

    func testMissingSemicolonAfterField() {
        let proto = """
        message A {
        string x = 1
        }
        """
        let error = parseError(proto)
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.line, 3)
        XCTAssertEqual(error?.expected, "';'")
    }

    func testMissingBraceAfterMessageName() {
        let proto = "message A string x = 1; }"
        let error = parseError(proto)
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.line, 1)
        XCTAssertEqual(error?.expected, "'{'")
    }

    func testMissingFieldNumber() {
        let proto = """
        message A {
        string x = ;
        }
        """
        let error = parseError(proto)
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.line, 2)
        XCTAssertEqual(error?.expected, "a field number")
    }

    func testUnexpectedEndOfFileInsideMessage() {
        let proto = """
        message A {
        string x = 1;
        """
        let error = parseError(proto)
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.found, "end of file")
    }

    func testUnknownTopLevelStatement() {
        let proto = "rpc Foo (Bar) returns (Baz);"
        XCTAssertNotNil(parseError(proto))
    }

    func testOneofMembersAreParsedAsFields() throws {
        let proto = """
        message A {
        string x = 1;
        oneof choice {
        string a = 2;
        int32 b = 3;
        }
        string y = 4;
        }
        """
        let file = try ProtoParser.parse(proto, quite: true)
        XCTAssertEqual(file.messages.count, 1)
        XCTAssertEqual(file.messages[0].fields.map(\.name), ["x", "a", "b", "y"])
    }

    func testServiceIsSkippedWithoutError() throws {
        let proto = """
        service Greeter {
        rpc SayHello (HelloRequest) returns (HelloReply);
        }

        message HelloRequest {
        string name = 1;
        }
        """
        let file = try ProtoParser.parse(proto, quite: true)
        XCTAssertEqual(file.messages.map(\.name), ["HelloRequest"])
    }

    func testReservedIsSkippedSilently() throws {
        let proto = """
        message A {
        reserved 2, 15;
        reserved "foo", "bar";
        string x = 1;
        }
        """
        let file = try ProtoParser.parse(proto, quite: true)
        XCTAssertEqual(file.messages[0].fields.map(\.name), ["x"])
    }
}
