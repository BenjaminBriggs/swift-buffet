import Foundation

/// A recursive-descent parser for the subset of the proto language that
/// SwiftBuffet generates code for.
///
/// Header statements (`syntax`, `package`, `import`, `option`) are consumed
/// and ignored. Constructs the generator has no representation for (`oneof`,
/// `service`, `extend`) are skipped with a warning. `reserved` statements are
/// skipped silently. Anything malformed throws `ParseError`.
struct ProtoParser {

    static func parse(_ source: String, quite: Bool) throws -> ProtoFileNode {
        var parser = ProtoParser(
            tokens: try Lexer.tokenize(source),
            quite: quite
        )
        return try parser.parseFile()
    }

    private let tokens: [Token]
    private let quite: Bool
    private var index = 0

    private init(tokens: [Token], quite: Bool) {
        self.tokens = tokens
        self.quite = quite
    }

    // MARK: - Grammar

    private mutating func parseFile() throws -> ProtoFileNode {
        var file = ProtoFileNode()
        loop: while true {
            switch peek().kind {
            case .docComment:
                advance()
            case .identifier(let keyword):
                switch keyword {
                case "message":
                    file.messages.append(try parseMessage())
                case "enum":
                    file.enums.append(try parseEnum())
                case "syntax", "package", "import", "option":
                    try skipToSemicolon()
                case "service", "extend":
                    try skipUnsupportedBlock(named: keyword)
                default:
                    throw unexpected(expected: "'message', 'enum', or a header statement")
                }
            default:
                break loop
            }
        }
        try expect(.eof, description: "'message', 'enum', or a header statement")
        return file
    }

    private mutating func parseMessage() throws -> MessageNode {
        advance() // "message"
        let name = try expectIdentifier(description: "a message name")
        try expect(.openBrace, description: "'{'")
        var node = MessageNode(name: name)

        while peek().kind != .closeBrace {
            let comment = takeDocComments()
            if peek().kind == .closeBrace {
                break // dangling comment before the closing brace
            }

            guard case .identifier(let word) = peek().kind else {
                throw unexpected(expected: "a field, 'message', 'enum', or '}'")
            }

            switch word {
            case "message" where isDeclarationLookahead():
                node.messages.append(try parseMessage())
            case "enum" where isDeclarationLookahead():
                node.enums.append(try parseEnum())
            case "option", "reserved":
                try skipToSemicolon()
            case "oneof" where isDeclarationLookahead():
                try parseOneofMembers(into: &node)
            default:
                node.fields.append(try parseField(comment: comment))
            }
        }
        try expect(.closeBrace, description: "'}'")
        return node
    }

    /// Parses a `oneof` block, adding its member fields to the enclosing
    /// message as ordinary fields — matching what the generated structs have
    /// always contained for oneof members.
    private mutating func parseOneofMembers(into node: inout MessageNode) throws {
        advance() // "oneof"
        advance() // name
        try expect(.openBrace, description: "'{'")
        while peek().kind != .closeBrace {
            let comment = takeDocComments()
            if peek().kind == .closeBrace {
                break
            }
            if case .identifier("option") = peek().kind {
                try skipToSemicolon()
                continue
            }
            node.fields.append(try parseField(comment: comment))
        }
        try expect(.closeBrace, description: "'}'")
    }

    private mutating func parseField(comment: String?) throws -> FieldNode {
        var isOptional = false
        var isRepeated = false
        var isMap = false
        let type: String

        if case .identifier(let modifier) = peek().kind,
           ["optional", "repeated"].contains(modifier),
           isModifierLookahead() {
            isOptional = modifier == "optional"
            isRepeated = modifier == "repeated"
            advance()
        }

        if case .identifier("map") = peek().kind, peekNext().kind == .openAngle {
            isMap = true
            advance() // "map"
            try expect(.openAngle, description: "'<'")
            let keyType = try parseTypeName()
            try expect(.comma, description: "','")
            let valueType = try parseTypeName()
            try expect(.closeAngle, description: "'>'")
            // Legacy model shape: map types are stored as "<key, value>".
            type = "<\(keyType), \(valueType)>"
        } else {
            type = try parseTypeName()
        }

        let name = try expectIdentifier(description: "a field name")
        try expect(.equals, description: "'='")
        guard case .intLiteral = peek().kind else {
            throw unexpected(expected: "a field number")
        }
        advance()

        let isDeprecated = try parseFieldOptions()
        try expect(.semicolon, description: "';'")

        return FieldNode(
            name: name,
            type: type,
            comment: comment,
            isOptional: isOptional,
            isRepeated: isRepeated,
            isMap: isMap,
            isDeprecated: isDeprecated
        )
    }

    /// Scans an optional `[...]` option list, extracting only `deprecated = true`.
    ///
    /// Everything else — parenthesized custom options, aggregate `{...}`
    /// values, float literals — is skipped without being understood, so an
    /// option this tool doesn't support can never fail the parse.
    private mutating func parseFieldOptions() throws -> Bool {
        guard peek().kind == .openBracket else { return false }
        advance()
        var isDeprecated = false
        var depth = 1
        while depth > 0 {
            switch peek().kind {
            case .openBracket, .openBrace, .openParen, .openAngle:
                depth += 1
            case .closeBracket, .closeBrace, .closeParen, .closeAngle:
                depth -= 1
            case .identifier("deprecated") where depth == 1:
                if peekNext().kind == .equals,
                   case .identifier("true") = peek(ahead: 2).kind {
                    isDeprecated = true
                }
            case .eof:
                throw unexpected(expected: "']'")
            default:
                break
            }
            advance()
        }
        return isDeprecated
    }

