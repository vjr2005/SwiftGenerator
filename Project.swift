import ProjectDescription

let baseSettings: SettingsDictionary = [
	"SWIFT_VERSION": "6.0",
	"SWIFT_STRICT_CONCURRENCY": "complete",
]

let project = Project(
	name: "SwiftGenerator",
	settings: .settings(base: baseSettings),
	targets: [
		// MARK: - SwiftGeneratorKit (Static Framework)
		.target(
			name: "SwiftGeneratorKit",
			destinations: [.mac],
			product: .staticFramework,
			bundleId: "com.swiftgenerator.kit",
			sources: ["Sources/SwiftGeneratorKit/**"],
			dependencies: [
				.external(name: "SwiftSyntax"),
				.external(name: "SwiftParser"),
			]
		),

		// MARK: - SwiftGeneratorCLI (Command Line Tool)
		.target(
			name: "SwiftGeneratorCLI",
			destinations: [.mac],
			product: .commandLineTool,
			bundleId: "com.swiftgenerator.cli",
			sources: ["Sources/CLI/**"],
			dependencies: [
				.target(name: "SwiftGeneratorKit"),
				.external(name: "ArgumentParser"),
			]
		),

		// MARK: - Tests
		.target(
			name: "SwiftGeneratorKitTests",
			destinations: [.mac],
			product: .unitTests,
			bundleId: "com.swiftgenerator.kit.tests",
			sources: ["Tests/SwiftGeneratorKitTests/**"],
			dependencies: [
				.target(name: "SwiftGeneratorKit"),
			]
		),
	],
	schemes: [
		.scheme(
			name: "SwiftGenerator",
			buildAction: .buildAction(targets: [
				.target("SwiftGeneratorKit"),
				.target("SwiftGeneratorCLI"),
			]),
			testAction: .targets(
				[.testableTarget(target: .target("SwiftGeneratorKitTests"))],
				options: .options(coverage: true)
			),
			runAction: .runAction(executable: .target("SwiftGeneratorCLI"))
		),
	]
)
