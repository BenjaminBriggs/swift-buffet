import Testing
import Foundation
@testable import SwiftBuffet

@Suite struct ProtoParserErrorTests {

    private func parseError(_ source: String) -> ParseError? {
        do {
            _ = try ProtoParser.parse(source, verbose: false)
            return nil
        } catch let error as ParseError {
            return error
        } catch {
            Issue.record("Expected ParseError, got \(error)")
            return nil
        }
    }

    @Test func missingSemicolonAfterField() {
        let proto = """
        message A {
        string x = 1
        }
        """
        let error = parseError(proto)
        #expect(error != nil)
        #expect(error?.line == 3)
        #expect(error?.expected == "';'")
    }

    @Test func missingBraceAfterMessageName() {
        let proto = "message A string x = 1; }"
        let error = parseError(proto)
        #expect(error != nil)
        #expect(error?.line == 1)
        #expect(error?.expected == "'{'")
    }

    @Test func missingFieldNumber() {
        let proto = """
        message A {
        string x = ;
        }
        """
        let error = parseError(proto)
        #expect(error != nil)
        #expect(error?.line == 2)
        #expect(error?.expected == "a field number")
    }

    @Test func unexpectedEndOfFileInsideMessage() {
        let proto = """
        message A {
        string x = 1;
        """
        let error = parseError(proto)
        #expect(error != nil)
        #expect(error?.found == "end of file")
    }

    @Test func unknownTopLevelStatement() {
        let proto = "rpc Foo (Bar) returns (Baz);"
        #expect(parseError(proto) != nil)
    }

    @Test func oneofMembersAreParsedAsFields() throws {
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
        let file = try ProtoParser.parse(proto, verbose: false)
        #expect(file.messages.count == 1)
        #expect(file.messages[0].fields.map(\.name) == ["x", "a", "b", "y"])
    }

    @Test func serviceIsSkippedWithoutError() throws {
        let proto = """
        service Greeter {
        rpc SayHello (HelloRequest) returns (HelloReply);
        }

        message HelloRequest {
        string name = 1;
        }
        """
        let file = try ProtoParser.parse(proto, verbose: false)
        #expect(file.messages.map(\.name) == ["HelloRequest"])
    }

    @Test func reservedIsSkippedSilently() throws {
        let proto = """
        message A {
        reserved 2, 15;
        reserved "foo", "bar";
        string x = 1;
        }
        """
        let file = try ProtoParser.parse(proto, verbose: false)
        #expect(file.messages[0].fields.map(\.name) == ["x"])
    }
}
