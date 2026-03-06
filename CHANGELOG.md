# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial mock code generator with support for `@MainActor`, `nonisolated`, and `actor` patterns
- Swift 6.0 strict concurrency support with typed throws
- Extensible architecture via `MockEmitter` protocol (Strategy pattern)
- `FileSystem` protocol for testable I/O abstraction
- Tuist project generation with mise tool management
- Universal binary release build script (arm64 + x86_64)
- Comprehensive public API documentation
