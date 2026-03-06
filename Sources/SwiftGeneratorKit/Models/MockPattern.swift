/// The concurrency pattern to apply when generating a mock type.
///
/// SwiftGenerator infers the pattern from protocol traits (see ``ProtocolMetadata/pattern``)
/// and selects the corresponding ``MockEmitter`` to produce the mock declaration.
///
/// ## Pattern selection rules
///
/// | Protocol trait              | Pattern         |
/// |-----------------------------|-----------------|
/// | Inherits `Actor`            | ``actor``       |
/// | Has `nonisolated` modifier  | ``nonisolated`` |
/// | Everything else             | ``mainActor``   |
public enum MockPattern: Sendable, Hashable {
	/// Default MainActor isolation — generates a plain `final class`.
	///
	/// When the protocol requires `Sendable` conformance, the generated class
	/// also conforms to `@unchecked Sendable`.
	///
	/// ```swift
	/// // Input:
	/// // @mock
	/// protocol FooContract: Sendable { … }
	///
	/// // Output:
	/// final class FooMock: FooContract, @unchecked Sendable { … }
	/// ```
	case mainActor

	/// Nonisolated pattern — generates a `nonisolated final class` conforming to `@unchecked Sendable`.
	///
	/// Methods annotated with `@concurrent` in the protocol preserve that attribute in the mock.
	///
	/// ```swift
	/// // Input:
	/// // @mock
	/// nonisolated protocol FooContract: Sendable {
	///     @concurrent func fetch() async throws -> Data
	/// }
	///
	/// // Output:
	/// nonisolated final class FooMock: FooContract, @unchecked Sendable {
	///     @concurrent func fetch() async throws -> Data { … }
	/// }
	/// ```
	case nonisolated

	/// Actor pattern — generates an `actor` type.
	///
	/// Used for protocols that inherit from `Actor`. The generated mock includes
	/// setter methods for configuring return values and closures from outside
	/// the actor's isolation domain.
	///
	/// ```swift
	/// // Input:
	/// // @mock
	/// protocol FooContract: Actor { … }
	///
	/// // Output:
	/// actor FooMock: FooContract { … }
	/// ```
	case actor
}
