import Foundation

public enum SystemError: Error, Equatable, LocalizedError {
    case helperNotInstalled
    case rejected(String)
    case failed(Int32, String)
    case timedOut
    case userCancelled
    case invalidUsername
    case resourceMissing(String)

    public var errorDescription: String? {
        switch self {
        case .helperNotInstalled:
            String(localized: "system.error.helperNotInstalled", bundle: .module)
        case .rejected(let detail):
            String(format: String(localized: "system.error.rejected", bundle: .module), detail)
        case .failed(let code, let detail):
            String(format: String(localized: "system.error.failed", bundle: .module), Int(code), detail)
        case .timedOut:
            String(localized: "system.error.timedOut", bundle: .module)
        case .userCancelled:
            String(localized: "system.error.userCancelled", bundle: .module)
        case .invalidUsername:
            String(localized: "system.error.invalidUsername", bundle: .module)
        case .resourceMissing(let name):
            String(format: String(localized: "system.error.resourceMissing", bundle: .module), name)
        }
    }
}
