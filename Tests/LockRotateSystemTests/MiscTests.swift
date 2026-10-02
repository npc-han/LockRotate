import Foundation
import Testing
@testable import LockRotateSystem

struct LockTextReaderTests {
    @Test func defaultReaderDoesNotCrash() {
        let value: String? = LockTextReader().current()
        _ = value // this machine may or may not have the key
    }

    @Test func injectedStringIsReturned() {
        #expect(LockTextReader(read: { "hello" }).current() == "hello")
    }

    @Test func missingOrNonStringValueIsNil() {
        #expect(LockTextReader(read: { nil }).current() == nil)
        #expect(LockTextReader(read: { 42 }).current() == nil)
    }
}

struct SystemErrorTests {
    @Test func everyCaseHasADescription() {
        let all: [SystemError] = [
            .helperNotInstalled, .rejected("too long"), .failed(3, "boom"), .timedOut,
            .userCancelled, .invalidUsername, .resourceMissing("x.sh"),
        ]
        for error in all {
            let text = error.errorDescription ?? ""
            #expect(!text.isEmpty)
            #expect(!text.hasPrefix("system.error."), "missing localization for \(error)")
        }
    }

    @Test func detailsAreInterpolated() {
        #expect(SystemError.rejected("too long").errorDescription?.contains("too long") == true)
        let failed = SystemError.failed(3, "boom").errorDescription
        #expect(failed?.contains("3") == true && failed?.contains("boom") == true)
        #expect(SystemError.resourceMissing("x.sh").errorDescription?.contains("x.sh") == true)
    }
}

struct HelperPathsTests {
    @Test func constants() {
        #expect(HelperPaths.helper == "/Library/PrivilegedHelperTools/lockrotate/set-lock-text")
        #expect(HelperPaths.sudoers == "/etc/sudoers.d/lockrotate")
    }
}
