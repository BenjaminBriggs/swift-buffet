import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftParser

/// Thrown when the generated source fails to re-parse as valid Swift.
/// This is the final validation gate: codegen fails here rather than in the
/// consumer's build.
struct GenerationError: Error, CustomStringConvertible {
    let line: Int?
    let excerpt: String

    var description: String {
        let location = line.map { " at line \($0)" } ?? ""
        return "Internal error: generated Swift failed to parse\(location). Please report this. Context:\n\(excerpt)"
    }

    init(generated: String, tree: SourceFileSyntax) {
        let finder = FirstSyntaxErrorFinder(viewMode: .all)
        finder.walk(tree)

        if let position = finder.position {
            let converter = SourceLocationConverter(
                fileName: "generated.swift",
                tree: tree
            )
            let errorLine = converter.location(for: position).line
            let lines = generated.split(separator: "\n", omittingEmptySubsequences: false)
            let window = lines[max(0, errorLine - 6)..<min(lines.count, errorLine + 5)]
            self.line = errorLine
            self.excerpt = window.joined(separator: "\n")
        } else {
            self.line = nil
            self.excerpt = generated
        }
    }
}

/// Finds the position of the first missing or unexpected token in a tree.
private final class FirstSyntaxErrorFinder: SyntaxAnyVisitor {
    var position: AbsolutePosition?

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        if position != nil || node.hasError == false {
            return .skipChildren
        }
        if node.is(UnexpectedNodesSyntax.self)
            || node.as(TokenSyntax.self)?.presence == .missing {
            position = node.positionAfterSkippingLeadingTrivia
            return .skipChildren
        }
        return .visitChildren
    }
}

/// Thrown when two proto types would flatten to the same Swift type name.
///
/// All structs are generated at the top level, so `Order.Item` and
/// `Invoice.Item` would both become `<prefix>Item` — a duplicate-symbol
/// compile error in the consumer's build if it were allowed through.
struct DuplicateTypeNameError: Error, CustomStringConvertible {
    let swiftName: String
    let protoNames: [String]
    var description: String {
        "Cannot generate: \(protoNames.joined(separator: " and ")) would both produce the Swift type '\(swiftName)'. Rename one of them."
    }
}

/// Generates Swift code from protocol buffer messages and enums.
///
/// - Parameters:
///   - messages: An array of `ProtoMessage` representing protocol buffer messages.
///   - enums: An array of `ProtoEnum` representing protocol buffer enums.
/// - Returns: A string containing the generated Swift code.
/// - Throws: `GenerationError` if the generated source is not valid Swift.
func generateSwiftCode(
    from messages: [ProtoMessage],
    enums: [ProtoEnum],
    with swiftPrefix: String,
    includeProto: Bool,
    includeLocalIDFor localIDMessages: [String]?,
    includeBackingData: Bool,
    with protoPrefix: String
) throws -> String {
    // Every message becomes a top-level struct, and top-level enums share
    // that namespace. Nested enums live inside extensions of their parent,
    // so they cannot collide with top-level types.
    let topLevelNames = messages.map { (name: $0.name, fullName: $0.fullName) }
        + enums.filter(\.parentPath.isEmpty).map { (name: $0.name, fullName: $0.fullName) }
    let duplicates = Dictionary(grouping: topLevelNames) { $0.name }
        .filter { $0.value.count > 1 }
    if let (name, collisions) = duplicates.min(by: { $0.key < $1.key }) {
        throw DuplicateTypeNameError(
            swiftName: "\(swiftPrefix)\(name)",
            protoNames: collisions.map(\.fullName).sorted()
        )
    }

    var declarations: [DeclSyntax] = [DeclSyntax("import Foundation")]

    let sortedMessages = messages.sorted { $0.name < $1.name }
    for (index, message) in sortedMessages.enumerated() {
        var declaration = DeclSyntax(
            try structDecl(
                for: message,
                swiftPrefix: swiftPrefix,
                includeProto: includeProto,
                includeLocalID: localIDMessages?.contains(message.name) ?? false,
                includeBackingData: includeBackingData,
                protoPrefix: protoPrefix
            )
        )
        declaration.leadingTrivia = sectionTrivia(
            mark: index == 0 ? "Structs" : nil
        )
        declarations.append(declaration)
    }

    let sortedEnums = enums.sorted { $0.name < $1.name }
    for (index, protoEnum) in sortedEnums.enumerated() {
        var declaration = try enumDecl(
            for: protoEnum,
            swiftPrefix: swiftPrefix,
            includeProto: includeProto,
            protoPrefix: protoPrefix
        )
        declaration.leadingTrivia = sectionTrivia(
            mark: index == 0 ? "Enums" : nil
        )
        declarations.append(declaration)
    }

    let source = SourceFileSyntax {
        for declaration in declarations {
            declaration
        }
    }

    var text = source.formatted().description
    if text.hasSuffix("\n") == false {
        text += "\n"
    }

    let reparsed = SwiftParser.Parser.parse(source: text)
    guard reparsed.hasError == false else {
        throw GenerationError(generated: text, tree: reparsed)
    }

    return text
}

