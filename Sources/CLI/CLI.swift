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

		try fileSystem.createDirectory(atPath: internalOutput)
		if let publicOutput {
			try fileSystem.createDirectory(atPath: publicOutput)
		}

		for proto in protocols {
			let code = generator.generate(from: proto)
			let mockName = generator.mockName(for: proto)
			let filename = "\(mockName).swift"
			let outputDir = outputDirectory(for: proto)
			let filePath = (outputDir as NSString).appendingPathComponent(filename)
			try fileSystem.write(code, toFile: filePath)
			print("Generated: \(filename)")
		}

		print("\(protocols.count) mock(s) generated.")
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
