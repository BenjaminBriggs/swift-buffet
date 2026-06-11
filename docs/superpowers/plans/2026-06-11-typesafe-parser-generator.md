# Type-Safe Parser and Generator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace regex-based .proto parsing with a lexer + recursive-descent parser, and string-concatenation Swift generation with SwiftSyntax builders, preceded by a characterization test suite.

**Architecture:** `.proto text → Lexer → [Token] → ProtoParser → AST tree → flatten → [ProtoMessage]/[ProtoEnum] → Generator (SwiftSyntax) → formatted source`. `Models.swift` stays as the generator contract so the parser (Phase 1) and generator (Phase 2) swaps are independent. Phase 0 builds the safety net first.

**Tech Stack:** Swift 5.10, XCTest, swift-syntax (`510.0.0..<602.0.0`, Phase 2 only). Spec: `docs/superpowers/specs/2026-06-11-typesafe-parser-generator-design.md`.

**Baseline:** 7 tests passing on `feature/byond-regex`. Dead code confirmed (no call sites): `writeCodingKeys`, `writeCodableInit(for message:)`, `writeCodableInit(for protoEnum:)`, `writeTimeIntervalHelper`, `writeDateFormatter` — not ported in Phase 2.

**Known latent bug (fix in Phase 2, note in commit):** `Generator.swift:289` emits `self.x = <protoName>` instead of `self.x = x` inside the `if let x = Type(proto:...)` branch — wrong whenever `caseCorrectName != caseCorrectProtoName` (e.g. `description`). Phase 2 emits `self.x = x`.

**File map:**

| File | Phase | Action |
|---|---|---|
| `Sources/SwiftBuffet/Parser.swift` | 0 | add `parseProto` wrapper; 1: gut regex internals, keep `parseProto` |
| `Tests/ParserTests.swift` | 0 | migrate to `parseProto` |
| `Tests/ParserCorpusTests.swift` | 0 | create — input matrix, `XCTExpectFailure` on known regex bugs |
| `Tests/GoldenTests.swift` | 0 | create — full-pipeline snapshots; re-baselined in Phase 2 |
| `Sources/SwiftBuffet/Lexer.swift` | 1 | create — `Token`, `TokenKind`, `ParseError`, `Lexer` |
| `Tests/LexerTests.swift` | 1 | create |
| `Sources/SwiftBuffet/AST.swift` | 1 | create — `ProtoFileNode`, `MessageNode`, `EnumNode`, `FieldNode`, flatten |
| `Sources/SwiftBuffet/ProtoParser.swift` | 1 | create — recursive descent |
| `Tests/ProtoParserErrorTests.swift` | 1 | create |
| `Sources/SwiftBuffet/Regex.swift` | 1 | delete |
| `Package.swift` | 2 | add swift-syntax |
| `Sources/SwiftBuffet/Generator.swift` | 2 | rewrite with SwiftSyntaxBuilder |
| `Tests/RoundTripTests.swift` | 2 | create — SwiftParser diagnostics check |

---

## Phase 0 — Characterization tests

### Task 0.1: `parseProto` stable entry point

**Files:** Modify `Sources/SwiftBuffet/Parser.swift`, `Tests/ParserTests.swift`, `Sources/SwiftBuffet/main.swift`

- [ ] **Step 1:** Add to `Parser.swift`:

```swift
/// Stable parsing entry point. The implementation behind this function is
/// replaced in later phases; its contract is pinned by the test corpus.
func parseProto(
    _ content: String,
    swiftPrefix: String,
    verbose: Bool = false,
    quite: Bool = true
) throws -> ([ProtoMessage], [ProtoEnum]) {
    var mutableContent = content
    return parseContent(
        &mutableContent,
        parent: nil,
        with: swiftPrefix,
        verbose: verbose,
        quite: quite
    )
}
```

- [ ] **Step 2:** Point `parseProtoFile` and the two `parseContent` call sites in `ParserTests.swift` at `parseProto` (tests become `let (messages, enums) = try parseProto(protoFileContent, swiftPrefix: "MyApp")`, content no longer `var`).
- [ ] **Step 3:** `swift test` — 7 tests pass.
- [ ] **Step 4:** Commit: `test: add parseProto stable entry point`

