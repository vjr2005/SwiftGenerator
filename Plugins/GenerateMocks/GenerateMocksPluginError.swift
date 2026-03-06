import Foundation

enum GenerateMocksPluginError: LocalizedError {
	case targetNotFound(String)
	case subprocessFailedNonZeroExit(Int32)

	var errorDescription: String? {
		switch self {
		case .targetNotFound(let name):
			"Target '\(name)' not found in the package."
		case .subprocessFailedNonZeroExit(let code):
			"swift-generator exited with status \(code)."
		}
	}
}
