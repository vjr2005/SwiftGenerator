/// A strategy for emitting a mock type declaration and body.
///
/// Each ``MockPattern`` maps to a `MockEmitter` implementation that knows how to produce
/// the correct type declaration (class vs actor), conformance clauses, and body structure.
///
/// ## Built-in emitters
///
/// - `ClassMockEmitter` — handles ``MockPattern/mainActor`` and ``MockPattern/nonisolated``
/// - `ActorMockEmitter` — handles ``MockPattern/actor``
///
/// ## Custom emitters
///
/// Implement this protocol to support custom mock patterns, then register the emitter
/// via ``SwiftGenerator/init(moduleName:mockNameSuffixes:emitters:)``:
///
/// ```swift
/// struct MyCustomEmitter: MockEmitter {
///     func emit(code: inout CodeBuilder, proto: ProtocolMetadata, mockName: String, access: String) {
///         // Emit the full type declaration and body
///     }
/// }
/// ```
public protocol MockEmitter: Sendable {

	/// Emits the complete mock type declaration and body into the code builder.
	///
	/// The implementation is responsible for:
	/// 1. The `// periphery:ignore:all` comment
	/// 2. The type declaration (class/actor with conformances)
	/// 3. All stored properties (tracking, return values, closures)
	/// 4. Initializer (if needed)
	/// 5. Method implementations
	/// 6. The `reset()` method
	///
	/// - Parameters:
	///   - code: The code builder to emit into, at the current indentation level.
	///   - proto: The protocol metadata to generate a mock for.
	///   - mockName: The computed mock type name (e.g., `"FooTrackerMock"`).
	///   - access: The access level keyword (`"public"`, `"package"`, or `""` for internal).
	func emit(code: inout CodeBuilder, proto: ProtocolMetadata, mockName: String, access: String)
}

/// Shared emission helpers used by all mock emitters.
///
/// `MockEmission` provides static methods for generating the parts of a mock that are
/// identical across all ``MockPattern`` variants: tracking properties, method implementations,
/// reset logic, and method signature construction.
enum MockEmission {

	static func accessPrefix(_ access: String) -> String {
		access.isEmpty ? "" : "\(access) "
	}

	static func optionalType(_ type: String) -> String {
		if type.hasSuffix("?") { return type }
		if type.hasPrefix("any ") || type.hasPrefix("some ") || type.contains("->") {
			return "(\(type))?"
		}
		return "\(type)?"
	}

	// MARK: - Method Properties

	static func emitMethodProperties(_ code: inout CodeBuilder, method: MethodMetadata, access: String) {
		let prefix = accessPrefix(access)
		let ppVar = "\(prefix)private(set) var"

		// CallsCount
		code.addLine("\(ppVar) \(method.name)CallsCount = 0")

		// Received params
		if method.parameters.count == 1 {
			let param = method.parameters[0]
			code.addLine("\(ppVar) \(method.name)Received\(param.trackingName.capitalizedFirst): \(optionalType(param.type))")
		} else if method.parameters.count > 1 {
			let tupleType = method.parameters.map { "\($0.internalName): \($0.type)" }.joined(separator: ", ")
			code.addLine("\(ppVar) \(method.name)ReceivedArguments: (\(tupleType))?")
		}

		// ReceivedInvocations
		if !method.parameters.isEmpty {
			if method.parameters.count == 1 {
				let param = method.parameters[0]
				code.addLine("\(ppVar) \(method.name)ReceivedInvocations: [\(param.type)] = []")
			} else {
				let tupleType = method.parameters.map { "\($0.internalName): \($0.type)" }.joined(separator: ", ")
				code.addLine("\(ppVar) \(method.name)ReceivedInvocations: [(\(tupleType))] = []")
			}
		}

		// ReturnValue
		if method.isThrowing, let returnType = method.returnType {
			let errorType = method.throwsType ?? "any Error"
			let type = method.hasGenericReturn ? "Any?" : "Result<\(returnType), \(errorType)>?"
			code.addLine("\(prefix)var \(method.name)ReturnValue: \(type)")
		} else if method.isThrowing && method.returnType == nil {
			let errorType = method.throwsType ?? "any Error"
			code.addLine("\(prefix)var \(method.name)ThrowableError: (\(errorType))?")
		} else if let returnType = method.returnType {
			let type = method.hasGenericReturn ? "Any?" : optionalType(returnType)
			code.addLine("\(prefix)var \(method.name)ReturnValue: \(type)")
		}

		// Closure
		let closureType = method.isAsync ? "(() async -> Void)?" : "(() -> Void)?"
		code.addLine("\(prefix)var \(method.name)Closure: \(closureType)")
	}