### Task 0.2: Parser corpus tests

**Files:** Create `Tests/ParserCorpusTests.swift`

- [ ] **Step 1:** Write corpus tests calling `parseProto`, asserting model structure. Matrix (one test fn per row):
  - empty message `message Empty {}` on one line
  - simple message, 3 field types
  - multiple top-level messages and a top-level enum
  - nested message two levels deep (`Outer > Middle > Inner`), asserting `parentName` chain
  - nested enum in message
  - optional / repeated fields
  - `map<string, int32>` and `map<string, OtherMessage>` fields (assert `isMap`, type `<string, int32>` shape via `caseCorrectedBaseType == "[String: Int]"`)
  - `[deprecated = true]` field option (assert `isDeprecated`)
  - `/** doc */` comment on a field (assert `comment` non-nil)
  - enum with common prefix cases (`GENDER_UNKNOWN = 0; GENDER_MALE = 1;`)
  - `syntax`/`package`/`import`/`option` header lines present
  - varied whitespace: tabs, no indentation, extra blank lines
  - closing brace on same line as last field: `message A { string x = 1; }`
  - closing brace indented (not column 0)
  - field named with a keyword-ish word: `string message_text = 1;` and `string option = 1;`
- [ ] **Step 2:** `swift test` — record which corpus tests fail under the regex implementation.
- [ ] **Step 3:** Wrap exactly the failing assertions in `XCTExpectFailure("regex parser known bug — fixed in Phase 1") { ... }`. Suite green.
- [ ] **Step 4:** Commit: `test: add parser characterization corpus`

### Task 0.3: Golden snapshot tests

**Files:** Create `Tests/GoldenTests.swift`

- [ ] **Step 1:** Two goldens, full pipeline `parseProto` → `generateSwiftCode`:
  - `testGoldenExampleProto` — the contents of `Example/Sources/example.proto` inlined, all generator flags on (`includeProto: true`, `includeLocalIDFor: ["Person"]`, `includeBackingData: true`).
  - `testGoldenKitchenSink` — proto with nested message, nested enum, map, optional, repeated, doc comment, deprecated, Duration + Timestamp fields.
  Each asserts `XCTAssertEqual(generated, expected)` with `expected` initially empty.
- [ ] **Step 2:** Run, copy actual output into `expected` (characterization baseline). Re-run — green.
- [ ] **Step 3:** Commit: `test: add golden snapshot tests for generator output`

---

## Phase 1 — Lexer + Parser

### Task 1.1: Lexer

**Files:** Create `Sources/SwiftBuffet/Lexer.swift`, `Tests/LexerTests.swift`

- [ ] **Step 1:** Write failing `LexerTests`: punctuation kinds, identifiers, int literals (incl. negative), string literals, doc comment captured verbatim (`/** hi */`), line comments skipped, line/column positions, unterminated string/block comment throw `ParseError`.
- [ ] **Step 2:** Implement:

```swift
struct ParseError: Error, CustomStringConvertible, Equatable {
    let line: Int
    let column: Int
    let expected: String
    let found: String
    var description: String {
        "Parse error at line \(line), column \(column): expected \(expected), found \(found)"
    }
}

enum TokenKind: Equatable {
    case identifier(String)
    case intLiteral(Int)
    case stringLiteral(String)
    case docComment(String)   // raw, including /** and */
    case openBrace, closeBrace, equals, semicolon
    case openAngle, closeAngle, comma, openBracket, closeBracket, dot
    case eof
}

struct Token: Equatable {
    let kind: TokenKind
    let line: Int
    let column: Int
}

struct Lexer {
    static func tokenize(_ source: String) throws -> [Token] { ... }
}
```

  Single pass over `source` tracking line/column. `//` → skip to newline. `/*` without second `*` → skip to `*/` (plain comment); `/**` → capture to `*/` as `docComment`. Keywords are NOT special — they lex as `identifier`. `-123` lexes as `intLiteral(-123)`.
- [ ] **Step 3:** `swift test --filter LexerTests` — pass.
- [ ] **Step 4:** Commit: `feat: add proto lexer`

