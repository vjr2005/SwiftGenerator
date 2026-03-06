import Foundation

/// Abstraction over file system operations for testability and separation of I/O from domain logic.
///
/// By depending on `FileSystem` instead of `FileManager` directly, the CLI layer can be tested
/// with a stub implementation that reads from and writes to in-memory buffers.
///
/// ## Built-in implementation
///
/// ``DefaultFileSystem`` provides the standard implementation backed by `Foundation.FileManager`.
///
/// ## Custom implementations
///
/// Conform to this protocol to provide alternative I/O behavior (e.g., in-memory file systems
/// for testing, or remote file storage):
///
/// ```swift
/// struct InMemoryFileSystem: FileSystem {
///     var files: [String: String] = [:]
///
///     func files(in directory: String, withExtension ext: String) throws -> [String] { … }
///     func contents(ofFile path: String) throws -> String { … }
///     func createDirectory(atPath path: String) throws { … }
///     func write(_ string: String, toFile path: String) throws { … }
/// }
/// ```
public protocol FileSystem: Sendable {

	/// Recursively enumerates files in a directory that match the given file extension.
	///
	/// The search skips hidden files and directories (those starting with `.`).
	/// Results are returned sorted alphabetically by path.
	///
	/// - Parameters:
	///   - directory: The absolute path to the directory to search.
	///   - ext: The file extension to match, without the leading dot (e.g., `"swift"`, `"json"`).
	/// - Returns: An array of absolute file paths matching the extension, sorted alphabetically.
	/// - Throws: An error if the directory cannot be accessed.
	func files(in directory: String, withExtension ext: String) throws -> [String]

	/// Reads and returns the entire contents of a file as a UTF-8 string.
	///
	/// - Parameter path: The absolute path to the file to read.
	/// - Returns: The file contents as a string.
	/// - Throws: An error if the file cannot be read or is not valid UTF-8.
	func contents(ofFile path: String) throws -> String

	/// Creates a directory at the given path, including any intermediate directories.
	///
	/// If the directory already exists, this method succeeds silently.
	///
	/// - Parameter path: The absolute path of the directory to create.
	/// - Throws: An error if the directory cannot be created.
	func createDirectory(atPath path: String) throws

	/// Writes a string to a file atomically using UTF-8 encoding.
	///
	/// If the file already exists, it is overwritten. The write is performed atomically
	/// (the content is written to a temporary file first, then renamed) to prevent
	/// partial writes.
	///
	/// - Parameters:
	///   - string: The content to write.
	///   - path: The absolute path of the file to write.
	/// - Throws: An error if the file cannot be written.
	func write(_ string: String, toFile path: String) throws
}

/// The default file system implementation backed by `Foundation.FileManager`.
///
/// This is the standard implementation used by the CLI. All operations delegate
/// directly to `FileManager.default` and `String` file I/O methods.
public struct DefaultFileSystem: FileSystem {

	/// Creates a new default file system instance.
	public init() {}

	/// Recursively enumerates files matching the given extension using `FileManager.enumerator`.
	///
	/// - Parameters:
	///   - directory: The absolute path to the directory to search.
	///   - ext: The file extension to match, without the leading dot (e.g., `"swift"`).
	/// - Returns: An array of absolute file paths, sorted alphabetically.
	/// - Throws: An error if the directory cannot be accessed.
	public func files(in directory: String, withExtension ext: String) throws -> [String] {
		let url = URL(fileURLWithPath: directory)
		guard let enumerator = FileManager.default.enumerator(
			at: url,
			includingPropertiesForKeys: [.isRegularFileKey],
			options: [.skipsHiddenFiles]
		) else {
			return []
		}

		var files: [String] = []
		for case let fileURL as URL in enumerator {
			if fileURL.pathExtension == ext {
				files.append(fileURL.path)
			}
		}
		return files.sorted()
	}

	/// Reads the entire contents of a file as a UTF-8 string.
	///
	/// - Parameter path: The absolute path to the file to read.
	/// - Returns: The file contents as a string.
	/// - Throws: An error if the file cannot be read or contains invalid UTF-8.
	public func contents(ofFile path: String) throws -> String {
		try String(contentsOfFile: path, encoding: .utf8)
	}

	/// Creates a directory at the given path, including any intermediate directories.
	///
	/// - Parameter path: The absolute path of the directory to create.
	/// - Throws: An error if the directory cannot be created.
	public func createDirectory(atPath path: String) throws {
		try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
	}

	/// Writes a string to a file atomically using UTF-8 encoding.
	///
	/// - Parameters:
	///   - string: The content to write.
	///   - path: The absolute path of the file to write.
	/// - Throws: An error if the file cannot be written.
	public func write(_ string: String, toFile path: String) throws {
		try string.write(toFile: path, atomically: true, encoding: .utf8)
	}
}
