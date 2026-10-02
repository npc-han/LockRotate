import Foundation
import Testing
@testable import LockRotateSystem

struct HelperCommandsTests {
    let script = Data("#!/bin/sh\necho 'it''s' \"quoted\" \\ back\n".utf8)
    let helper = Data("#!/bin/sh\nexit 0\n".utf8)

    /// Undoes the AppleScript string escaping, i.e. what `do shell script` receives.
    func unwrap(_ appleScript: String) throws -> String {
        let prefix = "do shell script \"", suffix = "\" with administrator privileges"
        try #require(appleScript.hasPrefix(prefix) && appleScript.hasSuffix(suffix))
        let body = String(appleScript.dropFirst(prefix.count).dropLast(suffix.count))
        var out = "", escaping = false
        for ch in body {
            if escaping { out.append(ch); escaping = false }
            else if ch == "\\" { escaping = true }
            else {
                try #require(ch != "\"", "unescaped double quote inside AppleScript string")
                out.append(ch)
            }
        }
        try #require(!escaping)
        return out
    }

    func syntaxIsValid(_ command: String) throws -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-n", "-c", command] // -n parses only
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    @Test func installCommandRoundTrips() throws {
        let command = try HelperCommands.install(userName: "alice", installScript: script, helper: helper)
        let parts = command.components(separatedBy: " | ")
        #expect(parts.count == 3)
        #expect(parts[1] == "/usr/bin/base64 -D")
        #expect(parts[0].hasPrefix("printf %s '") && parts[0].hasSuffix("'"))
        let scriptB64 = String(parts[0].dropFirst("printf %s '".count).dropLast())
        #expect(Data(base64Encoded: scriptB64) == script)
        let tail = "/bin/sh -s -- 'alice' '\(helper.base64EncodedString())'"
        #expect(parts[2] == tail)
    }

    @Test func installCommandSurvivesAppleScriptEscaping() throws {
        let command = try HelperCommands.install(userName: "a.b-c_1", installScript: script, helper: helper)
        let script = HelperCommands.appleScript(for: command)
        #expect(!script.contains("\n"))
        #expect(try unwrap(script) == command)
        #expect(try syntaxIsValid(unwrap(script)))
    }

    @Test func realResourcesBuildValidCommandsThatRoundTrip() throws {
        let installer = try sourceResource("install-helper.sh")
        let realHelper = try sourceResource("set-lock-text")
        let command = try HelperCommands.install(userName: NSUserName() == "root" ? "alice" : NSUserName(),
                                                 installScript: installer, helper: realHelper)
        #expect(try syntaxIsValid(command))
        let b64s = command.split(separator: "'").map(String.init).filter { Data(base64Encoded: $0) != nil && $0.count > 40 }
        #expect(b64s.count == 2)
        #expect(Data(base64Encoded: b64s[0]) == installer)
        #expect(Data(base64Encoded: b64s[1]) == realHelper)
    }

    @Test(arguments: ["x'; rm -rf / #", "has space", "quo\"te", "quo'te", "root", "", "9lives", "a/b", "a;b", "$(id)", "ñ"])
    func rejectsUnsafeUsernames(name: String) {
        #expect(throws: SystemError.invalidUsername) {
            try HelperCommands.install(userName: name, installScript: script, helper: helper)
        }
    }

    @Test(arguments: ["alice", "_www", "Bob.Smith", "a-b", "user_1", "A"])
    func acceptsOrdinaryUsernames(name: String) throws {
        let command = try HelperCommands.install(userName: name, installScript: script, helper: helper)
        #expect(command.contains("-- '\(name)' '"))
    }

    @Test func uninstallCommandPlacesKeepTextAfterDoubleDash() throws {
        let plain = try HelperCommands.uninstall(uninstallScript: script, keepText: false)
        let keep = try HelperCommands.uninstall(uninstallScript: script, keepText: true)
        #expect(plain.hasSuffix(" | /bin/sh -s --"))
        #expect(keep.hasSuffix(" | /bin/sh -s -- '--keep-text'"))
        #expect(try syntaxIsValid(plain) && syntaxIsValid(keep))
        let b64 = String(keep.dropFirst("printf %s '".count).prefix { $0 != "'" })
        #expect(Data(base64Encoded: b64) == script)
    }

    @Test func shellQuoteHandlesQuotes() throws {
        #expect(HelperCommands.shellQuote("a'b") == "'a'\\''b'")
        #expect(HelperCommands.shellQuote("") == "''")
        // Prove with a real parse that the result is a single word.
        let hostile = "x'; rm -rf / #\"\\$(id)`"
        #expect(try syntaxIsValid("printf %s \(HelperCommands.shellQuote(hostile))"))
    }

    @Test func appleScriptEscapesBackslashesAndQuotes() throws {
        let input = #"echo "a\b" 'c'"#
        let out = HelperCommands.appleScript(for: input)
        #expect(out == #"do shell script "echo \"a\\b\" 'c'" with administrator privileges"#)
        #expect(try unwrap(out) == input)
    }

    @Test func appleScriptEscapesBackslashBeforeQuote() throws {
        // A trailing backslash must not be able to swallow the closing quote.
        let out = HelperCommands.appleScript(for: "x\\")
        #expect(out == #"do shell script "x\\" with administrator privileges"#)
        #expect(try unwrap(out) == "x\\")
    }
}
