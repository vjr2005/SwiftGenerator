/// Emits `final class` mocks for MainActor and Nonisolated patterns.
struct ClassMockEmitter: MockEmitter {
	let nonisolated: Bool

	func emit(code: inout CodeBuilder, proto: ProtocolMetadata, mockName: String, access: String) {
		let prefix = MockEmission.accessPrefix(access)
		let nonisolatedKeyword = nonisolated ? "nonisolated " : ""
		let sendable = proto.requiresSendable ? ", @unchecked Sendable" : ""
		let header = "\(prefix)\(nonisolatedKeyword)final class \(mockName): \(proto.name)\(sendable)"

		code.addLine("// periphery:ignore:all")
		code.block(header) { code in
			emitProtocolProperties(&code, proto: proto, access: access)
			for (index, method) in proto.methods.enumerated() {
				if index > 0 || !proto.properties.isEmpty {
					code.addBlankLine()
				}
				MockEmission.emitMethodProperties(&code, method: method, access: access)
			}
			emitInit(&code, proto: proto, access: access)
			for method in proto.methods {
				code.addBlankLine()
				MockEmission.emitMethodImpl(&code, method: method, access: access, isConcurrent: nonisolated && method.isConcurrent)
			}
			MockEmission.emitReset(&code, proto: proto, access: access)
		}
	}

	// MARK: - Protocol Properties

	private func emitProtocolProperties(_ code: inout CodeBuilder, proto: ProtocolMetadata, access: String) {
		let prefix = MockEmission.accessPrefix(access)
		for prop in proto.properties {
			code.addLine("\(prefix)var \(prop.name): \(prop.type)")
		}
	}

	// MARK: - Init

	private func emitInit(_ code: inout CodeBuilder, proto: ProtocolMetadata, access: String) {
		let nonOptionalProps = proto.properties.filter { !$0.isOptional }
		guard !nonOptionalProps.isEmpty || !access.isEmpty else { return }

		let prefix = MockEmission.accessPrefix(access)
		code.addBlankLine()

		if nonOptionalProps.isEmpty {
			code.addLine("\(prefix)init() {}")
		} else {
			let params = nonOptionalProps.map { "\($0.name): \($0.type)" }.joined(separator: ", ")
			code.block("\(prefix)init(\(params))") { code in
				for prop in nonOptionalProps {
					code.addLine("self.\(prop.name) = \(prop.name)")
				}
			}
		}
	}
}