    private mutating func parseEnum() throws -> EnumNode {
        advance() // "enum"
        let name = try expectIdentifier(description: "an enum name")
        try expect(.openBrace, description: "'{'")
        var node = EnumNode(name: name)

        while peek().kind != .closeBrace {
            _ = takeDocComments()
            if peek().kind == .closeBrace {
                break // dangling comment before the closing brace
            }

            guard case .identifier(let word) = peek().kind else {
                throw unexpected(expected: "an enum case or '}'")
            }

            if ["option", "reserved"].contains(word), peekNext().kind != .equals {
                try skipToSemicolon()
                continue
            }

            let caseName = try expectIdentifier(description: "an enum case name")
            try expect(.equals, description: "'='")
            guard case .intLiteral(let value) = peek().kind else {
                throw unexpected(expected: "an enum case value")
            }
            advance()
            _ = try parseFieldOptions()
            try expect(.semicolon, description: "';'")
            node.cases.append(ProtoEnumCase(name: caseName, value: value))
        }
        try expect(.closeBrace, description: "'}'")
        return node
    }

    /// Parses a possibly dotted type name like `google.protobuf.Timestamp`.
    private mutating func parseTypeName() throws -> String {
        var parts = [try expectIdentifier(description: "a type name")]
        while peek().kind == .dot {
            advance()
            parts.append(try expectIdentifier(description: "a type name"))
        }
        return parts.joined(separator: ".")
    }

    // MARK: - Skipping

    /// Skips to the statement-terminating semicolon, stepping over balanced
    /// `{...}` regions so aggregate option values can't end the skip early.
    private mutating func skipToSemicolon() throws {
        var depth = 0
        while true {
            switch peek().kind {
            case .semicolon where depth == 0:
                advance()
                return
            case .openBrace:
                depth += 1
            case .closeBrace:
                depth -= 1
            case .eof:
                throw unexpected(expected: "';'")
            default:
                break
            }
            advance()
        }
    }

    private mutating func skipUnsupportedBlock(named keyword: String) throws {
        if quite == false {
            print("Warning: skipping unsupported '\(keyword)' block")
        }
        advance() // keyword
        // Skip everything up to the opening brace (names, rpc signatures, etc.).
        while peek().kind != .openBrace {
            if peek().kind == .eof {
                throw unexpected(expected: "'{'")
            }
            advance()
        }
        advance() // "{"
        var depth = 1
        while depth > 0 {
            switch peek().kind {
            case .openBrace: depth += 1
            case .closeBrace: depth -= 1
            case .eof:
                throw unexpected(expected: "'}'")
            default:
                break
            }
            advance()
        }
    }

    // MARK: - Lookahead

    /// True when the current keyword starts a nested declaration
    /// (`message Name {` / `enum Name {`) rather than acting as a field type.
    private func isDeclarationLookahead() -> Bool {
        guard case .identifier = peekNext().kind else { return false }
        return peek(ahead: 2).kind == .openBrace
    }

    /// True when `optional`/`repeated` is a modifier rather than a field of
    /// that name (`string optional = 1;`) — a modifier is followed by a type,
    /// never by `=`.
    private func isModifierLookahead() -> Bool {
        peekNext().kind != .equals
    }

    // MARK: - Token primitives

    private func peek(ahead: Int = 0) -> Token {
        let target = min(index + ahead, tokens.count - 1)
        return tokens[target]
    }

    private func peekNext() -> Token {
        peek(ahead: 1)
    }

    @discardableResult
    private mutating func advance() -> Token {
        let token = peek()
        if index < tokens.count - 1 {
            index += 1
        }
        return token
    }

    /// Consumes a run of consecutive doc comments, returning the last one —
    /// the comment adjacent to the declaration it documents.
    private mutating func takeDocComments() -> String? {
        var comment: String?
        while case .docComment(let text) = peek().kind {
            comment = text
            advance()
        }
        return comment
    }

    private mutating func expect(
        _ kind: TokenKind,
        description: String
    ) throws {
        guard peek().kind == kind else {
            throw unexpected(expected: description)
        }
        advance()
    }

    private mutating func expectIdentifier(description: String) throws -> String {
        guard case .identifier(let text) = peek().kind else {
            throw unexpected(expected: description)
        }
        advance()
        return text
    }

    private func unexpected(expected: String) -> ParseError {
        let token = peek()
        let found: String
        switch token.kind {
        case .identifier(let text): found = "'\(text)'"
        case .intLiteral(let value): found = "'\(value)'"
        case .stringLiteral(let text): found = "\"\(text)\""
        case .docComment: found = "a comment"
        case .openBrace: found = "'{'"
        case .closeBrace: found = "'}'"
        case .equals: found = "'='"
        case .semicolon: found = "';'"
        case .openAngle: found = "'<'"
        case .closeAngle: found = "'>'"
        case .comma: found = "','"
        case .openBracket: found = "'['"
        case .closeBracket: found = "']'"
        case .openParen: found = "'('"
        case .closeParen: found = "')'"
        case .dot: found = "'.'"
        case .unknown(let character): found = "'\(character)'"
        case .eof: found = "end of file"
        }
        return ParseError(
            line: token.line,
            column: token.column,
            expected: expected,
            found: found
        )
    }
}
