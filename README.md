# SwiftGenerator

An extensible Swift code generation toolkit powered by [SwiftSyntax](https://github.com/swiftlang/swift-syntax). It parses Swift source files and produces derived code based on annotations, designed for Swift 6 concurrency patterns.

SwiftGenerator ships with a **Mock Generator** as its first built-in generator, with more generators planned for the future.

## Table of Contents

- [Why SwiftGenerator](#why-swiftgenerator)
- [Requirements](#requirements)
- [Installation](#installation)
  - [Quick Start (Bootstrap)](#quick-start-bootstrap)
  - [Build from Source](#build-from-source)
  - [Release Binary](#release-binary)
  - [Swift Package Manager](#swift-package-manager)
- [Development](#development)
  - [Prerequisites](#prerequisites)
  - [Project Setup](#project-setup)
  - [Available Commands](#available-commands)
- [Generators](#generators)
  - [Mock Generator](#mock-generator)
    - [Quick Start](#quick-start)
    - [Annotation Format](#annotation-format)
    - [Mock Patterns](#mock-patterns)
    - [Generated Mock Structure](#generated-mock-structure)
    - [Advanced Mock Features](#advanced-mock-features)
- [CLI Reference](#cli-reference)
- [Integration](#integration)
  - [Build Script](#build-script)
  - [Xcode Build Phase](#xcode-build-phase)
- [Architecture](#architecture)
  - [Design Principles](#design-principles)
  - [Adding New Generators](#adding-new-generators)
  - [Using SwiftGeneratorKit as a Library](#using-swiftgeneratorkit-as-a-library)
- [Testing](#testing)
- [Roadmap](#roadmap)
- [License](#license)

---

## Why SwiftGenerator

- **Accurate parsing** — uses SwiftSyntax to analyze real Swift ASTs, not regex or string matching.
- **Swift 6 native** — full support for `nonisolated` protocols, `@concurrent` methods, `actor` protocols, and typed `throws`.
- **Opt-in** — only declarations with explicit annotations (e.g., `// @mock`) are processed. Your codebase stays clean.
- **Extensible** — the architecture is designed around pluggable generators. The parser extracts metadata once, and multiple generators can consume it to produce different outputs.

---

## Requirements

- **Swift 6.0** or later
- **macOS 13** or later
- **[mise](https://mise.jdx.dev)** (for development with Tuist)

---

## Installation

### mise (recommended)

Install the pre-built binary via [mise](https://mise.jdx.dev):

```bash
# Install globally
mise use -g ubi:vjr2005/SwiftGenerator

# Or pin a version
mise use -g ubi:vjr2005/SwiftGenerator@1.0.0
```

Or add it to your project's `mise.toml`:

```toml
[tools]
"ubi:vjr2005/SwiftGenerator" = "1.0.0"

[tasks.generate-mocks]
description = "Generate mocks from @mock-annotated protocols"
run = """
swift-generator \
    --sources Sources/MyFeature \
    --internal-output Tests/MyFeatureTests/Mocks \
    --module MyFeature
"""
```

After `mise install`, run `swift-generator` directly or `mise run generate-mocks`.

### From Sources (SPM)

Ideal for integrating `SwiftGeneratorKit` as a library or using the SPM command plugin:

```swift
dependencies: [
    .package(url: "https://github.com/vjr2005/SwiftGenerator", from: "1.0.0"),
]
```

SPM clones the repository and compiles automatically from the versioned tag.

### Universal Binary (macOS)

Build a universal binary locally:

```bash
git clone https://github.com/vjr2005/SwiftGenerator.git
cd SwiftGenerator
make release
```

This builds for `arm64` and `x86_64`, creates a universal binary via `lipo`, and packages it as an artifact bundle. Copy the binary to your `$PATH`:

```bash
cp build/swift-generator.artifactbundle/swift-generator-macos/swift-generator /usr/local/bin/
```

### Quick Build from Sources

For local development:

```bash
swift build -c release
```

The binary is generated at `.build/release/swift-generator`.

---

## Development

### Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [mise](https://mise.jdx.dev) | Latest | Tool version manager |
| [Tuist](https://tuist.io) | 4.x | Xcode project generation (installed via mise) |
| Swift | 6.0+ | Compiler |
| Xcode | 16+ | IDE (optional, for Tuist-generated project) |

### Project Setup

```bash
# First-time setup (installs mise tools, generates Xcode project)
make bootstrap

# Or if mise/tuist are already installed:
make setup
```

### Available Commands

All commands are available via `make` or `mise`:

| Command | Make | Mise | Description |
|---------|------|------|-------------|
| Bootstrap | `make bootstrap` | — | First-time setup (installs tools, generates project) |
| Setup | `make setup` | `mise run setup` | Install dependencies and generate Xcode project |
| Generate | `make generate` | `mise run generate` | Regenerate Xcode project |
| Edit | `make edit` | `mise run edit` | Open Tuist manifests for editing |
| Build | `make build` | `mise run build` | Build with Tuist |
| Test | `make test` | `mise run test` | Run tests with Tuist |
| Clean | `make clean` | `mise run clean` | Clean build artifacts |
| Graph | `make graph` | `mise run graph` | Generate dependency graph |
| SPM Build | `make spm-build` | `mise run spm-build` | Build with Swift Package Manager |
| SPM Test | `make spm-test` | `mise run spm-test` | Run tests with Swift Package Manager |
| Release | `make release` | — | Build universal macOS binary for distribution |
| Help | `make help` | — | Show all available commands |

---

## Generators

### Mock Generator

Generates mock implementations from protocols annotated with `// @mock`. Each mock includes call tracking, argument recording, configurable return values, side-effect closures, and a `reset()` method.

#### Quick Start

**1. Annotate your protocols:**

```swift
// @mock
protocol CharacterListTrackerContract {
    func trackScreenViewed()
    func trackCharacterSelected(identifier: Int)
}
```

**2. Run the generator:**

```bash
swift-generator \
    --sources Sources/ChallengeCharacter \
    --internal-output Tests/ChallengeCharacterTests/Mocks \
    --module ChallengeCharacter
```

**3. Use the generated mock in tests:**

```swift
func testTrackScreenViewed() {
    let mock = CharacterListTrackerMock()

    mock.trackScreenViewed()

    #expect(mock.trackScreenViewedCallsCount == 1)
}
```

#### Annotation Format

The generator looks for the exact line comment `// @mock` in the leading trivia of a protocol declaration:

```swift
// @mock
protocol FooContract {
    func bar()
}
```

**Rules:**

- Must be a line comment (`//`), not a block comment (`/* */`).
- Must appear directly before the protocol declaration (or before its modifiers/doc comments).
- Protocols without `// @mock` are ignored entirely.
- Multiple protocols in the same file can be annotated independently.

```swift
protocol IgnoredContract {
    func ignored()
}

// @mock
protocol AnnotatedContract {
    func annotated()
}
```

Only `AnnotatedContract` will produce a mock.

#### Mock Patterns

The generator infers the concurrency pattern from protocol traits and selects the appropriate mock type:

| Protocol trait             | Pattern       | Generated type                                   |
|----------------------------|---------------|--------------------------------------------------|
| Default                    | MainActor     | `final class`                                    |
| Inherits `Sendable`        | MainActor     | `final class … @unchecked Sendable`              |
| `nonisolated` modifier     | Nonisolated   | `nonisolated final class … @unchecked Sendable`  |
| Inherits `Actor`           | Actor         | `actor` (with setter methods)                    |

##### MainActor Pattern

**Triggers when:** The protocol has no `nonisolated` modifier and does not inherit from `Actor`.

```swift
// Input:
// @mock
protocol CharacterListTrackerContract {
    func trackScreenViewed()
    func trackCharacterSelected(identifier: Int)
}

// Output:
final class CharacterListTrackerMock: CharacterListTrackerContract {
    private(set) var trackScreenViewedCallsCount = 0
    var trackScreenViewedClosure: (() -> Void)?

    private(set) var trackCharacterSelectedCallsCount = 0
    private(set) var trackCharacterSelectedReceivedIdentifier: Int?
    private(set) var trackCharacterSelectedReceivedInvocations: [Int] = []
    var trackCharacterSelectedClosure: (() -> Void)?

    func trackScreenViewed() {
        trackScreenViewedCallsCount += 1
        trackScreenViewedClosure?()
    }

    func trackCharacterSelected(identifier: Int) {
        trackCharacterSelectedCallsCount += 1
        trackCharacterSelectedReceivedIdentifier = identifier
        trackCharacterSelectedReceivedInvocations.append(identifier)
        trackCharacterSelectedClosure?()
    }

    // MARK: - Reset

    func reset() {
        trackScreenViewedCallsCount = 0
        trackCharacterSelectedCallsCount = 0
        trackCharacterSelectedReceivedIdentifier = nil
        trackCharacterSelectedReceivedInvocations = []
    }
}
```

When the protocol inherits `Sendable`, the class also conforms to `@unchecked Sendable`:

```swift
// @mock
protocol GetCharacterUseCaseContract: Sendable {
    func execute(identifier: Int) async throws(CharacterError) -> Character
}

// Output:
final class GetCharacterUseCaseMock: GetCharacterUseCaseContract, @unchecked Sendable {
    // ...
}
```

##### Nonisolated Pattern

**Triggers when:** The protocol has the `nonisolated` modifier.

Methods annotated with `@concurrent` in the protocol preserve that attribute in the mock.

```swift
// Input:
// @mock
nonisolated protocol CharacterRemoteDataSourceContract: Sendable {
    @concurrent func fetch(identifier: Int) async throws -> CharacterDTO
}

// Output:
nonisolated final class CharacterRemoteDataSourceMock: CharacterRemoteDataSourceContract, @unchecked Sendable {
    private(set) var fetchCallsCount = 0
    private(set) var fetchReceivedIdentifier: Int?
    private(set) var fetchReceivedInvocations: [Int] = []
    var fetchReturnValue: Result<CharacterDTO, any Error>?
    var fetchClosure: (() async -> Void)?

    @concurrent func fetch(identifier: Int) async throws -> CharacterDTO {
        fetchCallsCount += 1
        fetchReceivedIdentifier = identifier
        fetchReceivedInvocations.append(identifier)
        await fetchClosure?()
        guard let returnValue = fetchReturnValue else {
            preconditionFailure("fetchReturnValue not configured")
        }
        return try returnValue.get()
    }

    // MARK: - Reset

    func reset() {
        fetchCallsCount = 0
        fetchReceivedIdentifier = nil
        fetchReceivedInvocations = []
    }
}
```

##### Actor Pattern

**Triggers when:** The protocol inherits from `Actor`.

Since actor properties cannot be set from outside the isolation domain, the mock includes setter methods for configuring return values and closures.

```swift
// Input:
// @mock
protocol CharacterLocalDataSourceContract: Actor {
    func getValue(identifier: Int) -> String?
    func saveValue(_ value: String)
}

// Output:
actor CharacterLocalDataSourceMock: CharacterLocalDataSourceContract {
    private(set) var getValueCallsCount = 0
    private(set) var getValueReceivedIdentifier: Int?
    private(set) var getValueReceivedInvocations: [Int] = []
    var getValueReturnValue: String?
    var getValueClosure: (() -> Void)?

    private(set) var saveValueCallsCount = 0
    private(set) var saveValueReceivedValue: String?
    private(set) var saveValueReceivedInvocations: [String] = []
    var saveValueClosure: (() -> Void)?

    func setGetValueReturnValue(_ value: String?) {
        getValueReturnValue = value
    }

    func setGetValueClosure(_ closure: (() -> Void)?) {
        getValueClosure = closure
    }

    func setSaveValueClosure(_ closure: (() -> Void)?) {
        saveValueClosure = closure
    }

    func getValue(identifier: Int) -> String? {
        getValueCallsCount += 1
        getValueReceivedIdentifier = identifier
        getValueReceivedInvocations.append(identifier)
        getValueClosure?()
        return getValueReturnValue
    }

    func saveValue(_ value: String) {
        saveValueCallsCount += 1
        saveValueReceivedValue = value
        saveValueReceivedInvocations.append(value)
        saveValueClosure?()
    }

    // MARK: - Reset

    func reset() {
        getValueCallsCount = 0
        getValueReceivedIdentifier = nil
        getValueReceivedInvocations = []
        saveValueCallsCount = 0
        saveValueReceivedValue = nil
        saveValueReceivedInvocations = []
    }
}
```

#### Generated Mock Structure

Every generated mock follows the same structure for each method in the protocol.

##### Tracking Properties

| Property | Type | Description |
|----------|------|-------------|
| `<method>CallsCount` | `Int` | Number of times the method was called. |
| `<method>Received<Param>` | `<ParamType>?` | Last received argument (single-parameter methods). |
| `<method>ReceivedArguments` | `(<params>)?` | Last received arguments as a tuple (multi-parameter methods). |
| `<method>ReceivedInvocations` | `[<ParamType>]` or `[(<params>)]` | History of all received arguments. |

##### Return Value Configuration

The type of the return value property depends on whether the method throws:

| Method signature | Property | Type |
|-----------------|----------|------|
| `func foo() -> String` | `fooReturnValue` | `String?` |
| `func foo() throws -> String` | `fooReturnValue` | `Result<String, any Error>?` |
| `func foo() throws(FooError) -> String` | `fooReturnValue` | `Result<String, FooError>?` |
| `func foo() throws` (void) | `fooThrowableError` | `(any Error)?` |
| `func foo() throws(FooError)` (void) | `fooThrowableError` | `(FooError)?` |
| `func foo<T: Decodable>() throws -> T` | `fooReturnValue` | `Any?` |

**Usage in tests:**

```swift
// Non-throwing:
mock.fetchReturnValue = "result"

// Throwing with Result (success):
mock.executeReturnValue = .success(myCharacter)

// Throwing with Result (failure):
mock.executeReturnValue = .failure(CharacterError.notFound)

// Void throwing:
mock.saveThrowableError = SaveError.diskFull
```

##### Side-Effect Closures

Every method gets a closure property invoked during the method call, after argument recording and before the return:

```swift
var fetchClosure: (() async -> Void)?  // async methods
var saveClosure: (() -> Void)?         // sync methods
```

Useful for triggering side effects in tests:

```swift
mock.fetchClosure = {
    // Simulate a delay, update state, etc.
}
```

##### Reset

Every mock includes a `reset()` method that clears all tracking state (call counts, received arguments, invocation history) but **preserves** configuration (return values, closures):

```swift
mock.fetchReturnValue = .success(myData)
mock.fetch(identifier: 1)
mock.fetch(identifier: 2)

#expect(mock.fetchCallsCount == 2)

mock.reset()

#expect(mock.fetchCallsCount == 0)
#expect(mock.fetchReceivedInvocations.isEmpty)
// fetchReturnValue is still .success(myData)
```

#### Advanced Mock Features

##### Public vs Internal Mocks

Protocols with `public` access level generate mocks with `public` modifiers and a plain `import`:

```swift
// Input:
// @mock
public protocol NavigatorContract {
    func navigate(to destination: String)
}

// Output:
// import ChallengeCore  (not @testable)
public final class NavigatorMock: NavigatorContract {
    public private(set) var navigateCallsCount = 0
    public private(set) var navigateReceivedDestination: String?
    public private(set) var navigateReceivedInvocations: [String] = []
    public var navigateClosure: (() -> Void)?

    public init() {}

    public func navigate(to destination: String) { ... }

    public func reset() { ... }
}
```

Use `--public-output` to write these to a separate directory.

##### Generic Methods

Generic methods use `Any?` for the return value property and cast at the call site:

```swift
// Input:
// @mock
nonisolated protocol APIClientContract: Sendable {
    @concurrent func execute<T: Decodable>(_ operation: String) async throws -> T
}

// Output (property):
var executeReturnValue: Any?

// Output (method body):
guard let returnValue = executeReturnValue as? T else {
    preconditionFailure("executeReturnValue not configured or type mismatch")
}
return returnValue
```

**Usage in tests:**

```swift
let expected = MyResponse(id: 1, name: "test")
mock.executeReturnValue = expected

let result: MyResponse = try await mock.execute("query")
#expect(result == expected)
```

##### Source Imports

The generator captures `import` statements from the source file and replicates them in the generated mock file:

```swift
// Source file:
import Foundation
import ChallengeCore

// @mock
protocol FooContract {
    func process(data: ChallengeCore.DataModel) -> String
}

// Generated file:
import Foundation
import ChallengeCore

@testable import ChallengeCharacter
```

The module import and `import Foundation` are never duplicated.

##### Protocol Properties

Protocols with properties generate stored properties in the mock. Non-optional properties require a memberwise initializer:

```swift
// Input:
// @mock
protocol FilterDelegate: AnyObject, Sendable {
    var currentFilter: String { get }
    var lastUpdate: Date? { get set }
}

// Output:
final class FilterMock: FilterDelegate, @unchecked Sendable {
    var currentFilter: String
    var lastUpdate: Date?

    init(currentFilter: String) {
        self.currentFilter = currentFilter
    }
    // ...
}
```

##### Mock Naming

The generator strips known suffixes from the protocol name before appending `Mock`:

| Protocol name | Mock name |
|--------------|-----------|
| `CharacterListTrackerContract` | `CharacterListTrackerMock` |
| `NavigationDelegate` | `NavigationMock` |
| `DataStore` | `DataStoreMock` |

Default suffixes stripped: `Contract`, `Delegate`. This is configurable when using `SwiftGeneratorKit` as a library.

---

## CLI Reference

```
USAGE: swift-generator --sources <sources> ... --internal-output <path> [--public-output <path>] --module <name>
```

### Options

| Option | Required | Description |
|--------|----------|-------------|
| `--sources <path>` | Yes | Source directories to scan. Can be repeated for multiple directories. |
| `--internal-output <path>` | Yes | Output directory for internal generated code (uses `@testable import`). Created automatically. |
| `--public-output <path>` | No | Output directory for public generated code (uses plain `import`). |
| `--module <name>` | Yes | Module name for import statements in generated files. |

### Examples

```bash
# Single source directory
swift-generator \
    --sources Sources/ChallengeCharacter \
    --internal-output Tests/ChallengeCharacterTests/Mocks \
    --module ChallengeCharacter

# Multiple source directories with separate public output
swift-generator \
    --sources Sources/ChallengeCharacter \
    --sources Sources/ChallengeCore \
    --internal-output Tests/Mocks/Internal \
    --public-output Tests/Mocks/Public \
    --module ChallengeCharacter
```

---

## Integration

### SPM Command Plugin (recommended)

The easiest way to integrate SwiftGenerator into your project. Add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/vjr2005/SwiftGenerator", from: "1.0.0"),
]
```

Then run the plugin:

```bash
# Auto-detects sources, module, and output for all targets:
swift package plugin --allow-writing-to-package-directory generate-mocks

# Specify a target:
swift package plugin --allow-writing-to-package-directory generate-mocks --target MyFeature

# Full manual control:
swift package plugin --allow-writing-to-package-directory generate-mocks \
    --target MyFeature \
    --module MyFeature \
    --internal-output Tests/MyFeatureTests/Mocks \
    --public-output Tests/MyFeatureTests/PublicMocks
```

**Auto-detection defaults:**

| Argument | Auto-detected value | Override flag |
|----------|-------------------|---------------|
| `--sources` | Target source directory | `--sources <path>` |
| `--module` | Target name | `--module <name>` |
| `--internal-output` | `Tests/<TargetName>Tests/Mocks/` | `--internal-output <path>` |
| `--public-output` | Not auto-detected | `--public-output <path>` |
| `--target` | All non-test Swift source targets | `--target <name>` |

**Binary distribution:** When using a released version, the plugin downloads a pre-built universal binary — no need to compile SwiftSyntax locally. This makes the first run fast.

**Xcode:** The plugin is also available from Xcode: right-click the package in the navigator and select "generate-mocks".

### Build Script

```bash
#!/bin/bash
set -euo pipefail

GENERATOR=".build/release/swift-generator"

swift build -c release --product swift-generator 2>/dev/null

$GENERATOR \
    --sources Sources/ChallengeCharacter \
    --internal-output Tests/ChallengeCharacterTests/Generated/Mocks \
    --module ChallengeCharacter
```

### Xcode Build Phase

Add a **Run Script** build phase that runs before the test target compiles:

```bash
"${BUILD_DIR}/../../SourcePackages/artifacts/swift-generator" \
    --sources "${SRCROOT}/Sources/ChallengeCharacter" \
    --internal-output "${SRCROOT}/Tests/ChallengeCharacterTests/Mocks" \
    --module ChallengeCharacter
```

---

## Architecture

```
SwiftGenerator/
  Package.swift                           # SPM package definition
  Project.swift                           # Tuist project definition
  Tuist.swift                             # Tuist configuration
  mise.toml                               # Tool management (Tuist 4)
  Makefile                                # Unified command interface
  scripts/
    bootstrap.sh                          # First-time setup script
    build-release.sh                      # Artifact bundle build script
  Plugins/
    GenerateMocks/
      GenerateMocksPlugin.swift           # SPM Command Plugin entry point
      GenerateMocksPluginError.swift      # Plugin error types
      PackagePlugin+Helpers.swift         # Subprocess execution helper
  Sources/
    CLI/
      CLI.swift                           # Command-line entry point (ArgumentParser)
    SwiftGeneratorKit/
      Models/
        MockPattern.swift                 # mainActor | nonisolated | actor
        ProtocolMetadata.swift            # Protocol, Method, Parameter, Property metadata
      Parser/
        ProtocolParser.swift              # SwiftSyntax visitor — extracts annotated protocols
      Generator/
        CodeBuilder.swift                 # Indented source code builder (shared utility)
        MockEmitter.swift                 # MockEmitter protocol + shared emission helpers
        ClassMockEmitter.swift            # Emitter for mainActor and nonisolated patterns
        ActorMockEmitter.swift            # Emitter for actor pattern
        SwiftGenerator.swift              # Mock generator orchestrator
      FileSystem/
        FileSystem.swift                  # FileSystem protocol + DefaultFileSystem
  Tests/
    SwiftGeneratorKitTests/
      ProtocolParserTests.swift           # Parser tests (Swift Testing)
      SwiftGeneratorTests.swift           # Generator tests (Swift Testing)
```

### Design Principles

The architecture is built for extensibility:

- **Single Responsibility**: The parser extracts metadata, generators produce output, the CLI orchestrates I/O. Each component does one thing.
- **Open/Closed**: New mock patterns are added by implementing `MockEmitter` and registering the emitter. New generators can be added alongside `SwiftGenerator` by consuming the same `ProtocolMetadata` (or new metadata types from new parsers).
- **Dependency Inversion**: The CLI depends on the `FileSystem` protocol, not `FileManager`. The generator depends on `MockEmitter`, not concrete emitters. This makes every layer testable in isolation.
- **No file I/O in domain logic**: `ProtocolParser` and `SwiftGenerator` are pure transformations (string in, data/string out). All file I/O lives at the CLI boundary via `FileSystem`.

### Adding New Generators

The project is structured so that new generators can be added without modifying existing code:

1. **Define a new annotation** (e.g., `// @equatable`, `// @codable`) or reuse `// @mock`.
2. **Create a new metadata model** if the existing `ProtocolMetadata` doesn't cover the input needs, or reuse/extend it.
3. **Implement the generator** as a new type that takes metadata and produces source code via `CodeBuilder`.
4. **Register it in the CLI** by adding the corresponding options and wiring.

The shared infrastructure (`ProtocolParser`, `CodeBuilder`, `FileSystem`, `MockEmission` helpers) is available for reuse by any generator.

### Using SwiftGeneratorKit as a Library

The core logic is available as a library target for programmatic use:

```swift
import SwiftGeneratorKit

let parser = ProtocolParser()
let generator = SwiftGenerator(moduleName: "MyModule")

let protocols = parser.parse(source: swiftSource, filePath: "/path/to/File.swift")
for proto in protocols {
    let code = generator.generate(from: proto)
    let name = generator.mockName(for: proto)
    // Write `code` to `\(name).swift`
}
```

Custom mock emitters can be injected:

```swift
let generator = SwiftGenerator(
    moduleName: "MyModule",
    mockNameSuffixes: ["Contract", "Delegate", "Protocol"],
    emitters: [
        .mainActor: MyCustomClassEmitter(),
        .nonisolated: MyCustomClassEmitter(),
        .actor: MyCustomActorEmitter(),
    ]
)
```

---

## Testing

```bash
# With SPM
make spm-test

# With Tuist
make test
```

The test suite uses the [Swift Testing](https://developer.apple.com/documentation/testing) framework and covers:

- **Parser tests**: Annotation detection, access level inference, pattern inference, method/property/parameter parsing, generic methods, multiple protocols per file.
- **Generator tests**: Mock naming, header and imports, all three mock patterns, tracking properties, return value types (`Result`, `ThrowableError`, `Any?`), reset behavior, public access modifiers, source imports.

---

## Roadmap

SwiftGenerator is designed as a platform for multiple code generators. The Mock Generator is the first. Potential future generators include:

| Generator | Annotation | Description |
|-----------|------------|-------------|
| **Mock** (shipped) | `// @mock` | Generates mock implementations from protocols. |
| Spy | `// @spy` | Like mocks but forwarding calls to a real implementation while recording. |
| Stub | `// @stub` | Lightweight stubs with minimal tracking overhead. |
| Builder | `// @builder` | Generates builder-pattern types for structs. |
| Equatable | `// @equatable` | Auto-generates `Equatable` conformance for complex types. |
| Fixture | `// @fixture` | Generates factory methods with sensible defaults for test data. |

These are ideas, not commitments. Contributions and suggestions for new generators are welcome.

---

## License

This project is licensed under the [MIT License](LICENSE).
