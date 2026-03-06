import Foundation
import PackagePlugin

@main
struct GenerateMocksPlugin: CommandPlugin {
	func performCommand(
		context: PluginContext,
		arguments: [String]
	) async throws {
		let tool = try context.tool(named: "swift-generator")

		var extractor = ArgumentExtractor(arguments)

		let targetNames = extractor.extractOption(named: "target")
		let moduleOverride = extractor.extractOption(named: "module").first
		let internalOutput = extractor.extractOption(named: "internal-output").first
		let publicOutput = extractor.extractOption(named: "public-output").first
		let manualSources = extractor.extractOption(named: "sources")

		let targets: [Target]
		if targetNames.isEmpty {
			targets = context.package.targets.filter {
				$0 is SwiftSourceModuleTarget && !$0.name.hasSuffix("Tests")
			}
		} else {
			targets = try targetNames.map { name in
				guard let target = context.package.targets.first(where: { $0.name == name }) else {
					throw GenerateMocksPluginError.targetNotFound(name)
				}
				return target
			}
		}

		for target in targets {
			let moduleName = moduleOverride ?? target.name

			let sourceDirs: [String]
			if !manualSources.isEmpty {
				sourceDirs = manualSources
			} else {
				sourceDirs = [target.directory.string]
			}

			let defaultInternalOutput = context.package.directory
				.appending(subpath: "Tests")
				.appending(subpath: "\(target.name)Tests")
				.appending(subpath: "Mocks")
				.string

			let resolvedInternalOutput = internalOutput ?? defaultInternalOutput

			var toolArguments: [String] = []
			for source in sourceDirs {
				toolArguments.append(contentsOf: ["--sources", source])
			}
			toolArguments.append(contentsOf: ["--internal-output", resolvedInternalOutput])
			if let publicOutput {
				toolArguments.append(contentsOf: ["--public-output", publicOutput])
			}
			toolArguments.append(contentsOf: ["--module", moduleName])
			toolArguments.append(contentsOf: extractor.remainingArguments)

			print("Generating mocks for target '\(target.name)' (module: \(moduleName))...")
			print("  Sources: \(sourceDirs.joined(separator: ", "))")
			print("  Output:  \(resolvedInternalOutput)")

			try tool.path.exec(arguments: toolArguments)

			print("Done generating mocks for '\(target.name)'.")
		}
	}
}
