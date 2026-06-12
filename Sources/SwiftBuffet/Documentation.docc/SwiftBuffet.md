# ``SwiftBuffet``
Generate simple, dependency-light Swift structs from Protocol Buffer definitions.

## Overview
Swift Buffet reads `.proto` files and generates plain Swift value types — `struct`s and `enum`s with `Hashable`, `Equatable`, and `Sendable` conformance — that are pleasant to use directly in app code. Unlike the types produced by `protoc` and SwiftProtobuf, the generated types have no protobuf runtime requirements of their own; optionally, they can include initializers that bridge *from* SwiftProtobuf types when you need wire-format decoding.

The tool runs in two ways:
- As a **command-line tool**, converting one `.proto` file to one `.swift` file.
- As a **Swift Package Manager build-tool plugin**, regenerating Swift sources automatically whenever the `.proto` files in a target change. The plugin also supports Xcode app projects.

Internally, Swift Buffet lexes and parses proto source with a hand-written recursive-descent parser (no regular expressions), then generates Swift using SwiftSyntax — every generated file is re-parsed before it is written, so the tool fails loudly rather than emitting invalid Swift into your build.
```proto
message Person {
    string name = 1;
    int32 id = 2;
    optional string nick_name = 3;
}
```
becomes:
```swift
public struct Person: Hashable, Equatable, Sendable {
    public let name: String
    public let id: Int
    public let nickName: String?

    public init(name: String, id: Int, nickName: String?) {
        self.name = name
        self.id = id
        self.nickName = nickName
    }
}
```

## Topics
### Essentials
- <doc:GettingStarted>
- <doc:CommandLineUsage>
- <doc:PluginConfiguration>

### Reference
- <doc:GeneratedCode>
- <doc:SupportedProtoFeatures>
