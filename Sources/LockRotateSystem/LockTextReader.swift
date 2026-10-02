import Foundation

public struct LockTextReader: Sendable {
    private let read: @Sendable () -> Any?

    /// The default reads the system-wide loginwindow preference without elevated rights.
    public init() {
        self.init {
            CFPreferencesCopyValue(
                "LoginwindowText" as CFString,
                "com.apple.loginwindow" as CFString,
                kCFPreferencesAnyUser,
                kCFPreferencesAnyHost
            )
        }
    }

    /// Injectable source, so tests do not depend on this machine's preferences.
    public init(read: @escaping @Sendable () -> Any?) {
        self.read = read
    }

    public func current() -> String? {
        read() as? String
    }
}
