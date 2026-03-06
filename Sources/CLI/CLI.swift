import ArgumentParser
import Foundation
import SwiftGeneratorKit

@main
struct SwiftGeneratorCLI: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "swift-generator",
		abstract: "Generates mock implementations from protocols annotated with // @mock."
	)

	@Option(name: .long, help: "Source directories to scan (can be repeated).")
	var sources: [String]

	@Option(name: .long, help: "Output directory for internal mocks.")
	var internalOutput: String

	@Option(name: .long, help: "Output directory for public mocks (protocols with public access level).")
	var publicOutput: String?

	@Option(name: .long, help: "Module name for imports (e.g., ChallengeCharacter).")
	var module: String

	func run() throws {
		let fileSystem: FileSystem = DefaultFileSystem()
		let parser = ProtocolParser()
		let generator = SwiftGenerator(moduleName: module)

		let protocols = try parseProtocols(from: sources, parser: parser, fileSystem: fileSystem)

		if protocols.isEmpty {
			print("No protocols with @mock annotation found.")
			return
		}

		let internalProtos = protocols.filter { outputDirectory(for: $0) == internalOutput }
		let publicProtos = protocols.filter { outputDirectory(for: $0) != internalOutput }

		if !internalProtos.isEmpty {
			try writeGeneratedFile(
				protocols: internalProtos,
				to: internalOutput,
				isPublic: false,
				generator: generator,
				fileSystem: fileSystem
			)
		}

		if !publicProtos.isEmpty, let publicOutput {
			try writeGeneratedFile(
				protocols: publicProtos,
				to: publicOutput,
				isPublic: true,
				generator: generator,
				fileSystem: fileSystem
			)
		}

		print("\(protocols.count) mock(s) generated.")
	}

	private func writeGeneratedFile(
		protocols: [ProtocolMetadata],
		to directory: String,
		isPublic: Bool,
		generator: SwiftGenerator,
		fileSystem: FileSystem
	) throws {
		try fileSystem.createDirectory(atPath: directory)
		let code = generator.generateCombinedFile(from: protocols, isPublic: isPublic)
		let filePath = (directory as NSString).appendingPathComponent("GeneratedMocks.swift")
		try fileSystem.write(code, toFile: filePath)
		let access = isPublic ? "public" : "internal"
		print("Generated: GeneratedMocks.swift (\(protocols.count) \(access) mock(s))")
	}

	private func parseProtocols(
		from directories: [String],
		parser: ProtocolParser,
		fileSystem: FileSystem
	) throws -> [ProtocolMetadata] {
		var protocols: [ProtocolMetadata] = []
		for directory in directories {
			let files = try fileSystem.files(in: directory, withExtension: "swift")
			for file in files {
				let source = try fileSystem.contents(ofFile: file)
				let parsed = parser.parse(source: source, filePath: file)
				protocols.append(contentsOf: parsed)
			}
		}
		return protocols
	}

	private func outputDirectory(for proto: ProtocolMetadata) -> String {
		if proto.accessLevel == "public", let publicOutput {
			return publicOutput
		}
		return internalOutput
	}
}