### Task 1.2: AST + recursive-descent parser

**Files:** Create `Sources/SwiftBuffet/AST.swift`, `Sources/SwiftBuffet/ProtoParser.swift`, `Tests/ProtoParserErrorTests.swift`

- [ ] **Step 1:** AST + flatten in `AST.swift`:

```swift
struct ProtoFileNode { var messages: [MessageNode] = []; var enums: [EnumNode] = [] }
struct MessageNode {
    let name: String
    var fields: [FieldNode] = []
    var messages: [MessageNode] = []
    var enums: [EnumNode] = []
}
struct EnumNode { let name: String; var cases: [ProtoEnumCase] = [] }
struct FieldNode {
    let name: String
    let type: String          // map fields use "<key, value>" to match legacy model shape
    let comment: String?
    let isOptional: Bool
    let isRepeated: Bool
    let isMap: Bool
    let isDeprecated: Bool
}

func flatten(
    _ file: ProtoFileNode,
    swiftPrefix: String
) -> ([ProtoMessage], [ProtoEnum]) { ... }
// Recurse: each MessageNode → ProtoMessage(parentName: immediate parent name),
// EnumNode → ProtoEnum(parentName:), FieldNode → ProtoField(swiftPrefix:...).
```

- [ ] **Step 2:** Failing error tests in `ProtoParserErrorTests.swift`: missing `;` after field, missing `{` after message name, missing field number, unexpected EOF inside message — each asserts thrown `ParseError` line/column. Plus: `oneof`/`service` skipped with no throw; `reserved 2, 15;` silent.
- [ ] **Step 3:** Implement `ProtoParser`:

```swift
struct ProtoParser {
    static func parse(_ source: String, quite: Bool) throws -> ProtoFileNode

    // peek() / advance() / expect(_ kind:) -> Token primitives over [Token].
    // parseFile: loop on identifier:
    //   "message" → parseMessage | "enum" → parseEnum
    //   "syntax" | "package" | "import" | "option" → skipToSemicolon
    //   "service" | "extend" → warn (respect quite) + skipBraceBlock
    //   else → throw ParseError
    // parseMessage: name, "{", body until "}":
    //   docComment? then identifier:
    //     "message" + ident + "{"-lookahead → nested parseMessage
    //     "enum" + ident + "{"-lookahead → nested parseEnum
    //     "option" | "reserved" → skipToSemicolon (silent)
    //     "oneof" → warn + skipBraceBlock
    //     "map" → "<" type "," type ">" name "=" int options? ";"
    //               type stored as "<\(key), \(value)>"
    //     "optional" | "repeated" (when followed by a type, not "=") → modifier
    //     then: type name "=" int options? ";"
    //   type → identifier ("." identifier)* joined with "."
    //   options → "[" ident "=" (ident|literal) ("," ...)* "]";
    //             isDeprecated = (name == "deprecated" && value == "true")
    // parseEnum: name, "{", (ident "=" int options? ";" | "option"/"reserved" skip)* "}"
    // Keyword-as-name disambiguation is by lookahead: "message" followed by
    //   ident + "{" is a declaration; anything else is a type/name token.
}
```

- [ ] **Step 4:** `swift test --filter ProtoParserErrorTests` — pass.
- [ ] **Step 5:** Commit: `feat: add recursive-descent proto parser and AST`

### Task 1.3: Swap implementations, delete regex

**Files:** Modify `Sources/SwiftBuffet/Parser.swift`, `Tests/ParserCorpusTests.swift`; Delete `Sources/SwiftBuffet/Regex.swift`

- [ ] **Step 1:** `parseProto` body becomes:

```swift
let file = try ProtoParser.parse(content, quite: quite)
return flatten(file, swiftPrefix: swiftPrefix)
```

  Delete `parseContent`, `processMessage`, `processEnum`, `parseMessageFields`, `parseEnumCases`, and `Regex.swift`. `parseProtoFile` keeps its signature, calls `parseProto`.
