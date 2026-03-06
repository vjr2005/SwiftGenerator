// swift-tools-version: 6.0

#if TUIST
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
	productTypes: [
		"SwiftSyntax": .framework,
		"SwiftParser": .framework,
		"ArgumentParser": .framework,
	]
)
#endif

import PackageDescription

let binaryChecksum = "fd9e79328f315c86e78f5cbec5da4212395f13e157e40adf20c77fbba259bd5b"

var products: [Product] = [
	.executable(name: "swift-generator", targets: ["SwiftGeneratorCLI"]),
	.plugin(name: "GenerateMocks", targets: ["GenerateMocks"]),
]

var targets: [Target] = [
	.target(
		name: "SwiftGeneratorKit",
		dependencies: [
			.product(name: "SwiftSyntax", package: "swift-syntax"),
			.product(name: "SwiftParser", package: "swift-syntax"),
		],
		path: "Sources/SwiftGeneratorKit"
	),
	.executableTarget(
		name: "SwiftGeneratorCLI",
		dependencies: [
			"SwiftGeneratorKit",
			.product(name: "ArgumentParser", package: "swift-argument-parser"),
		],
		path: "Sources/CLI"
	),
	.testTarget(
		name: "SwiftGeneratorKitTests",
		dependencies: ["SwiftGeneratorKit"],
		path: "Tests/SwiftGeneratorKitTests"
	),
	.plugin(
		name: "GenerateMocks",
		capability: .command(
			intent: .custom(
				verb: "generate-mocks",
				description: "Generate mock implementations from @mock-annotated protocols."
			),
			permissions: [
				.writeToPackageDirectory(
					reason: "Writes generated mock files to the specified output directories."
				),
			]
		),
		dependencies: [
			binaryChecksum != "PLACEHOLDER"
				? .target(name: "SwiftGeneratorBinary")
				: .target(name: "SwiftGeneratorCLI"),
		],
		path: "Plugins/GenerateMocks"
	),
]

if binaryChecksum != "PLACEHOLDER" {
	targets.append(
		.binaryTarget(
			name: "SwiftGeneratorBinary",
			url: "https://github.com/vjr2005/SwiftGenerator/releases/download/1.0.0/swift-generator.artifactbundle.zip",
			checksum: binaryChecksum
		)
	)
}

let package = Package(
	name: "SwiftGenerator",
	platforms: [.macOS(.v13)],
	products: products,
	dependencies: [
		.package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.1"),
		.package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
	],
	targets: targets
)
