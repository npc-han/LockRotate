import Foundation
import LockRotateCore

enum AppEnvironment {
    static let dataDirectoryVariable = "LOCKROTATE_DATA_DIR"

    /// `LOCKROTATE_DATA_DIR` overrides the default so development runs never touch real data.
    static func dataDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment[dataDirectoryVariable], !override.isEmpty {
            let path = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return LockRotateDirectory.defaultURL()
    }
}
