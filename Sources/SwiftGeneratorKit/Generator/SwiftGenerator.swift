/// The main entry point for generating mock source code from protocol metadata.
///
/// `SwiftGenerator` orchestrates the generation pipeline: it computes mock names,
/// emits the file header and import statements, then delegates the type-specific
/// mock body to a ``MockEmitter`` selected by the protocol's ``MockPattern``.
///
/// ## Usage
///
/// ```swift
/// let generator = SwiftGenerator(moduleName: "ChallengeCharacter")
///
/// // Generate mock source code:
/// let sourceCode = generator.generate(from: protocolMetadata)
///
/// // Get the mock name for file naming:
/// let name = generator.mockName(for: protocolMetadata) // e.g., "CharacterListTrackerMock"
/// ```
///
/// ## Customization
///
/// - **Mock name suffixes**: By default, `"Contract"` and `"Delegate"` are stripped from
///   the protocol name before appending `"Mock"`. Override via `mockNameSuffixes`.
/// - **Custom emitters**: Supply a custom `emitters` dictionary to replace or extend
///   the built-in emitters for each ``MockPattern``.
///
/// ## Generated file structure
///
/// Each generated file follows this layout:
/// 1. Auto-generated header comment
/// 2. `import Foundation` + source file imports
/// 3. Module import (`@testable` for internal, plain for public)
/// 4. Mock type declaration (delegated to the appropriate ``MockEmitter``)
public struct SwiftGenerator: Sendable {
	private let moduleName: String
	private let mockNameSuffixes: [String]
	private let emitters: [MockPattern: any MockEmitter]

	/// Creates a new mock generator.
	///
	/// - Parameters:
	///   - moduleName: The module name used in import statements (e.g., `"ChallengeCharacter"`).
	///     For internal mocks, this appears as `@testable import <moduleName>`.
	///     For public mocks, it appears as `import <moduleName>`.
	///   - mockNameSuffixes: Suffixes to strip from protocol names when computing mock names.
	///     Defaults to `["Contract", "Delegate"]`. Only the first matching suffix is stripped.
	///     For example, `"FooTrackerContract"` becomes `"FooTrackerMock"`.
	///   - emitters: A dictionary mapping each ``MockPattern`` to a ``MockEmitter`` implementation.
	///     Pass `nil` (the default) to use the built-in emitters:
	///     - ``MockPattern/mainActor`` → `ClassMockEmitter(nonisolated: false)`
	///     - ``MockPattern/nonisolated`` → `ClassMockEmitter(nonisolated: true)`
	///     - ``MockPattern/actor`` → `ActorMockEmitter()`
	public init(
		moduleName: String,
		mockNameSuffixes: [String] = ["Contract", "Delegate"],
		emitters: [MockPattern: any MockEmitter]? = nil
	) {
		self.moduleName = moduleName
		self.mockNameSuffixes = mockNameSuffixes
		self.emitters = emitters ?? [
			.mainActor: ClassMockEmitter(nonisolated: false),
			.nonisolated: ClassMockEmitter(nonisolated: true),
			.actor: ActorMockEmitter(),
		]
	}

	/// Computes the mock type name for a protocol.
	///
	/// Strips the first matching suffix from ``mockNameSuffixes`` and appends `"Mock"`.
	/// If no suffix matches, `"Mock"` is appended to the full protocol name.
	///
	/// - Parameter proto: The protocol metadata to compute the name for.
	/// - Returns: The generated mock name (e.g., `"CharacterListTrackerMock"`).
	///
	/// ## Examples
	///
	/// | Protocol name                   | Mock name                    |
	/// |---------------------------------|------------------------------|
	/// | `CharacterListTrackerContract`  | `CharacterListTrackerMock`   |
	/// | `NavigationDelegate`            | `NavigationMock`             |
	/// | `DataStore`                     | `DataStoreMock`              |
	public func mockName(for proto: ProtocolMetadata) -> String {
		var baseName = proto.name
		for suffix in mockNameSuffixes {
			if baseName.hasSuffix(suffix) {
				baseName = String(baseName.dropLast(suffix.count))
				break
			}
		}
		return baseName + "Mock"
	}

	/// Generates the complete mock source file content for a protocol.
	///
	/// The output includes the file header, import statements, and the full mock type
	/// declaration with all tracking properties, method implementations, and the `reset()` method.
	///
	/// - Parameter proto: The protocol metadata to generate a mock for.
	/// - Returns: The generated Swift source code as a string, ready to be written to a `.swift` file.
	public func generate(from proto: ProtocolMetadata) -> String {
		let access = proto.accessLevel
		let name = mockName(for: proto)

		var code = CodeBuilder()

		emitHeader(&code)
		emitImports(&code, isPublic: access == "public", sourceImports: proto.sourceImports)
		code.addBlankLine()

		guard let emitter = emitters[proto.pattern] else {
			preconditionFailure("No emitter registered for pattern: \(proto.pattern)")
		}
		emitter.emit(code: &code, proto: proto, mockName: name, access: access)

		code.addBlankLine()
		return code.output
	}

	/// Generates a single combined file containing all mock implementations.
	///
	/// Unlike ``generate(from:)``, which produces one file per protocol, this method
	/// merges all protocols into a single output with a shared header and deduplicated
	/// import statements. This is the preferred output mode because it produces a stable
	/// filename (`GeneratedMocks.swift`) that can be referenced by build systems at
	/// project-generation time.
	///
	/// - Parameters:
	///   - protocols: The protocol metadata array to generate mocks for.
	///   - isPublic: When `true`, uses `import <moduleName>`. When `false`, uses `@testable import`.
	/// - Returns: The generated Swift source code as a single string containing all mocks.
	public func generateCombinedFile(from protocols: [ProtocolMetadata], isPublic: Bool) -> String {
		var code = CodeBuilder()

		emitHeader(&code)

		let mergedImports = mergeImports(from: protocols)
		emitImports(&code, isPublic: isPublic, sourceImports: mergedImports)

		for proto in protocols {
			let access = proto.accessLevel
			let name = mockName(for: proto)
			code.addBlankLine()

			guard let emitter = emitters[proto.pattern] else {
				preconditionFailure("No emitter registered for pattern: \(proto.pattern)")
			}
			emitter.emit(code: &code, proto: proto, mockName: name, access: access)
		}

		code.addBlankLine()
		return code.output
	}

	// MARK: - Header

	private func emitHeader(_ code: inout CodeBuilder) {
		code.addLine("// Auto-generated by SwiftGenerator — DO NOT EDIT.")
		code.addLine("// Any changes will be overwritten the next time mocks are regenerated.")
		code.addBlankLine()
	}

	// MARK: - Imports

	private func mergeImports(from protocols: [ProtocolMetadata]) -> [String] {
		var seen = Set<String>()
		var result: [String] = []
		for proto in protocols {
			for imp in proto.sourceImports {
				if seen.insert(imp).inserted {
					result.append(imp)
				}
			}
		}
		return result
	}

	private func emitImports(_ code: inout CodeBuilder, isPublic: Bool, sourceImports: [String]) {
		code.addLine("import Foundation")

		let moduleImport = "import \(moduleName)"
		let extraImports = sourceImports.filter { $0 != "import Foundation" && $0 != moduleImport }
		for imp in extraImports {
			code.addLine(imp)
		}

		code.addBlankLine()
		if isPublic {
			code.addLine(moduleImport)
		} else {
			code.addLine("@testable \(moduleImport)")
		}
	}
}
