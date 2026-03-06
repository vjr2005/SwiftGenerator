/// A utility for building indented Swift source code line by line.
///
/// `CodeBuilder` manages a list of lines and an indentation level, making it straightforward
/// to produce well-formatted code with nested blocks. All generated mock code passes through
/// a `CodeBuilder` instance.
///
/// ## Usage
///
/// ```swift
/// var code = CodeBuilder()
/// code.addLine("import Foundation")
/// code.addBlankLine()
/// code.block("final class FooMock: FooContract") { code in
///     code.addLine("var callCount = 0")
/// }
/// print(code.output)
/// // import Foundation
/// //
/// // final class FooMock: FooContract {
/// //     var callCount = 0
/// // }
/// ```
///
/// ## Indentation
///
/// By default, each indentation level uses a single tab character (`\t`).
/// Pass `useTabs: false` to the initializer to use four spaces instead.
public struct CodeBuilder: Sendable {
	private var lines: [String] = []
	private var indentLevel: Int = 0
	private let indentString: String

	/// Creates a new code builder.
	///
	/// - Parameter useTabs: When `true` (the default), indentation uses tab characters.
	///   When `false`, indentation uses four spaces per level.
	public init(useTabs: Bool = true) {
		self.indentString = useTabs ? "\t" : "    "
	}

	/// The accumulated source code as a single string, with lines separated by newline characters.
	///
	/// Call this after building is complete to retrieve the final output.
	public var output: String {
		lines.joined(separator: "\n")
	}

	/// Appends an empty line to the output.
	///
	/// Used to add vertical spacing between sections (e.g., between properties and methods).
	public mutating func addBlankLine() {
		lines.append("")
	}

	/// Appends a line of text at the current indentation level.
	///
	/// The line is automatically prefixed with the appropriate indentation string
	/// (tabs or spaces) repeated for the current nesting depth.
	///
	/// - Parameter text: The source code text to append (without leading indentation).
	public mutating func addLine(_ text: String) {
		let indent = String(repeating: indentString, count: indentLevel)
		lines.append(indent + text)
	}

	/// Opens a new block by appending `header {` and incrementing the indentation level.
	///
	/// Must be paired with a corresponding ``closeBlock()`` call.
	///
	/// - Parameter header: The block header (e.g., `"func foo()"`, `"final class Bar"`).
	public mutating func openBlock(_ header: String) {
		addLine(header + " {")
		indentLevel += 1
	}

	/// Closes the current block by decrementing the indentation level and appending `}`.
	///
	/// The indentation level is clamped to zero to prevent underflow.
	public mutating func closeBlock() {
		indentLevel = max(0, indentLevel - 1)
		addLine("}")
	}

	/// Opens a block, executes a closure to emit the block body, then closes the block.
	///
	/// This is the preferred way to emit nested structures, as it guarantees
	/// that ``openBlock(_:)`` and ``closeBlock()`` are always balanced.
	///
	/// - Parameters:
	///   - header: The block header (e.g., `"if condition"`, `"func bar()"`).
	///   - body: A closure that receives the builder as `inout` to emit the block contents.
	public mutating func block(_ header: String, body: (inout CodeBuilder) -> Void) {
		openBlock(header)
		body(&self)
		closeBlock()
	}
}
