import Foundation
import Testing
@testable import LockRotateSystem

struct SetLockTextTests {
    @Test func successSendsTextOnStdinWithoutArguments() async throws {
        let runner = FakeRunner(CommandResult(exitCode: 0))
        try await makeManager(runner).setLockText("héllo\nworld 你好")
        let call = try #require(runner.calls.first)
        #expect(runner.calls.count == 1)
        #expect(call.executable == "/usr/bin/sudo")
        #expect(call.arguments == ["-n", "/Library/PrivilegedHelperTools/lockrotate/set-lock-text"])
        #expect(call.stdin == Data("héllo\nworld 你好".utf8))
    }

    @Test func textNeverAppearsInArguments() async throws {
        let runner = FakeRunner(CommandResult(exitCode: 0))
        try await makeManager(runner).setLockText("secret-ish text")
        #expect(!runner.calls[0].arguments.contains { $0.contains("secret") })
    }

    @Test func exit65IsRejectedWithTrimmedStderr() async {
        let runner = FakeRunner(CommandResult(exitCode: 65, stderr: "set-lock-text: text too long\n"))
        await #expect(throws: SystemError.rejected("set-lock-text: text too long")) {
            try await makeManager(runner).setLockText("x")
        }
    }

    @Test(arguments: ["sudo: a password is required", "sudo: set-lock-text: command not found"])
    func sudoWithoutRuleMeansNotInstalled(stderr: String) async {
        let runner = FakeRunner(CommandResult(exitCode: 1, stderr: stderr))
        await #expect(throws: SystemError.helperNotInstalled) {
            try await makeManager(runner).setLockText("x")
        }
    }

    @Test func exit1WithOtherStderrIsFailed() async {
        let runner = FakeRunner(CommandResult(exitCode: 1, stderr: "boom"))
        await #expect(throws: SystemError.failed(1, "boom")) {
            try await makeManager(runner).setLockText("x")
        }
    }

    @Test func otherExitCodesAreFailed() async {
        let runner = FakeRunner(CommandResult(exitCode: 77, stderr: "must run as root"))
        await #expect(throws: SystemError.failed(77, "must run as root")) {
            try await makeManager(runner).setLockText("x")
        }
    }

    @Test func passwordWordsWithOtherExitCodeAreNotNotInstalled() async {
        let runner = FakeRunner(CommandResult(exitCode: 2, stderr: "a password is required"))
        await #expect(throws: SystemError.failed(2, "a password is required")) {
            try await makeManager(runner).setLockText("x")
        }
    }

    @Test func runnerErrorsPropagate() async {
        let runner = FakeRunner(throwing: .timedOut)
        await #expect(throws: SystemError.timedOut) {
            try await makeManager(runner).setLockText("x")
        }
    }
}

struct IsInstalledTests {
    @Test func installedWhenFileExistsAndSudoListSucceeds() async {
        let runner = FakeRunner(CommandResult(exitCode: 0))
        let manager = makeManager(runner)
        #expect(await manager.isInstalled())
        #expect(await manager.status() == .installed)
        #expect(runner.calls[0].executable == "/usr/bin/sudo")
        #expect(runner.calls[0].arguments == ["-n", "-l", "/Library/PrivilegedHelperTools/lockrotate/set-lock-text"])
    }

    @Test func notInstalledWhenFileMissingAndSudoIsNotAsked() async {
        let runner = FakeRunner(CommandResult(exitCode: 0))
        let manager = makeManager(runner, installed: false)
        #expect(await manager.isInstalled() == false)
        #expect(await manager.status() == .notInstalled)
        #expect(runner.calls.isEmpty)
    }

    @Test func notInstalledWhenSudoRuleMissing() async {
        let runner = FakeRunner(CommandResult(exitCode: 1, stderr: "sudo: a password is required"))
        #expect(await makeManager(runner).isInstalled() == false)
    }

    @Test func notInstalledWhenSudoCannotRun() async {
        let runner = FakeRunner(throwing: .timedOut)
        #expect(await makeManager(runner).isInstalled() == false)
    }
}

struct PrivilegedRunTests {
    @Test func installRunsOsascriptWithLongTimeout() async throws {
        let runner = FakeRunner(CommandResult(exitCode: 0))
        try await makeManager(runner).install()
        let call = try #require(runner.calls.first)
        #expect(call.executable == "/usr/bin/osascript")
        #expect(call.arguments.count == 2 && call.arguments[0] == "-e")
        #expect(call.arguments[1].hasPrefix("do shell script \""))
        #expect(call.arguments[1].hasSuffix("\" with administrator privileges"))
        #expect(call.timeout == 120)
        #expect(call.stdin == nil)
    }

    @Test(arguments: ["x'; rm -rf / #", "bad name", "a\"b", "root", "", "1abc", "名字", "a\nb"])
    func installRejectsBadUsernameWithoutRunningAnything(name: String) async {
        let runner = FakeRunner(CommandResult(exitCode: 0))
        await #expect(throws: SystemError.invalidUsername) {
            try await makeManager(runner, user: name).install()
        }
        #expect(runner.calls.isEmpty)
    }

    @Test(arguments: ["-128", "execution error: User canceled. (-128)"])
    func cancellationMapsToUserCancelled(stderr: String) async {
        let runner = FakeRunner(CommandResult(exitCode: 1, stderr: "0:5: " + stderr))
        await #expect(throws: SystemError.userCancelled) { try await makeManager(runner).install() }
        await #expect(throws: SystemError.userCancelled) { try await makeManager(runner).uninstall() }
    }

    @Test func otherOsascriptFailureIsFailed() async {
        let runner = FakeRunner(CommandResult(exitCode: 1, stderr: "install: failed, rolled back\n"))
        await #expect(throws: SystemError.failed(1, "install: failed, rolled back")) {
            try await makeManager(runner).install()
        }
    }

    @Test func osascriptTimeoutPropagates() async {
        let runner = FakeRunner(throwing: .timedOut)
        await #expect(throws: SystemError.timedOut) { try await makeManager(runner).uninstall() }
    }

    @Test func missingResourceIsReported() async {
        let manager = HelperManager(
            runner: FakeRunner(CommandResult(exitCode: 0)),
            userName: { "alice" },
            fileExists: { _ in true },
            loadResource: { throw SystemError.resourceMissing($0) }
        )
        await #expect(throws: SystemError.resourceMissing("install-helper.sh")) { try await manager.install() }
    }

    @Test func uninstallPassesKeepTextAfterDoubleDash() async throws {
        let runner = FakeRunner(CommandResult(exitCode: 0))
        try await makeManager(runner).uninstall(keepText: true)
        #expect(runner.calls[0].arguments[1].contains("/bin/sh -s -- '--keep-text'"))
        let plain = FakeRunner(CommandResult(exitCode: 0))
        try await makeManager(plain).uninstall()
        #expect(!plain.calls[0].arguments[1].contains("--keep-text"))
    }
}

struct BundleResourceTests {
    @Test(arguments: ["install-helper.sh", "uninstall-helper.sh", "set-lock-text"])
    func bundledScriptsMatchSourceFiles(name: String) throws {
        #expect(try HelperManager.bundledResource(name) == sourceResource(name))
    }

    @Test func missingBundledResourceThrows() {
        #expect(throws: SystemError.resourceMissing("nope.sh")) { try HelperManager.bundledResource("nope.sh") }
    }
}
