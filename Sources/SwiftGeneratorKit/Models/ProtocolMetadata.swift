/// Parsed metadata for a Swift protocol annotated with `// @mock`.
///
/// `ProtocolMetadata` is the central data model produced by ``ProtocolParser`` and consumed
/// by ``SwiftGenerator``. It captures everything needed to generate a mock implementation:
/// the protocol's name, access level, concurrency traits, inherited types, methods, and properties.
///
/// ## Mock pattern inference
///
/// The ``pattern`` property derives the ``MockPattern`` from protocol traits:
/// - Protocols inheriting `Actor` → ``MockPattern/actor``
/// - Protocols with the `nonisolated` modifier → ``MockPattern/nonisolated``
/// - Everything else → ``MockPattern/mainActor``
public struct ProtocolMetadata: Sendable, Equatable {
	/// The protocol name as declared in source (e.g., `"CharacterListTrackerContract"`).
	public let name: String

	/// The access level keyword of the protocol declaration.
	///
	/// Contains `"public"` or `"package"` when explicitly declared, or an empty string
	/// for internal (default) access. The generator uses this to prefix mock declarations
	/// and decide between `@testable import` (internal) and plain `import` (public).
	public let accessLevel: String

	/// Whether the protocol has the `nonisolated` modifier.
	///
	/// When `true`, the inferred ``pattern`` is ``MockPattern/nonisolated`` (unless the
	/// protocol also inherits `Actor`, which takes precedence).
	public let isNonisolated: Bool

	/// The inherited types from the protocol's inheritance clause.
	///
	/// Contains the trimmed type names as written in source
	/// (e.g., `["AnyObject", "Sendable"]`, `["Actor"]`).
	/// Used to determine ``requiresSendable`` and ``inheritsActor``.
	public let inheritedTypes: [String]

	/// The methods declared in the protocol body, in source order.
	public let methods: [MethodMetadata]

	/// The properties declared in the protocol body, in source order.
	public let properties: [PropertyMetadata]

	/// The absolute path to the source file where this protocol was found.
	///
	/// Defaults to `"<in-memory>"` when parsing from a string without a file path.
	public let sourceFilePath: String

	/// The import statements from the source file containing this protocol.
	///
	/// Captured as full import declarations (e.g., `["import Foundation", "import ChallengeCore"]`).
	/// The generator uses these to replicate necessary imports in the generated mock file.
	public let sourceImports: [String]

	/// Creates a new protocol metadata instance.
	///
	/// - Parameters:
	///   - name: The protocol name as declared in source.
	///   - accessLevel: The access level keyword (`"public"`, `"package"`, or `""` for internal).
	///   - isNonisolated: Whether the protocol has the `nonisolated` modifier.
	///   - inheritedTypes: The type names from the protocol's inheritance clause.
	///   - methods: The methods declared in the protocol body.
	///   - properties: The properties declared in the protocol body.
	///   - sourceFilePath: The absolute path to the source file. Defaults to `"<in-memory>"` implicitly.
	///   - sourceImports: The import statements from the source file. Defaults to an empty array.
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
	///
	/// See ``MockPattern`` for the full selection rules. In summary:
	/// - `Actor` inheritance → ``MockPattern/actor``
	/// - `nonisolated` modifier → ``MockPattern/nonisolated``
	/// - Default → ``MockPattern/mainActor``
	public var pattern: MockPattern {
		if inheritsActor { return .actor }
		if isNonisolated { return .nonisolated }
		return .mainActor
	}

	/// Whether this protocol lists `Actor` in its inheritance clause.
	///
	/// When `true`, the generator produces an `actor` mock instead of a `final class`.
	public var inheritsActor: Bool {
		inheritedTypes.contains("Actor")
	}

	/// Whether this protocol requires `Sendable` conformance.
	///
	/// Returns `true` if the inheritance clause contains `"Sendable"` explicitly,
	/// or if the protocol inherits from `Actor` (which is implicitly `Sendable`).
	/// The ``MockPattern/mainActor`` and ``MockPattern/nonisolated`` emitters use
	/// this to decide whether to add `@unchecked Sendable` conformance to the mock.
	public var requiresSendable: Bool {
		inheritedTypes.contains("Sendable") || inheritsActor
	}

}

/// Parsed metadata for a single method declared in a protocol.
///
/// Captures the method's name, parameters, return type, effect specifiers (`async`, `throws`),
/// generic clause, and concurrency attributes. The generator uses this to produce
/// tracking properties (call count, received arguments) and the method implementation.
public struct MethodMetadata: Sendable, Equatable {
	/// The method base name (e.g., `"fetchCharacter"`, `"execute"`).
	///
	/// Does not include parameter labels or the generic clause.
	public let name: String

	/// The method's parameters, in declaration order.
	public let parameters: [ParameterMetadata]

	/// The return type as written in source (e.g., `"Character"`, `"[String]"`).
	///
	/// `nil` when the method returns `Void` (no explicit return clause).
	public let returnType: String?

	/// Whether the method has the `async` specifier.
	public let isAsync: Bool

	/// Whether the method has a `throws` clause (typed or untyped).
	public let isThrowing: Bool

	/// The error type from a typed `throws` clause (e.g., `"CharacterError"`).
	///
	/// `nil` for untyped `throws` or non-throwing methods. When present, the generator
	/// produces a `Result<ReturnType, ErrorType>` return value property instead of
	/// a separate `ThrowableError` property.
	public let throwsType: String?

	/// Whether the method has the `@concurrent` attribute.
	///
	/// Only meaningful for ``MockPattern/nonisolated`` mocks, where the generated
	/// method implementation preserves the `@concurrent` annotation.
	public let isConcurrent: Bool