- [ ] **Step 2:** Remove every `XCTExpectFailure` wrapper from `ParserCorpusTests.swift`.
- [ ] **Step 3:** `swift test` — full suite green, including goldens (byte-identical output proves parser parity).
- [ ] **Step 4:** Commit: `feat: replace regex parsing with lexer and recursive-descent parser`

---

## Phase 2 — SwiftSyntax generator

### Task 2.1: Dependency

**Files:** Modify `Package.swift`

- [ ] **Step 1:** Add `.package(url: "https://github.com/swiftlang/swift-syntax.git", "510.0.0"..<"602.0.0")` and products `SwiftSyntax`, `SwiftSyntaxBuilder`, `SwiftParser` to the `SwiftBuffet` target.
- [ ] **Step 2:** `swift build` — resolves and compiles.
- [ ] **Step 3:** Commit: `build: add swift-syntax dependency`

### Task 2.2: Rewrite generator

**Files:** Rewrite `Sources/SwiftBuffet/Generator.swift`; Modify `Sources/SwiftBuffet/main.swift`, `Tests/GeneratorTests.swift`, `Tests/GoldenTests.swift`

- [ ] **Step 1:** `generateSwiftCode` becomes `throws -> String`, building a `SourceFileSyntax` and returning `.formatted().description`. Structure (one builder fn per current writer; interpolated SwiftSyntaxBuilder throughout, `\(raw:)` for names):
  - `structDecl(for message:)` → `try StructDeclSyntax("public struct \(raw: prefixedName): Hashable, Equatable, Sendable")` with members: properties (doc comments as leading `.lineComment` trivia, deprecated notice as `///` trivia), `_localID`/`_backingData` when flagged, memberwise `InitializerDeclSyntax`, and when `includeProto` the `init?(data:)` + `init?(proto:)`.
  - `protoInitAssignments(for field:)` ports the branch ladder from `writeMessageProtoInit` verbatim — repeated/compactMap, map/reduce, TimeInterval/.timeInterval, Date/.date, URL (optional and guarded), int via `Int(exactly:)!`, primitive passthrough, message types via `init?(proto:)` — **fixing the `self.x = x` bug at Generator.swift:289**.
  - `enumDecl(for protoEnum:)` → `EnumDeclSyntax`, raw values from `stripCommonPrefix` zip, proto init when `includeProto`; nested enums wrapped in `try ExtensionDeclSyntax("extension \(raw: prefixedParent)")`.
  - Do NOT port dead code: `writeCodingKeys`, both `writeCodableInit`s, `writeTimeIntervalHelper`, `writeDateFormatter`. Delete `TimeInterval+String.swift`’s `readFileContents` use only if now-unreferenced.
- [ ] **Step 2:** Propagate `try` (main.swift `run()` already throws; tests add `try`).
- [ ] **Step 3:** `swift test --filter GeneratorTests` — semantic assertions pass unchanged. Adjust builder code, not the assertions, on failure.
- [ ] **Step 4:** Re-baseline the two goldens to the new formatted output. Eyeball the diff: cosmetic only + the line-289 fix.
- [ ] **Step 5:** Commit: `feat: generate Swift with SwiftSyntax instead of string concatenation`

### Task 2.3: Round-trip validation + end-to-end

**Files:** Create `Tests/RoundTripTests.swift`

- [ ] **Step 1:** For every corpus proto and both goldens: parse → generate → `SwiftParser.Parser.parse(source:)` → assert `!hasError` (walk diagnostics via `ParseDiagnosticsGenerator` or check `hasError` on the tree).
- [ ] **Step 2:** `swift test` — full suite green.
- [ ] **Step 3:** Build the Example project (`cd Example && swift build`) to prove the plugin path works end-to-end.
- [ ] **Step 4:** Commit: `test: add SwiftParser round-trip validation`

---

## Self-review notes

- Spec coverage: Phase 0 (0.1–0.3), lexer (1.1), parser+AST+flatten (1.2), swap+delete (1.3), dependency (2.1), generator (2.2), round-trip (2.3). README/CLI unchanged per spec.
- `parseProto` is `throws` from day one so Phase 1 needs no signature change.
- Golden tests use all-flags-on to cover `_backingData`/`_localID` paths.
