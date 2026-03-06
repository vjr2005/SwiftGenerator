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
		let parser = ProtocolParser()
		let protocols = try parser.parse(directories: sources)

		if protocols.isEmpty {
			print("No protocols with @mock annotation found.")
			return
		}

		let generator = SwiftGenerator(moduleName: module)
		let fileManager = FileManager.default

		try fileManager.createDirectory(atPath: internalOutput, withIntermediateDirectories: true)
		if let publicOutput {
			try fileManager.createDirectory(atPath: publicOutput, withIntermediateDirectories: true)
		}

		for proto in protocols {
			let code = generator.generate(from: proto)
			let filename = "\(proto.mockName).swift"
			let outputDir = outputDirectory(for: proto)
			let filePath = (outputDir as NSString).appendingPathComponent(filename)
			try code.write(toFile: filePath, atomically: true, encoding: .utf8)
			print("Generated: \(filename)")
		}

		print("\(protocols.count) mock(s) generated.")
	}

	private func outputDirectory(for proto: ProtocolMetadata) -> String {
		if proto.accessLevel == "public", let publicOutput {
			return publicOutput
		}
		return internalOutput
	}
}
