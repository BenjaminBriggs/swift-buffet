import Foundation

/// Parses a protocol buffer file from the given URL path.
///
/// - Parameter path: The URL of the .proto file to be parsed.
/// - Returns: A tuple containing arrays of `ProtoMessage` and `ProtoEnum`.
/// - Throws: An error if the file cannot be read or parsed.
internal func parseProtoFile(
    at path: URL,
    with swiftPrefix: String,
    verbose: Bool,
    quite: Bool
) throws -> ([ProtoMessage], [ProtoEnum]) {
    let content = try String(contentsOf: path)
    return try parseProto(
        content,
        swiftPrefix: swiftPrefix,
        verbose: verbose,
        quite: quite
    )
}

/// Stable parsing entry point: lexes and parses the .proto source, then
/// flattens the resulting tree into the generator's model arrays.
///
/// - Throws: `ParseError` with line/column information for malformed input.
func parseProto(
    _ content: String,
    swiftPrefix: String,
    verbose: Bool = false,
    quite: Bool = true
) throws -> ([ProtoMessage], [ProtoEnum]) {
    let file = try ProtoParser.parse(content, quite: quite)
    let (messages, enums) = flatten(file, swiftPrefix: swiftPrefix)

    if quite == false {
        for message in messages {
            print("Matched message: \(message.name)")
        }
        for protoEnum in enums {
            print("Matched enum: \(protoEnum.name)")
        }
    }
    if verbose {
        for message in messages {
            for field in message.fields {
                print("Matched field type: \(field.type), field name: \(field.name), isOptional: \(field.isOptional), isRepeated: \(field.isRepeated), isMap: \(field.isMap))")
            }
        }
    }

    return (messages, enums)
}
