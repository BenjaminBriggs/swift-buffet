# Type-Safe Parsing and Generation for SwiftBuffet

**Date:** 2026-06-11
**Branch:** `feature/byond-regex`
**Status:** Approved approach: hand-rolled lexer/parser + SwiftSyntax generator, preceded by a characterization test suite.

## Problem

SwiftBuffet currently:

- **Parses** `.proto` files with four regexes (`Regex.swift`) driven by a remove-matched-text-and-reparse recursion in `Parser.swift`. The message pattern `message\s+(\w+)\s*\{([\s\S]*?)\n\}` cannot balance nested braces — it depends on the closing `}` sitting at column 0. Malformed fields silently produce no match instead of an error.
- **Generates** Swift source by string concatenation (`output +=`) in `Generator.swift`, with manual indentation padding for nested declarations. Nothing validates that the emitted text is syntactically valid Swift; errors surface in the consumer's build.

Goal: replace both with fully type-safe equivalents. Decisions made:

- Dependency weight is acceptable if it buys safety ("whatever is safest").
- No `protoc` requirement — the tool stays self-contained.

## Architecture

```
.proto text → Lexer → [Token] → ProtoParser → ProtoFile AST → flatten → [ProtoMessage]/[ProtoEnum] → Generator (SwiftSyntax) → formatted source
```

`Models.swift` (`ProtoMessage`, `ProtoField`, `ProtoEnum`, `ProtoEnumCase`) remains the generator's input. The parser and generator replacements are therefore independent, shippable phases.

## Components

### Lexer (`Lexer.swift`, new)

- `Token`: kind + line/column position.
- `TokenKind`: `identifier(String)`, `intLiteral(Int)`, `stringLiteral(String)`, punctuation (`{ } = ; < > , [ ] .`), `docComment(String)` (captures `/** ... */` content), `eof`.
- Keywords (`message`, `enum`, `optional`, `repeated`, `map`, `reserved`, etc.) lex as plain identifiers; the parser decides meaning by context. Proto legally allows keyword-named fields, which the regex approach mishandles.
- Line comments (`//`) are skipped. Doc comments (`/** */`) are emitted as tokens so field comments flow into generated output, as today.
- Unterminated string/comment → `ParseError` with position.

### Parser (`ProtoParser.swift`, replaces `Parser.swift` + `Regex.swift`)

Recursive descent over the token stream with `peek`/`consume`/`expect` primitives.

Grammar subset:

```
file     → (syntax | package | import | option | message | enum)*
message  → "message" ident "{" (field | message | enum | reserved | unknown)* "}"
field    → docComment? (optional|repeated)? type ident "=" int options? ";"
         | docComment? "map" "<" type "," type ">" ident "=" int options? ";"
enum     → "enum" ident "{" (enumCase | reserved | option)* "}"
enumCase → ident "=" int ";"
```

- Header statements (`syntax`, `package`, `import`, `option`) are consumed and ignored — parity with current behavior.
- Nesting is handled by real recursion. No content mutation, no brace-balancing heuristics. Any brace style and indentation parses correctly.
- Unsupported constructs (`oneof`, `service`, `extend`) are skipped with a printed warning via brace/semicolon-matched skipping. The generator has no representation for them, so skipping preserves current output behavior while being loud about it. `reserved` statements are benign metadata and are skipped silently.
- Malformed syntax throws `ParseError(line:column:expected:found:)` conforming to `Error` and `CustomStringConvertible`. The CLI prints it and exits non-zero. Today's silent-drop behavior for malformed fields is removed deliberately.
- The parser builds a small AST tree (`MessageNode` with nested children); a flatten step converts it to the existing flat `parentName`-based models. The tree is the natural shape for recursive descent and is independently testable; flattening is trivial.

Stable entry point (introduced in Phase 0, retained forever):

```swift
func parseProto(
    _ content: String,
    swiftPrefix: String,
    verbose: Bool,
    quite: Bool
) throws -> ([ProtoMessage], [ProtoEnum])
```

### Generator (`Generator.swift`, rewritten)

- New dependency: `swift-syntax`, wide version range (`"510.0.0"..<"602.0.0"`) to avoid version conflicts with consumers' macro dependencies (the plugin is built from source by consumers).
- Each current `write*(... to output: inout String)` function becomes a function returning a syntax node (`DeclSyntax`, `MemberBlockItemListSyntax`, etc.), built with SwiftSyntaxBuilder's throwing interpolated builders, e.g.:

  ```swift
  try StructDeclSyntax("public struct \(raw: name): Hashable, Equatable, Sendable") {
      for field in message.fields { ... }
  }
  ```

  Every generated declaration is parsed and validated at generation time — invalid Swift fails the codegen run with an error, not the consumer's build. Fully explicit node construction (no interpolation) was rejected: ~3× the code for marginal gain over parse-validated builders; interpolated builders are the approach used by swift-openapi-generator and similar production tools.
