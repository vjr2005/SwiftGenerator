import Foundation
import SwiftParser
import SwiftSyntax

/// Parses Swift source code and extracts metadata for protocols annotated with `// @mock`.
///
/// `ProtocolParser` is a pure transformation: it takes a Swift source string and produces
/// an array of ``ProtocolMetadata`` values. It does **not** perform any file I/O — file
/// reading and directory enumeration are the caller's responsibility (see ``FileSystem``).
///
/// ## Usage
///
/// ```swift
/// let parser = ProtocolParser()
///
/// // Parse from a source string:
/// let protocols = parser.parse(source: sourceCode, filePath: "/path/to/File.swift")
///
/// // Parse from an in-memory string (filePath defaults to "<in-memory>"):
/// let protocols = parser.parse(source: sourceCode)
/// ```
///
/// ## Annotation format
///
/// Only protocols preceded by a `// @mock` line comment are extracted. The annotation
/// must appear in the leading trivia of the protocol declaration:
///
/// ```swift
/// // @mock
/// protocol FooContract: Sendable {
///     func execute() async throws -> String
/// }
/// ```
public struct ProtocolParser: Sendable {

	/// Creates a new protocol parser.
	public init() {}

	/// Parses a Swift source string and returns metadata for all `// @mock`-annotated protocols.
	///
	/// The parser walks the syntax tree using SwiftSyntax, collecting import statements
	/// and visiting protocol declarations. Only protocols whose leading trivia contains
	/// a `// @mock` line comment are included in the result.
	///
	/// - Parameters:
	///   - source: The Swift source code to parse.
	///   - filePath: The path to the source file, stored in ``ProtocolMetadata/sourceFilePath``.
	///     Defaults to `"<in-memory>"` when parsing from a string without a file context.
	/// - Returns: An array of ``ProtocolMetadata`` for each annotated protocol found,
	///   in source order. Returns an empty array if no annotated protocols are found.
	public func parse(source: String, filePath: String = "<in-memory>") -> [ProtocolMetadata] {
		let sourceFile = Parser.parse(source: source)
		let visitor = ProtocolVisitor(filePath: filePath)
		visitor.walk(sourceFile)
		return visitor.protocols
	}
}

// MARK: - SwiftSyntax Visitor

private final class ProtocolVisitor: SyntaxVisitor {
	let filePath: String
	var protocols: [ProtocolMetadata] = []
	private var imports: [String] = []

	init(filePath: String) {
		self.filePath = filePath
		super.init(viewMode: .sourceAccurate)
	}