	// MARK: - Method Implementation

	static func emitMethodImpl(
		_ code: inout CodeBuilder,
		method: MethodMetadata,
		access: String,
		isConcurrent: Bool
	) {
		let prefix = accessPrefix(access)
		let signature = buildMethodSignature(method, prefix: prefix, isConcurrent: isConcurrent)

		code.block(signature) { code in
			code.addLine("\(method.name)CallsCount += 1")

			if method.parameters.count == 1 {
				let param = method.parameters[0]
				code.addLine("\(method.name)Received\(param.trackingName.capitalizedFirst) = \(param.internalName)")
				code.addLine("\(method.name)ReceivedInvocations.append(\(param.internalName))")
			} else if method.parameters.count > 1 {
				let args = method.parameters.map { $0.internalName }.joined(separator: ", ")
				code.addLine("\(method.name)ReceivedArguments = (\(args))")
				code.addLine("\(method.name)ReceivedInvocations.append((\(args)))")
			}

			if method.isAsync {
				code.addLine("await \(method.name)Closure?()")
			} else {
				code.addLine("\(method.name)Closure?()")
			}

			if method.isThrowing, let returnType = method.returnType {
				if method.hasGenericReturn {
					code.addLine("guard let returnValue = \(method.name)ReturnValue as? \(returnType) else {")
					code.addLine("\tpreconditionFailure(\"\(method.name)ReturnValue not configured or type mismatch\")")
					code.addLine("}")
					code.addLine("return returnValue")
				} else {
					code.addLine("guard let returnValue = \(method.name)ReturnValue else {")
					code.addLine("\tpreconditionFailure(\"\(method.name)ReturnValue not configured\")")
					code.addLine("}")
					code.addLine("return try returnValue.get()")
				}
			} else if method.isThrowing && method.returnType == nil {
				code.addLine("if let error = \(method.name)ThrowableError { throw error }")
			} else if let returnType = method.returnType {
				if method.hasGenericReturn {
					code.addLine("guard let returnValue = \(method.name)ReturnValue as? \(returnType) else {")
					code.addLine("\tpreconditionFailure(\"\(method.name)ReturnValue not configured or type mismatch\")")
					code.addLine("}")
					code.addLine("return returnValue")
				} else if returnType.hasSuffix("?") {
					code.addLine("return \(method.name)ReturnValue")
				} else {
					code.addLine("guard let returnValue = \(method.name)ReturnValue else {")
					code.addLine("\tpreconditionFailure(\"\(method.name)ReturnValue not configured\")")
					code.addLine("}")
					code.addLine("return returnValue")
				}
			}
		}
	}

	// MARK: - Reset

	static func emitReset(_ code: inout CodeBuilder, proto: ProtocolMetadata, access: String) {
		let prefix = accessPrefix(access)

		code.addBlankLine()
		code.addLine("// MARK: - Reset")
		code.addBlankLine()
		code.block("\(prefix)func reset()") { code in
			for method in proto.methods {
				code.addLine("\(method.name)CallsCount = 0")

				if method.parameters.count == 1 {
					let param = method.parameters[0]
					code.addLine("\(method.name)Received\(param.trackingName.capitalizedFirst) = nil")
					code.addLine("\(method.name)ReceivedInvocations = []")
				} else if method.parameters.count > 1 {
					code.addLine("\(method.name)ReceivedArguments = nil")
					code.addLine("\(method.name)ReceivedInvocations = []")
				}
			}
		}
	}

	// MARK: - Signature

	static func buildMethodSignature(_ method: MethodMetadata, prefix: String, isConcurrent: Bool) -> String {
		var parts: [String] = []

		if isConcurrent {
			parts.append("@concurrent")
		}

		parts.append("\(prefix)func \(method.name)")

		if let genericClause = method.genericClause {
			let last = parts.removeLast()
			parts.append(last + genericClause)
		}

		let params = method.parameters.map { $0.declaration }.joined(separator: ", ")
		let lastIdx = parts.count - 1
		parts[lastIdx] = parts[lastIdx] + "(\(params))"

		if method.isAsync { parts.append("async") }

		if method.isThrowing {
			if let throwsType = method.throwsType {
				parts.append("throws(\(throwsType))")
			} else {
				parts.append("throws")
			}
		}

		if let returnType = method.returnType {
			parts.append("-> \(returnType)")
		}

		return parts.joined(separator: " ")
	}
}

// MARK: - Internal Helpers

extension String {
	var capitalizedFirst: String {
		guard let first = self.first else { return self }
		return first.uppercased() + dropFirst()
	}
}
