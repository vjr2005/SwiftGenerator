/// Emits `actor` mocks for protocols that inherit from `Actor`.
struct ActorMockEmitter: MockEmitter {
	func emit(code: inout CodeBuilder, proto: ProtocolMetadata, mockName: String, access: String) {
		let prefix = MockEmission.accessPrefix(access)
		let header = "\(prefix)actor \(mockName): \(proto.name)"

		code.addLine("// periphery:ignore:all")
		code.block(header) { code in
			for (index, method) in proto.methods.enumerated() {
				if index > 0 { code.addBlankLine() }
				MockEmission.emitMethodProperties(&code, method: method, access: access)
			}
			emitActorSetters(&code, proto: proto, access: access)
			for method in proto.methods {
				code.addBlankLine()
				MockEmission.emitMethodImpl(&code, method: method, access: access, isConcurrent: false)
			}
			MockEmission.emitReset(&code, proto: proto, access: access)
		}
	}

	// MARK: - Actor Setters

	private func emitActorSetters(_ code: inout CodeBuilder, proto: ProtocolMetadata, access: String) {
		let prefix = MockEmission.accessPrefix(access)

		for method in proto.methods {
			let cap = method.name.capitalizedFirst

			if method.isThrowing, let returnType = method.returnType {
				let errorType = method.throwsType ?? "any Error"
				let type = method.hasGenericReturn ? "Any?" : "Result<\(returnType), \(errorType)>?"
				code.addBlankLine()
				code.block("\(prefix)func set\(cap)ReturnValue(_ value: \(type))") { code in
					code.addLine("\(method.name)ReturnValue = value")
				}
			} else if method.isThrowing && method.returnType == nil {
				let errorType = method.throwsType ?? "any Error"
				code.addBlankLine()
				code.block("\(prefix)func set\(cap)ThrowableError(_ error: (\(errorType))?)") { code in
					code.addLine("\(method.name)ThrowableError = error")
				}
			} else if let returnType = method.returnType {
				let type = method.hasGenericReturn ? "Any?" : MockEmission.optionalType(returnType)
				code.addBlankLine()
				code.block("\(prefix)func set\(cap)ReturnValue(_ value: \(type))") { code in
					code.addLine("\(method.name)ReturnValue = value")
				}
			}

			code.addBlankLine()
			let closureType = method.isAsync ? "(() async -> Void)?" : "(() -> Void)?"
			code.block("\(prefix)func set\(cap)Closure(_ closure: \(closureType))") { code in
				code.addLine("\(method.name)Closure = closure")
			}
		}
	}
}
