import Foundation
import PackagePlugin

extension Path {
	func exec(arguments: [String]) throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: self.string)
		process.arguments = arguments
		try process.run()
		process.waitUntilExit()
		guard process.terminationReason == .exit, process.terminationStatus == 0 else {
			throw GenerateMocksPluginError.subprocessFailedNonZeroExit(process.terminationStatus)
		}
	}
}
