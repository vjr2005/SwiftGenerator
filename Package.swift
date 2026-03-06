// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "SwiftGenerator",
	platforms: [.macOS(.v13)],
	products: [
		.executable(name: "swift-generator", targets: ["SwiftGeneratorCLI"]),
	],
	dependencies: [
		.package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.1"),
		.package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
	],
	targets: [
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
	]
)
