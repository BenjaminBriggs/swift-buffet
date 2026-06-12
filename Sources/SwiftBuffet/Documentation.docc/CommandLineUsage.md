# Command-Line Usage

Run the generator directly for one-off conversions, scripts, or CI.

## Overview

The executable takes an input `.proto` path and an output `.swift` path, plus options controlling what gets generated:

```
swift run SwiftBuffet <input.proto> <output.swift> [options]
```

## Options

| Option | Default | Effect |
| --- | --- | --- |
| `--swift-prefix <prefix>` | *(empty)* | Prefix applied to every generated Swift type name. `--swift-prefix App` turns message `Person` into `struct AppPerson`. |
| `--include-protobuf` | off | Adds `init?(proto:)` and `init?(data: Data)` to every type, bridging from SwiftProtobuf-generated types. Requires the consuming target to depend on SwiftProtobuf and the matching `protoc` output. |
| `--proto-prefix <prefix>` | `Proto` | The Swift name prefix of the SwiftProtobuf-generated types referenced by `--include-protobuf`. |
| `--store-backing-data` | off | Adds a `_backingData: Data?` property that retains the original serialized bytes when a type is created via `init?(data:)`. |
| `--local-id-messages <name>` | *(none)* | Repeatable. Each named message gains a `_localID = UUID()` property — handy as a stable `Identifiable` id in SwiftUI lists. |
| `--verbose` / `-v` | off | Prints every parsed message, field, and enum, and warnings for skipped constructs. |
| `--quiet` / `-q` | off | Suppresses the per-file progress line. |

## Examples

Generate plain structs:

```
swift run SwiftBuffet models.proto Generated/Models.swift
```

Generate prefixed types with SwiftProtobuf bridging and backing data:

```
swift run SwiftBuffet models.proto Generated/Models.swift \
    --swift-prefix App \
    --include-protobuf \
    --proto-prefix Proto \
    --store-backing-data \
    --local-id-messages Person \
    --local-id-messages Article
```

## Errors

The tool exits non-zero with a descriptive message when:

- **The proto source is malformed.** Parse errors include the line and column: `Parse error at line 12, column 3: expected ';', found '}'`.
- **Two types would collide.** All structs are generated at the top level, so two messages named `Item` nested in different parents would produce duplicate Swift types. Generation fails naming both: `Cannot generate: Invoice.Item and Order.Item would both produce the Swift type 'AppItem'. Rename one of them.`
- **The generated Swift fails to re-parse.** Every output file is validated with SwiftParser before being written. This guards the tool's own output; if it ever triggers, it is a Swift Buffet bug and the error includes the offending excerpt.
