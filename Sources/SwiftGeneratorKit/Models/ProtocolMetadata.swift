/// Parsed metadata for a protocol annotated with `// @mock`.
public struct ProtocolMetadata: Sendable, Equatable {
	/// The protocol name (e.g., `CharacterListTrackerContract`).
	public let name: String

	/// The access level of the protocol declaration (`public` or empty for internal).
	public let accessLevel: String

	/// Whether the protocol has the `nonisolated` modifier.
	public let isNonisolated: Bool

	/// Inherited types (e.g., `["Sendable"]`, `["Actor"]`, `["AnyObject", "Sendable"]`).
	public let inheritedTypes: [String]

	/// Methods declared in the protocol.
	public let methods: [MethodMetadata]

	/// Properties declared in the protocol.
	public let properties: [PropertyMetadata]

	/// Path to the source file where this protocol was found.
	public let sourceFilePath: String

	/// Import statements from the source file (e.g., `["import ChallengeCore", "import Foundation"]`).
	public let sourceImports: [String]

	public init(
		name: String,
		accessLevel: String,
		isNonisolated: Bool,
		inheritedTypes: [String],
		methods: [MethodMetadata],
		properties: [PropertyMetadata],
		sourceFilePath: String,
		sourceImports: [String] = []
	) {
		self.name = name
		self.accessLevel = accessLevel
		self.isNonisolated = isNonisolated
		self.inheritedTypes = inheritedTypes
		self.methods = methods
		self.properties = properties
		self.sourceFilePath = sourceFilePath
		self.sourceImports = sourceImports
	}

	/// The inferred mock pattern based on protocol traits.
	public var pattern: MockPattern {
		if inheritsActor { return .actor }
		if isNonisolated { return .nonisolated }
		return .mainActor
	}

	/// Whether this protocol inherits from `Actor`.
	public var inheritsActor: Bool {
		inheritedTypes.contains("Actor")
	}

	/// Whether this protocol inherits from `Sendable` (directly or via `Actor`).
	public var requiresSendable: Bool {
		inheritedTypes.contains("Sendable") || inheritsActor
	}

	/// The generated mock name: strips "Contract"/"Delegate" suffix, appends "Mock".
	public var mockName: String {
		var baseName = name
		for suffix in ["Contract", "Delegate"] {
			if baseName.hasSuffix(suffix) {
				baseName = String(baseName.dropLast(suffix.count))
				break
			}
		}
		return baseName + "Mock"
	}

	/// Whether the mock needs `@unchecked Sendable` conformance.
	public var needsUncheckedSendable: Bool {
		requiresSendable && pattern != .actor
	}
}

/// Parsed metadata for a method in a protocol.
public struct MethodMetadata: Sendable, Equatable {
	/// The method base name (e.g., `fetchCharacter`).
	public let name: String

	/// The method parameters.
	public let parameters: [ParameterMetadata]

	/// The return type as written (e.g., `Character`, `CharactersResponseDTO`). Nil for Void.
	public let returnType: String?

	/// Whether the method is `async`.
	public let isAsync: Bool

	/// Whether the method throws.
	public let isThrowing: Bool

	/// The typed throws error type (e.g., `CharacterError`). Nil for untyped throws.
	public let throwsType: String?

	/// Whether the method has the `@concurrent` attribute.
	public let isConcurrent: Bool

	/// Whether the return type is a generic type parameter (e.g., `T`).
	public let hasGenericReturn: Bool

	/// Generic parameter clause (e.g., `<T: Decodable>`). Nil if not generic.
	public let genericClause: String?

	public init(
		name: String,
		parameters: [ParameterMetadata],
		returnType: String?,
		isAsync: Bool,
		isThrowing: Bool,
		throwsType: String?,
		isConcurrent: Bool,
		hasGenericReturn: Bool,
		genericClause: String?
	) {
		self.name = name
		self.parameters = parameters
		self.returnType = returnType
		self.isAsync = isAsync
		self.isThrowing = isThrowing
		self.throwsType = throwsType
		self.isConcurrent = isConcurrent
		self.hasGenericReturn = hasGenericReturn
		self.genericClause = genericClause
	}
}

/// Parsed metadata for a method parameter.
public struct ParameterMetadata: Sendable, Equatable {
	/// The external label (e.g., `identifier`). `_` for wildcard. Nil when same as `internalName`.
	public let externalLabel: String?

	/// The internal name (e.g., `identifier`, `filter`, `page`).
	public let internalName: String

	/// The type as written (e.g., `Int`, `CharacterFilter`, `any CharacterFilterDelegate`).
	public let type: String

	public init(externalLabel: String?, internalName: String, type: String) {
		self.externalLabel = externalLabel
		self.internalName = internalName
		self.type = type
	}

	/// The name to use for tracking properties (prefers internal name).
	public var trackingName: String {
		internalName
	}

	/// The full parameter declaration for use in method signatures.
	public var declaration: String {
		if let label = externalLabel {
			return "\(label) \(internalName): \(type)"
		}
		return "\(internalName): \(type)"
	}

	/// The argument label as it appears at the call site.
	public var callSiteLabel: String {
		if let label = externalLabel {
			return label == "_" ? "" : "\(label): "
		}
		return "\(internalName): "
	}
}

/// Parsed metadata for a property in a protocol.
public struct PropertyMetadata: Sendable, Equatable {
	/// The property name (e.g., `currentFilter`).
	public let name: String

	/// The type as written (e.g., `CharacterFilter`, `String`).
	public let type: String

	/// Whether the property has a setter (`{ get set }`).
	public let isSettable: Bool

	public init(name: String, type: String, isSettable: Bool) {
		self.name = name
		self.type = type
		self.isSettable = isSettable
	}

	/// Whether the type is optional (ends with `?`).
	public var isOptional: Bool {
		type.hasSuffix("?")
	}
}
