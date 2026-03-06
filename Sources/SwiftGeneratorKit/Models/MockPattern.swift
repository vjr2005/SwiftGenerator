/// The concurrency pattern to apply when generating a mock.
public enum MockPattern: Sendable, Equatable {
	/// Default MainActor isolation (plain `final class`).
	/// Optionally adds `@unchecked Sendable` when the contract requires `Sendable`.
	case mainActor

	/// Nonisolated pattern (`nonisolated final class: @unchecked Sendable`).
	/// Methods get `@concurrent` when the contract uses it.
	case nonisolated

	/// Actor pattern (`actor`).
	/// Used for contracts that inherit from `Actor`.
	case actor
}