	override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
		imports.append(node.trimmedDescription)
		return .skipChildren
	}

	override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
		guard hasMockAnnotation(on: node) else {
			return .skipChildren
		}

		let accessLevel = extractAccessLevel(from: node.modifiers)
		let isNonisolated = node.modifiers.contains { $0.name.text == "nonisolated" }
		let inheritedTypes = extractInheritedTypes(from: node.inheritanceClause)
		let methods = extractMethods(from: node.memberBlock, genericParams: extractGenericParamNames(from: node))
		let properties = extractProperties(from: node.memberBlock)

		let metadata = ProtocolMetadata(
			name: node.name.text,
			accessLevel: accessLevel,
			isNonisolated: isNonisolated,
			inheritedTypes: inheritedTypes,
			methods: methods,
			properties: properties,
			sourceFilePath: filePath,
			sourceImports: imports
		)

		protocols.append(metadata)
		return .skipChildren
	}

	// MARK: - Annotation Parsing

	private func hasMockAnnotation(on node: ProtocolDeclSyntax) -> Bool {
		let trivia = node.leadingTrivia
		for piece in trivia.reversed() {
			guard case let .lineComment(comment) = piece else { continue }
			if comment.trimmingCharacters(in: .whitespaces) == "// @mock" {
				return true
			}
		}
		return false
	}

	// MARK: - Extraction

	private func extractAccessLevel(from modifiers: DeclModifierListSyntax) -> String {
		for modifier in modifiers {
			if modifier.name.text == "public" || modifier.name.text == "package" {
				return modifier.name.text
			}
		}
		return ""
	}

	private func extractInheritedTypes(from clause: InheritanceClauseSyntax?) -> [String] {
		guard let clause else { return [] }
		return clause.inheritedTypes.map { $0.type.trimmedDescription }
	}

	private func extractGenericParamNames(from node: ProtocolDeclSyntax) -> Set<String> {
		guard let primaryAssociated = node.primaryAssociatedTypeClause else { return [] }
		return Set(primaryAssociated.primaryAssociatedTypes.map { $0.name.text })
	}

	private func extractMethods(from memberBlock: MemberBlockSyntax, genericParams: Set<String>) -> [MethodMetadata] {
		memberBlock.members.compactMap { member -> MethodMetadata? in
			guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { return nil }
			return parseMethod(funcDecl, protocolGenericParams: genericParams)
		}
	}

	private func extractProperties(from memberBlock: MemberBlockSyntax) -> [PropertyMetadata] {
		memberBlock.members.compactMap { member -> PropertyMetadata? in
			guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { return nil }
			return parseProperty(varDecl)
		}
	}

	// MARK: - Method Parsing

	private func parseMethod(_ funcDecl: FunctionDeclSyntax, protocolGenericParams: Set<String>) -> MethodMetadata {
		let name = funcDecl.name.text
		let parameters = funcDecl.signature.parameterClause.parameters.map { parseParameter($0) }

		let returnType: String?
		if let returnClause = funcDecl.signature.returnClause {
			returnType = returnClause.type.trimmedDescription
		} else {
			returnType = nil
		}

		let effects = funcDecl.signature.effectSpecifiers
		let isAsync = effects?.asyncSpecifier != nil
		let isThrowing = effects?.throwsClause != nil
		let throwsType = effects?.throwsClause?.type?.trimmedDescription

		let isConcurrent = funcDecl.attributes.contains {
			guard let attr = $0.as(AttributeSyntax.self) else { return false }
			return attr.attributeName.trimmedDescription == "concurrent"
		}

		let genericClause = funcDecl.genericParameterClause?.trimmedDescription
		let funcGenericParamNames: Set<String>
		if let genericParamClause = funcDecl.genericParameterClause {
			funcGenericParamNames = Set(genericParamClause.parameters.map { $0.name.text })
		} else {
			funcGenericParamNames = []
		}

		let allGenericNames = protocolGenericParams.union(funcGenericParamNames)
		let hasGenericReturn: Bool
		if let returnType {
			hasGenericReturn = allGenericNames.contains(returnType)
		} else {
			hasGenericReturn = false
		}

		return MethodMetadata(
			name: name,
			parameters: parameters,
			returnType: returnType,
			isAsync: isAsync,
			isThrowing: isThrowing,
			throwsType: throwsType,
			isConcurrent: isConcurrent,
			hasGenericReturn: hasGenericReturn,
			genericClause: genericClause
		)
	}

	private func parseParameter(_ param: FunctionParameterSyntax) -> ParameterMetadata {
		let firstName = param.firstName.text
		let secondName = param.secondName?.text
		let type = param.type.trimmedDescription

		let externalLabel: String?
		let internalName: String

		if let secondName {
			externalLabel = firstName
			internalName = secondName
		} else {
			externalLabel = nil
			internalName = firstName
		}

		return ParameterMetadata(
			externalLabel: externalLabel,
			internalName: internalName,
			type: type
		)
	}

	// MARK: - Property Parsing

	private func parseProperty(_ varDecl: VariableDeclSyntax) -> PropertyMetadata? {
		guard let binding = varDecl.bindings.first else { return nil }
		guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { return nil }
		guard let typeAnnotation = binding.typeAnnotation else { return nil }

		let name = pattern.identifier.text
		let type = typeAnnotation.type.trimmedDescription

		let isSettable: Bool
		if let accessorBlock = binding.accessorBlock {
			isSettable = hasSetAccessor(accessorBlock)
		} else {
			isSettable = false
		}

		return PropertyMetadata(name: name, type: type, isSettable: isSettable)
	}

	private func hasSetAccessor(_ block: AccessorBlockSyntax) -> Bool {
		switch block.accessors {
		case .accessors(let list):
			return list.contains { $0.accessorSpecifier.text == "set" }
		case .getter:
			return false
		}
	}
}