- Indentation and nesting come from `formatted()` (BasicFormat). All manual `padding`/whitespace logic is deleted.
- Output will not be byte-identical to today's hand-formatted output. Consumers see a one-time cosmetic diff in generated files. Accepted trade-off.

### Unchanged

- `main.swift` CLI surface (arguments, flags) — unchanged.
- `Models.swift` — unchanged (Phase 1 may add the internal AST types in a new file).
- `Plugins/SwiftBuffetPlugin` — unchanged.
- Existing `print`-based `verbose`/`quite` logging — unchanged.

## Phases

### Phase 0 — Characterization test suite

Build a robust test corpus against the **current** implementation before touching it.

- Add the `parseProto` wrapper around the existing regex implementation so tests target the stable contract.
- **Parser corpus tests** asserting on parsed model structure (message/enum names, field names, types, `isOptional`/`isRepeated`/`isMap`/`isDeprecated`, comments, parent relationships) across:
  - simple and empty messages
  - nested messages and nested enums, including multiple nesting levels
  - multiple top-level declarations in one file
  - optional / repeated / map fields (including `map<string, OtherMessage>`)
  - `[deprecated = true]` options
  - doc comments (`/** */`) on fields
  - enums with common-prefix case names (prefix stripping)
  - `syntax`, `package`, `import`, `option` header lines
  - varied whitespace, indentation, and brace placement
  - keyword-named fields (e.g. a field named `message`)
- Inputs the regex implementation is **known to mishandle** (nested `}` not at column 0, `}` on the same line as the last field, keyword-named fields) are included wrapped in `XCTExpectFailure`. Phase 0 ships green while documenting the bugs; Phase 1 removes the expectations, converting them into real regression tests.
- **Generator tests, two tiers:**
  1. *Semantic assertions* — output contains expected declarations (`public struct PrefixPerson`, `public let isActive: Bool`, init parameter lists, enum raw values). These survive Phase 2's formatting change.
  2. *Golden snapshots* — full-output equality for a few representative protos, including the `Example` project's proto. Re-baselined once in Phase 2.
- Framework: XCTest, consistent with existing tests.

### Phase 1 — Lexer + Parser

- Add `Lexer.swift`, `ProtoParser.swift`, AST types, flatten step.
- `parseProto` switches to the new implementation. Delete `Regex.swift` and the regex-driven internals of `Parser.swift`.
- Remove `XCTExpectFailure` wrappers — known-bug tests must now pass.
- Add `LexerTests` (token streams, positions, error cases) and parser error tests (malformed input throws `ParseError` with correct line/column).
- Generator untouched; Phase 0 golden snapshots prove output parity.

### Phase 2 — SwiftSyntax generator

- Add `swift-syntax` dependency.
- Rewrite `Generator.swift` as syntax-node builders; delete string concatenation and padding logic.
- Re-baseline golden snapshot tests; semantic-tier tests must pass unchanged.
- Add a round-trip test: generated output for every corpus proto must parse cleanly with `SwiftParser` (no diagnostics).

## Error Handling

- `ParseError(line:column:expected:found:)` thrown from lexer/parser; CLI prints description and exits non-zero (ArgumentParser default behavior on thrown errors).
- Generator builder failures (invalid interpolated syntax) throw at generation time and propagate the same way.
- Unsupported proto constructs: warning printed (respecting `quite`), construct skipped.

## Testing Summary

| Suite | Phase added | Survives |
|---|---|---|
| Parser corpus (model structure) | 0 | all phases |
| Known-bug tests (`XCTExpectFailure` → real) | 0 | all phases |
| Generator semantic assertions | 0 | all phases |
| Generator golden snapshots | 0 | re-baselined in Phase 2 |
| Lexer unit tests | 1 | all phases |
| Parser error tests | 1 | all phases |
| SwiftParser round-trip | 2 | all phases |

## Rejected Alternatives

- **swift-parsing combinators** for the parser: extra dependency, weaker error messages out of the box, little gain over recursive descent for a grammar this small.
- **`protoc --descriptor_set_out` + SwiftProtobuf**: spec-perfect parsing but requires `protoc` on every consumer machine and fights plugin sandboxing. Rejected by decision.
- **In-house structured code model** for generation: zero-dependency but only guarantees structure, not syntax. Rejected in favor of SwiftSyntax per the "whatever is safest" decision.
- **Fully explicit SwiftSyntax node construction**: maximal compile-time safety but ~3× the code; interpolated builders still parse-validate all output at generation time.
