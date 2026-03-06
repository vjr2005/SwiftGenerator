import Testing

@testable import SwiftGeneratorKit

@Suite("ProtocolParser")
struct ProtocolParserTests {
	let sut = ProtocolParser()

	// MARK: - Annotation Detection

	@Test("Ignores protocols without @mock annotation")
	func ignoresUnannotated() {
		let source = """
		protocol FooContract {
			func bar()
		}
		"""

		let result = sut.parse(source: source)

		#expect(result.isEmpty)
	}

	@Test("Detects // @mock annotation")
	func detectsMockAnnotation() {
		let source = """
		// @mock
		protocol FooContract {
			func bar()
		}
		"""

		let result = sut.parse(source: source)

		#expect(result.count == 1)
		#expect(result[0].name == "FooContract")
	}

	@Test("Infers public access level from protocol declaration")
	func infersPublicAccessLevel() {
		let source = """
		// @mock
		public protocol FooContract {
			func bar()
		}
		"""

		let result = sut.parse(source: source)

		#expect(result.count == 1)
		#expect(result[0].accessLevel == "public")
	}

	// MARK: - Pattern Inference

	@Test("Infers mainActor pattern for simple protocol")
	func infersMainActorPattern() {
		let source = """
		// @mock
		protocol FooContract {
			func bar()
		}
		"""

		let result = sut.parse(source: source)

		#expect(result[0].pattern == .mainActor)
		#expect(result[0].needsUncheckedSendable == false)
	}

	@Test("Infers mainActor pattern with Sendable inheritance")
	func infersMainActorWithSendable() {
		let source = """
		// @mock
		protocol FooContract: Sendable {
			func execute() async
		}
		"""

		let result = sut.parse(source: source)

		#expect(result[0].pattern == .mainActor)
		#expect(result[0].needsUncheckedSendable == true)
	}

	@Test("Infers nonisolated pattern")
	func infersNonisolatedPattern() {
		let source = """
		// @mock
		nonisolated protocol FooContract: Sendable {
			@concurrent func fetch() async throws -> String
		}
		"""

		let result = sut.parse(source: source)

		#expect(result[0].pattern == .nonisolated)
		#expect(result[0].needsUncheckedSendable == true)
	}

	@Test("Infers actor pattern")
	func infersActorPattern() {
		let source = """
		// @mock
		protocol FooContract: Actor {
			func getValue() -> String?
			func saveValue(_ value: String)
		}
		"""

		let result = sut.parse(source: source)

		#expect(result[0].pattern == .actor)
	}

	// MARK: - Method Parsing

	@Test("Parses simple void method")
	func parsesSimpleMethod() {
		let source = """
		// @mock
		protocol FooContract {
			func bar()
		}
		"""

		let method = sut.parse(source: source)[0].methods[0]

		#expect(method.name == "bar")
		#expect(method.parameters.isEmpty)
		#expect(method.returnType == nil)
		#expect(method.isAsync == false)
		#expect(method.isThrowing == false)
	}

	@Test("Parses async throwing method with typed throws")
	func parsesTypedThrowsMethod() {
		let source = """
		// @mock
		protocol FooContract: Sendable {
			func execute(identifier: Int) async throws(FooError) -> String
		}
		"""

		let method = sut.parse(source: source)[0].methods[0]

		#expect(method.name == "execute")
		#expect(method.isAsync == true)
		#expect(method.isThrowing == true)
		#expect(method.throwsType == "FooError")
		#expect(method.returnType == "String")
	}

	@Test("Parses method with @concurrent attribute")
	func parsesConcurrentMethod() {
		let source = """
		// @mock
		nonisolated protocol FooContract: Sendable {
			@concurrent func fetch(page: Int) async throws -> Data
		}
		"""

		let method = sut.parse(source: source)[0].methods[0]

		#expect(method.isConcurrent == true)
		#expect(method.isAsync == true)
		#expect(method.isThrowing == true)
		#expect(method.throwsType == nil)
	}

	@Test("Parses method parameters with external labels")
	func parsesParameterLabels() {
		let source = """
		// @mock
		protocol FooContract {
			func update(_ value: String, at index: Int)
		}
		"""

		let params = sut.parse(source: source)[0].methods[0].parameters

		#expect(params.count == 2)
		#expect(params[0].externalLabel == "_")
		#expect(params[0].internalName == "value")
		#expect(params[0].type == "String")
		#expect(params[1].externalLabel == "at")
		#expect(params[1].internalName == "index")
		#expect(params[1].type == "Int")
	}

	@Test("Parses generic method")
	func parsesGenericMethod() {
		let source = """
		// @mock
		protocol FooContract: Sendable {
			@concurrent func execute<T: Decodable>(_ operation: String) async throws -> T
		}
		"""

		let method = sut.parse(source: source)[0].methods[0]

		#expect(method.hasGenericReturn == true)
		#expect(method.genericClause == "<T: Decodable>")
		#expect(method.returnType == "T")
	}

	// MARK: - Property Parsing

	@Test("Parses get-only property")
	func parsesGetOnlyProperty() {
		let source = """
		// @mock
		protocol FooContract {
			var name: String { get }
		}
		"""

		let prop = sut.parse(source: source)[0].properties[0]

		#expect(prop.name == "name")
		#expect(prop.type == "String")
		#expect(prop.isSettable == false)
	}

	@Test("Parses get-set property")
	func parsesGetSetProperty() {
		let source = """
		// @mock
		protocol FooContract {
			var filter: String { get set }
		}
		"""

		let prop = sut.parse(source: source)[0].properties[0]

		#expect(prop.name == "filter")
		#expect(prop.isSettable == true)
	}

	// MARK: - Inherited Types

	@Test("Parses multiple inherited types")
	func parsesMultipleInheritedTypes() {
		let source = """
		// @mock
		protocol FooContract: AnyObject, Sendable {
			func bar()
		}
		"""

		let proto = sut.parse(source: source)[0]

		#expect(proto.inheritedTypes == ["AnyObject", "Sendable"])
		#expect(proto.requiresSendable == true)
	}

	// MARK: - Multiple Protocols

	@Test("Parses only annotated protocols from file with multiple protocols")
	func parsesOnlyAnnotated() {
		let source = """
		protocol IgnoredContract {
			func ignored()
		}

		// @mock
		protocol AnnotatedContract {
			func annotated()
		}
		"""

		let result = sut.parse(source: source)

		#expect(result.count == 1)
		#expect(result[0].name == "AnnotatedContract")
	}
}
