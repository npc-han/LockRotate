import Foundation

/// Pure builders for the admin-privileged install/uninstall commands. Nothing here runs anything.
///
/// Root must never execute or copy a file from a user-writable location, so the scripts and
/// the helper travel inside the command string itself (base64) and are decoded in memory.
enum HelperCommands {
    static let installScriptName = "install-helper.sh"
    static let uninstallScriptName = "uninstall-helper.sh"
    static let helperName = "set-lock-text"

    /// Same whitelist as install-helper.sh, checked here too so a bad name never reaches root.
    static func isValidUsername(_ name: String) -> Bool {
        guard name != "root", let first = name.unicodeScalars.first else { return false }
        func isLetter(_ s: Unicode.Scalar) -> Bool {
            ("A"..."Z").contains(s) || ("a"..."z").contains(s)
        }
        guard isLetter(first) || first == "_" else { return false }
        return name.unicodeScalars.allSatisfy {
            isLetter($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "." || $0 == "-"
        }
    }

    static func install(userName: String, installScript: Data, helper: Data) throws -> String {
        guard isValidUsername(userName) else { throw SystemError.invalidUsername }
        return pipeToShell(script: installScript, arguments: [userName, helper.base64EncodedString()])
    }

    static func uninstall(uninstallScript: Data, keepText: Bool) throws -> String {
        pipeToShell(script: uninstallScript, arguments: keepText ? ["--keep-text"] : [])
    }

    private static func pipeToShell(script: Data, arguments: [String]) -> String {
        // "--" stays literal so a leading "--keep-text" is a positional argument, not a shell option.
        let args = (["--"] + arguments.map(shellQuote)).joined(separator: " ")
        return "printf %s \(shellQuote(script.base64EncodedString())) | /usr/bin/base64 -D | /bin/sh -s \(args)"
    }

    /// POSIX single-quote escaping: the only character special inside '...' is the quote itself.
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScript(for shellCommand: String) -> String {
        // Backslash first, otherwise the backslashes added for quotes would be doubled.
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }
}