	/// Whether the return type is a generic type parameter (e.g., `T`).
	///
	/// When `true`, the generator uses `Any?` for the return value property
	/// and casts it back to the generic type at the call site.
	public let hasGenericReturn: Bool

	/// The generic parameter clause as written in source (e.g., `"<T: Decodable>"`).
	///
	/// `nil` if the method is not generic. Preserved verbatim in the generated
	/// method signature.
	public let genericClause: String?

	/// Creates a new method metadata instance.
	///
	/// - Parameters:
	///   - name: The method base name.
	///   - parameters: The method's parameters in declaration order.
	///   - returnType: The return type as written, or `nil` for `Void`.
	///   - isAsync: Whether the method is `async`.
	///   - isThrowing: Whether the method throws.
	///   - throwsType: The typed throws error type, or `nil` for untyped/non-throwing.
	///   - isConcurrent: Whether the method has `@concurrent`.
	///   - hasGenericReturn: Whether the return type is a generic type parameter.
	///   - genericClause: The generic parameter clause, or `nil` if not generic.
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

/// Parsed metadata for a single parameter in a protocol method.
///
/// Captures the external label, internal name, and type. Provides computed properties
/// for generating the parameter declaration and call-site label in mock code.
///
/// ## Label resolution
///
/// Swift method parameters can have an external label and an internal name:
/// ```swift
/// func update(_ value: String, at index: Int)
/// //          ^  ^^^^^          ^^ ^^^^^
/// //      ext.  internal     ext.  internal
/// ```
///
/// - When both are present, ``externalLabel`` holds the first name and ``internalName`` the second.
/// - When only one name is present, ``externalLabel`` is `nil` and ``internalName`` holds it.
/// - A wildcard label (`_`) is stored as the string `"_"` in ``externalLabel``.
public struct ParameterMetadata: Sendable, Equatable {
	/// The external argument label, or `nil` when it matches ``internalName``.
	///
	/// Contains `"_"` for wildcard labels. Examples:
	/// - `func foo(_ x: Int)` → `externalLabel = "_"`, `internalName = "x"`
	/// - `func foo(at index: Int)` → `externalLabel = "at"`, `internalName = "index"`
	/// - `func foo(index: Int)` → `externalLabel = nil`, `internalName = "index"`
	public let externalLabel: String?

	/// The internal parameter name used inside the method body.
	///
	/// This is always present and is used as the variable name in tracking properties
	/// (e.g., `fetchReceivedIdentifier` for a parameter named `identifier`).
	public let internalName: String

	/// The parameter type as written in source (e.g., `"Int"`, `"any CharacterFilterDelegate"`).
	public let type: String

	/// Creates a new parameter metadata instance.
	///
	/// - Parameters:
	///   - externalLabel: The external argument label, `"_"` for wildcard, or `nil` when implicit.
	///   - internalName: The internal parameter name.
	///   - type: The parameter type as written in source.
	public init(externalLabel: String?, internalName: String, type: String) {
		self.externalLabel = externalLabel
		self.internalName = internalName
		self.type = type
	}

	/// The name used for tracking properties in the generated mock.
	///
	/// Currently returns ``internalName``. For a parameter `identifier: Int`,
	/// the generated tracking property would be named `fetchReceivedIdentifier`.
	public var trackingName: String {
		internalName
	}

	/// The full parameter declaration for use in generated method signatures.
	///
	/// Combines the external label (if any), internal name, and type:
	/// - `"_ value: String"` when `externalLabel` is `"_"`
	/// - `"at index: Int"` when `externalLabel` is `"at"`
	/// - `"identifier: Int"` when `externalLabel` is `nil`
	public var declaration: String {
		if let label = externalLabel {
			return "\(label) \(internalName): \(type)"
		}
		return "\(internalName): \(type)"
	}

	/// The argument label as it appears at the call site.
	///
	/// Used when generating forwarding calls in mock implementations:
	/// - `""` (empty) for wildcard labels (`_`)
	/// - `"at: "` for explicit external labels
	/// - `"identifier: "` when the label matches the internal name
	public var callSiteLabel: String {
		if let label = externalLabel {
			return label == "_" ? "" : "\(label): "
		}
		return "\(internalName): "
	}
}

/// Parsed metadata for a single property declared in a protocol.
///
/// Captures the property's name, type, and accessor requirements (`get` vs `get set`).
/// The generator uses this to emit stored properties in the mock type and to determine
/// whether the mock needs a memberwise initializer for non-optional properties.
public struct PropertyMetadata: Sendable, Equatable {
	/// The property name as declared in source (e.g., `"currentFilter"`).
	public let name: String

	/// The property type as written in source (e.g., `"CharacterFilter"`, `"String?"`).
	public let type: String

	/// Whether the property has a setter in its accessor block.
	///
	/// `true` for `{ get set }` declarations, `false` for `{ get }` only.
	/// The generated mock always uses a stored `var`, regardless of this value.
	public let isSettable: Bool

	/// Creates a new property metadata instance.
	///
	/// - Parameters:
	///   - name: The property name as declared in source.
	///   - type: The property type as written in source.
	///   - isSettable: Whether the property has a setter (`{ get set }`).
	public init(name: String, type: String, isSettable: Bool) {
		self.name = name
		self.type = type
		self.isSettable = isSettable
	}

	/// Whether the property type is optional (ends with `?`).
	///
	/// Used by the generator to decide whether the mock needs a memberwise initializer:
	/// optional properties can default to `nil`, while non-optional properties must
	/// be provided at initialization.
	public var isOptional: Bool {
		type.hasSuffix("?")
	}
}