private func sectionTrivia(mark: String?) -> Trivia {
    if let mark {
        return [.newlines(2), .lineComment("// MARK: - \(mark)"), .newlines(1)]
    } else {
        return [.newlines(2)]
    }
}

// MARK: - Structs

private func structDecl(
    for message: ProtoMessage,
    swiftPrefix: String,
    includeProto: Bool,
    includeLocalID: Bool,
    includeBackingData: Bool,
    protoPrefix: String
) throws -> StructDeclSyntax {
    var members: [DeclSyntax] = []

    for field in message.fields {
        members.append(propertyDecl(for: field))
    }
    if includeLocalID {
        members.append(DeclSyntax("public let _localID = UUID()"))
    }
    if includeBackingData {
        members.append(DeclSyntax("public private(set) var _backingData: Data?"))
    }

    members.append(DeclSyntax(try memberwiseInit(for: message)))

    if includeProto {
        members.append(
            DeclSyntax(
                try dataInit(
                    for: message,
                    includeBackingData: includeBackingData,
                    protoPrefix: protoPrefix
                )
            )
        )
        members.append(
            DeclSyntax(try protoInit(for: message, protoPrefix: protoPrefix))
        )
    }

    return try StructDeclSyntax(
        "public struct \(raw: swiftPrefix)\(raw: message.name): Hashable, Equatable, Sendable"
    ) {
        for member in members {
            member
        }
    }
}

