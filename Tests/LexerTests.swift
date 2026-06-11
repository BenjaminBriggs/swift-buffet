import XCTest
@testable import SwiftBuffet

final class LexerTests: XCTestCase {

    private func kinds(_ source: String) throws -> [TokenKind] {
        try Lexer.tokenize(source).map(\.kind)
    }

    func testPunctuation() throws {
        XCTAssertEqual(
            try kinds("{ } = ; < > , [ ] ( ) ."),
            [.openBrace, .closeBrace, .equals, .semicolon,
             .openAngle, .closeAngle, .comma, .openBracket, .closeBracket,
             .openParen, .closeParen, .dot,
             .eof]
        )
    }

    func testIdentifiersAndKeywordsAreIdentifiers() throws {
        XCTAssertEqual(
            try kinds("message optional foo_bar Baz9"),
            [.identifier("message"), .identifier("optional"),
             .identifier("foo_bar"), .identifier("Baz9"), .eof]
        )
    }

    func testIntLiterals() throws {
        XCTAssertEqual(
            try kinds("0 42 -7"),
            [.intLiteral(0), .intLiteral(42), .intLiteral(-7), .eof]
        )
    }

    func testStringLiteral() throws {
        XCTAssertEqual(
            try kinds(#"import "google/protobuf/duration.proto";"#),
            [.identifier("import"),
             .stringLiteral("google/protobuf/duration.proto"),
             .semicolon, .eof]
        )
    }

    func testDocCommentCapturedVerbatim() throws {
        XCTAssertEqual(
            try kinds("/** hi there */ string"),
            [.docComment("/** hi there */"), .identifier("string"), .eof]
        )
    }

    func testLineCommentsSkipped() throws {
        XCTAssertEqual(
            try kinds("foo // comment text ; { }\nbar"),
            [.identifier("foo"), .identifier("bar"), .eof]
        )
    }

    func testPlainBlockCommentsSkipped() throws {
        XCTAssertEqual(
            try kinds("foo /* not a doc comment */ bar"),
            [.identifier("foo"), .identifier("bar"), .eof]
        )
    }

    func testPositions() throws {
        let tokens = try Lexer.tokenize("message Person {\n  string name = 1;\n}")
        let message = tokens[0]
        XCTAssertEqual(message.line, 1)
        XCTAssertEqual(message.column, 1)
        let string = tokens[3]
        XCTAssertEqual(string.kind, .identifier("string"))
        XCTAssertEqual(string.line, 2)
        XCTAssertEqual(string.column, 3)
        let closeBrace = tokens[tokens.count - 2]
        XCTAssertEqual(closeBrace.kind, .closeBrace)
        XCTAssertEqual(closeBrace.line, 3)
        XCTAssertEqual(closeBrace.column, 1)
    }

    func testUnterminatedStringThrows() {
        XCTAssertThrowsError(try Lexer.tokenize(#"option x = "unclosed"#)) { error in
            guard let parseError = error as? ParseError else {
                return XCTFail("Expected ParseError, got \(error)")
            }
            XCTAssertEqual(parseError.line, 1)
        }
    }

    func testUnterminatedBlockCommentThrows() {
        XCTAssertThrowsError(try Lexer.tokenize("foo /** never closed")) { error in
            XCTAssertTrue(error is ParseError)
        }
    }

    func testUnknownCharactersBecomeTokens() throws {
        XCTAssertEqual(
            try kinds("get: \"/v1\""),
            [.identifier("get"), .unknown(":"), .stringLiteral("/v1"), .eof]
        )
    }

    func testUnknownCharacterInParsedPositionThrows() {
        XCTAssertThrowsError(
            try ProtoParser.parse("message § {}", quite: true)
        ) { error in
            guard let parseError = error as? ParseError else {
                return XCTFail("Expected ParseError, got \(error)")
            }
            XCTAssertEqual(parseError.column, 9)
        }
    }
}
