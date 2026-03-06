import Foundation
import SwiftParser
import SwiftSyntax

/// Parses Swift source files and extracts protocols annotated with `// @mock`.
public struct ProtocolParser: Sendable {
	public init() {}

	/// Parses all `.swift` files in the given directories and returns annotated protocols.
	public func parse(directories: [String]) throws -> [ProtocolMetadata] {
		let fileManager = FileManager.default
		var protocols: [ProtocolMetadata] = []

		for directory in directories {
			let files = try swiftFiles(in: directory, fileManager: fileManager)
			for file in files {
				let source = try String(contentsOfFile: file, encoding: .utf8)
				let parsed = parse(source: source, filePath: file)
				protocols.append(contentsOf: parsed)
			}
		}

		return protocols
	}

	/// Parses a single Swift source string and returns annotated protocols.
	public func parse(source: String, filePath: String = "<in-memory>") -> [ProtocolMetadata] {
		let sourceFile = Parser.parse(source: source)
		let visitor = ProtocolVisitor(filePath: filePath)
		visitor.walk(sourceFile)
		return visitor.protocols
	}

	private func swiftFiles(in directory: String, fileManager: FileManager) throws -> [String] {
		let url = URL(fileURLWithPath: directory)
		guard let enumerator = fileManager.enumerator(
			at: url,
			includingPropertiesForKeys: [.isRegularFileKey],
			options: [.skipsHiddenFiles]
		) else {
			return []
		}

		var files: [String] = []
		for case let fileURL as URL in enumerator {
			if fileURL.pathExtension == "swift" {
				files.append(fileURL.path)
			}
		}
		return files.sorted()
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