/// A stored property for a message field, with its proto comment and any
/// deprecation notice attached as leading trivia.
private func propertyDecl(for field: ProtoField) -> DeclSyntax {
    var lines: [String] = []

    if let comment = field.comment {
        let commentLines = comment
            .replacingOccurrences(of: "/**", with: "")
            .replacingOccurrences(of: "*/", with: "")
            .replacingOccurrences(of: "*", with: "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }
        lines.append(contentsOf: commentLines.map { "// \($0)" })
    }
    if field.isDeprecated {
        lines.append("/// This property has been marked as **deprecated** in the proto file")
    }
    lines.append("public let \(field.caseCorrectName): \(field.caseCorrectedType)")

    return DeclSyntax("\(raw: lines.joined(separator: "\n"))")
}

private func memberwiseInit(for message: ProtoMessage) throws -> InitializerDeclSyntax {
    let parameters = message.fields
        .map { "\($0.caseCorrectName): \($0.caseCorrectedType)" }
        .joined(separator: ", ")

    return try InitializerDeclSyntax("public init(\(raw: parameters))") {
        for field in message.fields {
            ExprSyntax("self.\(raw: field.caseCorrectName) = \(raw: field.caseCorrectName)")
        }
    }
}

private func dataInit(
    for message: ProtoMessage,
    includeBackingData: Bool,
    protoPrefix: String
) throws -> InitializerDeclSyntax {
    let backingDataAssignment = includeBackingData
        ? "\n    self._backingData = data"
        : ""

    return try InitializerDeclSyntax("public init?(data: Data)") {
        ExprSyntax(
            """
            if let proto = try? \(raw: protoPrefix)\(raw: message.fullName)(serializedBytes: data) {
                self.init(proto: proto)\(raw: backingDataAssignment)
            } else {
                return nil
            }
            """
        )
    }
}

private func protoInit(
    for message: ProtoMessage,
    protoPrefix: String
) throws -> InitializerDeclSyntax {
    try InitializerDeclSyntax("internal init?(proto: \(raw: protoPrefix)\(raw: message.fullName))") {
        for field in message.fields {
            ExprSyntax("\(raw: protoInitStatement(for: field))")
        }
    }
}

/// The statement assigning one field inside `init?(proto:)`.
///
/// Integer scalars convert directly via their Swift type (Int/UInt per
/// `signedIntTypes`/`unsignedIntTypes`); URL-suffixed string fields convert
/// through `URL(string:)`, failably where the field is required.
private func protoInitStatement(for field: ProtoField) -> String {
    let name = field.caseCorrectName
    let protoName = field.caseCorrectProtoName
    let baseType = field.caseCorrectedBaseType

    var statement: String
    if field.isRepeated {
        let transform = if field.isURL {
            "URL(string: $0)"
        } else if field.isPrimitiveType || field.isIntType {
            "\(baseType)($0)"
        } else {
            "\(baseType)(proto: $0)"
        }
        statement = "self.\(name) = proto.\(protoName).compactMap { \(transform) }"
    } else if field.isMap {
        statement = "self.\(name) = proto.\(protoName).reduce(into: \(field.caseCorrectedType)()) { result, element in result[element.key] = element.value }"
    } else if baseType == "TimeInterval" {
        statement = "self.\(name) = proto.\(protoName).timeInterval"
    } else if baseType == "Date" {
        statement = "self.\(name) = proto.\(protoName).date"
    } else if field.isURL {
        if field.isOptional {
            statement = "self.\(name) = URL(string: proto.\(protoName))"
        } else {
            statement = requiredAssignment(
                of: name,
                to: "URL(string: proto.\(protoName))"
            )
        }
    } else if field.isIntType {
        statement = "self.\(name) = \(baseType)(proto.\(protoName))"
    } else if field.isPrimitiveType {
        statement = "self.\(name) = proto.\(protoName)"
    } else if field.isOptional == false {
        statement = requiredAssignment(
            of: name,
            to: "\(baseType)(proto: proto.\(protoName))"
        )
    } else {
        statement = "self.\(name) = \(baseType)(proto: proto.\(protoName))"
    }

    if field.isOptional {
        let defaultValue = if field.isRepeated {
            "[]"
        } else if field.type == "bool" {
            "false"
        } else {
            "nil"
        }
        statement = """
        if proto.has\(protoName.capitalizingFirstLetter()) {
            \(statement.split(separator: "\n").joined(separator: "\n    "))
        } else {
            self.\(name) = \(defaultValue)
        }
        """
    }

    return statement
}

/// An `if let` binding that assigns the unwrapped value or fails the
/// initializer — the shape shared by every conversion that can fail.
private func requiredAssignment(of name: String, to expression: String) -> String {
    """
    if let \(name) = \(expression) {
        self.\(name) = \(name)
    } else {
        return nil
    }
    """
}

// MARK: - Enums

private func enumDecl(
    for protoEnum: ProtoEnum,
    swiftPrefix: String,
    includeProto: Bool,
    protoPrefix: String
) throws -> DeclSyntax {
    let strippedCases = stripCommonPrefix(from: protoEnum.cases)
    let pairs = zip(
        strippedCases.map(\.name),
        protoEnum.cases.map(\.value)
    )

    // allow_alias permits several proto cases with one value; a Swift enum
    // permits one case per raw value, so only the first name survives.
    var seenValues = Set<Int>()
    var members: [DeclSyntax] = pairs.compactMap { caseName, caseValue in
        guard seenValues.insert(caseValue).inserted else { return nil }
        return DeclSyntax("case \(raw: caseName) = \(raw: String(caseValue))")
    }

    if includeProto {
        members.append(
            DeclSyntax(
                try InitializerDeclSyntax(
                    "internal init?(proto: \(raw: protoPrefix)\(raw: protoEnum.fullName))"
                ) {
                    ExprSyntax("self.init(rawValue: proto.rawValue)")
                }
            )
        )
    }

    let enumDeclaration = try EnumDeclSyntax(
        "public enum \(raw: swiftPrefix)\(raw: protoEnum.name): Int, CaseIterable, Hashable, Equatable, Sendable"
    ) {
        for member in members {
            member
        }
    }

    if let parent = protoEnum.parentName {
        let extensionDeclaration = try ExtensionDeclSyntax(
            "extension \(raw: swiftPrefix)\(raw: parent)"
        ) {
            enumDeclaration
        }
        return DeclSyntax(extensionDeclaration)
    } else {
        return DeclSyntax(enumDeclaration)
    }
}
