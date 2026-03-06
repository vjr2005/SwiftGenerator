/// Utility for building indented Swift source code.
public struct CodeBuilder: Sendable {
	private var lines: [String] = []
	private var indentLevel: Int = 0
	private let indentString: String

	public init(useTabs: Bool = true) {
		self.indentString = useTabs ? "\t" : "    "
	}

	/// The built source code string.
	public var output: String {
		lines.joined(separator: "\n")
	}

	/// Adds an empty line.
	public mutating func addBlankLine() {
		lines.append("")
	}

	/// Adds a line at the current indent level.
	public mutating func addLine(_ text: String) {
		let indent = String(repeating: indentString, count: indentLevel)
		lines.append(indent + text)
	}

	/// Opens a block (adds `{` and increments indent).
	public mutating func openBlock(_ header: String) {
		addLine(header + " {")
		indentLevel += 1
	}

	/// Closes a block (decrements indent and adds `}`).
	public mutating func closeBlock() {
		indentLevel = max(0, indentLevel - 1)
		addLine("}")
	}

	/// Executes a closure within a block.
	public mutating func block(_ header: String, body: (inout CodeBuilder) -> Void) {
		openBlock(header)
		body(&self)
		closeBlock()
	}
}
