import Foundation
import Testing
import LockRotateCore
import LockRotateSystem
@testable import LockRotateApp

@MainActor
@Suite("AppModel advance")
struct AdvanceTests {
    @Test func successWritesSavesAndRefreshes() async throws {
        let h = try Harness(items: ["a", "b", "c"])
        await h.model.advance()

        #expect(h.system.writes == ["a"])
        #expect(h.model.currentText == "a")
        #expect(h.model.banner == nil)
        #expect(h.savedState.lastText == "a")
        #expect(h.savedState.position == 1)
        #expect(h.model.rotationState == h.savedState)

        await h.model.advance()
        #expect(h.system.writes == ["a", "b"])
        #expect(h.model.currentText == "b")
    }

    @Test func currentTextComesFromTheReader() async throws {
        let system = FakeSystem(text: "before")
        let h = try Harness(items: ["a"], system: system)
        #expect(h.model.currentText == "before")
        await h.model.advance()
        #expect(h.model.currentText == "a")
    }

    @Test func helperNotInstalledShowsInstallPromptAndKeepsState() async throws {
        let system = FakeSystem(text: "old")
        system.failSetText(with: .helperNotInstalled)
        let h = try Harness(items: ["a", "b"], system: system)
        let before = h.model.rotationState

        await h.model.advance()

        #expect(h.model.banner?.kind == .error)
        #expect(h.model.banner?.action == .installHelper)
        #expect(h.model.banner?.text == SystemError.helperNotInstalled.localizedDescription)
        #expect(h.model.helperStatus == .notInstalled)
        #expect(h.model.showsInstallHelper)
        #expect(h.model.rotationState == before)
        #expect(h.savedState == RotationState())
        #expect(h.model.currentText == "old")
    }

    @Test(arguments: [
        SystemError.rejected("too long"),
        SystemError.failed(1, "boom"),
        SystemError.timedOut,
    ])
    func otherFailuresShowLocalizedErrorAndDoNotAdvance(error: SystemError) async throws {
        let system = FakeSystem(text: "old")
        system.failSetText(with: error)
        let h = try Harness(items: ["a", "b"], system: system)

        await h.model.advance()

        #expect(h.model.banner?.text == error.localizedDescription)
        #expect(h.model.banner?.action == nil)
        #expect(h.model.rotationState == RotationState())
        #expect(h.savedState == RotationState())
        #expect(h.model.currentText == "old")
        #expect(!h.model.isAdvancing)

        // After the failure clears, rotation starts from the same entry again.
        system.failSetText(with: nil)
        await h.model.advance()
        #expect(h.system.writes == ["a"])
        #expect(h.model.banner == nil)
    }

    @Test func emptyListShowsFriendlyNoticeInsteadOfCrashing() async throws {
        let h = try Harness()
        await h.model.advance()
        #expect(h.model.banner?.kind == .notice)
        #expect(h.model.banner?.action == .openList)
        #expect(h.system.writes.isEmpty)
    }

    @Test func randomModeStaysInListAndSavesBag() async throws {
        let items = ["a", "b", "c", "d"]
        let h = try Harness(items: items, mode: .random)
        for _ in 0..<8 { await h.model.advance() }
        #expect(h.system.writes.count == 8)
        #expect(h.system.writes.allSatisfy(items.contains))
        #expect(h.savedState.mode == .random)
        // A full bag has no repeats.
        #expect(Set(h.system.writes.prefix(4)).count == 4)
    }

    @Test func stateLoadsOnLaunchAndContinuesWhereItStopped() async throws {
        let h = try Harness(items: ["a", "b", "c"])
        await h.model.advance()
        await h.model.advance()

        let reopened = AppModel(
            settingsStore: SettingsStore(directory: h.directory),
            stateStore: StateStore(directory: h.directory),
            helper: h.system,
            reader: h.system,
            loginItem: FakeLoginItem()
        )
        #expect(reopened.settings.items == ["a", "b", "c"])
        #expect(reopened.currentText == "b")
        await reopened.advance()
        #expect(h.system.writes == ["a", "b", "c"])
    }
}

@MainActor
@Suite("AppModel helper")
struct HelperTests {
    @Test func startReadsHelperStatus() async throws {
        let h = try Harness(system: FakeSystem(status: .notInstalled))
        #expect(h.model.helperStatus == nil)
        await h.model.start()
        #expect(h.model.helperStatus == .notInstalled)
    }

    @Test func installSucceedsAndClearsInstallBanner() async throws {
        let system = FakeSystem(status: .notInstalled)
        system.failSetText(with: .helperNotInstalled)
        let h = try Harness(items: ["a"], system: system)
        await h.model.advance()
        #expect(h.model.banner?.action == .installHelper)

        await h.model.installHelper()
        #expect(system.installCalls == 1)
        #expect(h.model.helperStatus == .installed)
        #expect(h.model.banner == nil)
        #expect(h.model.helperOperation == nil)
    }

    @Test func userCancelIsNotShownAsError() async throws {
        let system = FakeSystem(status: .notInstalled)
        system.failInstall(with: .userCancelled)
        let h = try Harness(system: system)
        await h.model.installHelper()
        #expect(h.model.banner == nil)
        #expect(h.model.helperStatus == .notInstalled)
        #expect(h.model.helperOperation == nil)
    }

    @Test func installFailureIsShown() async throws {
        let system = FakeSystem(status: .notInstalled)
        system.failInstall(with: .failed(1, "nope"))
        let h = try Harness(system: system)
        await h.model.installHelper()
        #expect(h.model.banner?.text == SystemError.failed(1, "nope").localizedDescription)
        #expect(h.model.helperOperation == nil)
    }

    @Test func uninstallUpdatesStatus() async throws {
        let system = FakeSystem(status: .installed)
        let h = try Harness(system: system)
        await h.model.start()
        #expect(h.model.isHelperInstalled)
        await h.model.uninstallHelper()
        #expect(system.uninstallCalls == 1)
        #expect(h.model.helperStatus == .notInstalled)
    }
}

@MainActor
@Suite("AppModel list editing")
struct ListEditingTests {
    @Test func addCleansAndPersists() async throws {
        let h = try Harness()
        try h.model.addItem("  hello\t\tworld \r\n\r\n\r\n\r\nline two  ")
        #expect(h.model.settings.items == ["hello  world\n\nline two"])
        #expect(h.savedSettings.items == h.model.settings.items)
    }

    @Test func emptyAndWhitespaceTextIsRejected() async throws {
        let h = try Harness(items: ["a"])
        #expect(throws: ListEditError.empty) { try h.model.addItem("") }
        #expect(throws: ListEditError.empty) { try h.model.addItem(" \n\t ") }
        #expect(throws: ListEditError.empty) { try h.model.updateItem(at: 0, to: "   ") }
        #expect(h.model.settings.items == ["a"])
    }

    @Test func duplicatesAreRejectedButSelfEditIsAllowed() async throws {
        let h = try Harness(items: ["a", "b"])
        #expect(throws: ListEditError.duplicate) { try h.model.addItem(" a ") }
        #expect(throws: ListEditError.duplicate) { try h.model.updateItem(at: 1, to: "a") }
        try h.model.updateItem(at: 1, to: " b ")
        #expect(h.model.settings.items == ["a", "b"])
    }

    @Test func updateReplacesInPlaceAndPersists() async throws {
        let h = try Harness(items: ["a", "b", "c"])
        try h.model.updateItem(at: 1, to: "x\\y")
        #expect(h.model.settings.items == ["a", "x\\y", "c"])
        #expect(h.savedSettings.items == ["a", "x\\y", "c"])
        #expect(throws: ListEditError.indexOutOfRange) { try h.model.updateItem(at: 9, to: "z") }
    }

    @Test func overlongTextIsShortenedAndReported() async throws {
        let h = try Harness()
        try h.model.addItem(String(repeating: "x", count: 900))
        #expect(h.model.settings.items[0].count == 500)
        #expect(h.model.settings.items[0].hasSuffix("…"))
        #expect(h.model.listMessage != nil)
    }

    @Test func removeDeletesAndPersists() async throws {
        let h = try Harness(items: ["a", "b", "c"])
        h.model.removeItems(["a", "c"])
        #expect(h.model.settings.items == ["b"])
        #expect(h.savedSettings.items == ["b"])
    }

    @Test func editingTheListRestartsRotation() async throws {
        let h = try Harness(items: ["a", "b", "c"])
        await h.model.advance()
        await h.model.advance()
        try h.model.addItem("d")
        await h.model.advance()
        #expect(h.system.writes == ["a", "b", "a"])
    }
}

@MainActor
@Suite("AppModel import")
struct ImportTests {
    private func data(_ s: String) -> Data { Data(s.utf8) }

    @Test func emptyListTakesImportDirectly() async throws {
        let h = try Harness()
        h.model.stageImport(data: data("one\ntwo\n# note\nthree"), filename: "list.txt")
        #expect(h.model.pendingImport == nil)
        #expect(h.model.settings.items == ["one", "two", "three"])
        #expect(h.savedSettings.items == ["one", "two", "three"])
        #expect(h.model.listMessage == AppModel.importSummary(added: 3, skippedEmpty: 0, truncated: 0, duplicates: 0))
    }

    @Test func nonEmptyListWaitsForChoice() async throws {
        let h = try Harness(items: ["old"])
        h.model.stageImport(data: data("new1\nnew2"), filename: "list.txt")
        #expect(h.model.pendingImport?.items == ["new1", "new2"])
        #expect(h.model.settings.items == ["old"])

        h.model.cancelImport()
        #expect(h.model.pendingImport == nil)
        #expect(h.model.settings.items == ["old"])
    }

    @Test func replaceDiscardsOldEntries() async throws {
        let h = try Harness(items: ["old"])
        h.model.stageImport(data: data("new1\nnew2\nnew1"), filename: "list.txt")
        let pending = try #require(h.model.pendingImport)
        h.model.applyImport(pending, mode: .replace)
        #expect(h.model.settings.items == ["new1", "new2"])
        #expect(h.model.pendingImport == nil)
        #expect(h.model.listMessage == AppModel.importSummary(added: 2, skippedEmpty: 0, truncated: 0, duplicates: 1))
    }

    @Test func appendDeduplicatesTheWholeList() async throws {
        let h = try Harness(items: ["a", "b"])
        h.model.stageImport(data: data("[\"b\", \"c\", \"c\", \"  \", \"d\"]"), filename: "list.json")
        let pending = try #require(h.model.pendingImport)
        h.model.applyImport(pending, mode: .append)

        #expect(h.model.settings.items == ["a", "b", "c", "d"])
        #expect(h.savedSettings.items == ["a", "b", "c", "d"])
        // 2 new entries; the duplicate "c" inside the file plus "b" already in the list = 2 removed; 1 blank skipped.
        #expect(h.model.listMessage == AppModel.importSummary(added: 2, skippedEmpty: 1, truncated: 0, duplicates: 2))
    }

    @Test func summaryOmitsZeroCounts() {
        let plain = AppModel.importSummary(added: 3, skippedEmpty: 0, truncated: 0, duplicates: 0)
        let full = AppModel.importSummary(added: 3, skippedEmpty: 1, truncated: 2, duplicates: 4)
        #expect(full.count > plain.count)
        #expect(full.contains("4"))
        #expect(full.contains("2"))
        #expect(!plain.contains("0"))
    }

    @Test func truncatedCountsAreReported() async throws {
        let h = try Harness()
        h.model.stageImport(data: data(String(repeating: "y", count: 700)), filename: "list.txt")
        #expect(h.model.listMessage == AppModel.importSummary(added: 1, skippedEmpty: 0, truncated: 1, duplicates: 0))
    }

    @Test func importErrorsAreShownAndKeepTheList() async throws {
        let h = try Harness(items: ["keep"])
        h.model.stageImport(data: data("[1, 2]"), filename: "bad.json")
        #expect(h.model.banner?.text == ImportError.invalidJSONStructure.localizedDescription)
        h.model.stageImport(data: Data(), filename: "empty.txt")
        #expect(h.model.banner?.text == ImportError.emptyFile.localizedDescription)
        #expect(h.model.settings.items == ["keep"])
        #expect(h.model.pendingImport == nil)
    }

    @Test func missingFileShowsError() async throws {
        let h = try Harness()
        h.model.loadImport(from: h.directory.appendingPathComponent("nope.txt"))
        #expect(h.model.banner?.kind == .error)
    }

    @Test func importsFromAFileOnDisk() async throws {
        let h = try Harness()
        let file = h.directory.appendingPathComponent("quotes.txt")
        try data("first\\nline\nsecond").write(to: file)
        h.model.loadImport(from: file)
        #expect(h.model.settings.items == ["first\nline", "second"])
    }
}

@MainActor
@Suite("AppModel settings")
struct SettingsTests {
    @Test func changesPersist() async throws {
        let h = try Harness()
        h.model.settings.mode = .random
        h.model.settings.intervalMinutes = 45
        h.model.settings.triggers.wake = false
        h.model.settings.triggers.login = true

        let saved = h.savedSettings
        #expect(saved.mode == .random)
        #expect(saved.intervalMinutes == 45)
        #expect(saved.triggers.wake == false)
        #expect(saved.triggers.login == true)
    }

    @Test func intervalIsClampedToRange() async throws {
        let h = try Harness()
        h.model.settings.intervalMinutes = 0
        #expect(h.model.settings.intervalMinutes == 1)
        h.model.settings.intervalMinutes = 5000
        #expect(h.model.settings.intervalMinutes == 1440)
        #expect(h.savedSettings.intervalMinutes == 1440)
        h.model.settings.intervalMinutes = -20
        #expect(h.savedSettings.intervalMinutes == 1)
    }

    @Test func defaultsMatchTheSpec() async throws {
        let h = try Harness()
        #expect(h.model.settings.intervalMinutes == 30)
        #expect(h.model.settings.mode == .sequential)
    }

    @Test func oversizedStoredIntervalIsClampedOnLoad() async throws {
        let dir = try makeTempDirectory()
        try SettingsStore(directory: dir).save(AppSettings(intervalMinutes: 99_999))
        let model = AppModel(
            settingsStore: SettingsStore(directory: dir),
            stateStore: StateStore(directory: dir),
            helper: FakeSystem(),
            reader: FakeSystem(),
            loginItem: FakeLoginItem()
        )
        #expect(model.settings.intervalMinutes == 1440)
    }

    @Test func pauseIsSavedAndRestored() async throws {
        let h = try Harness(items: ["a"])
        #expect(!h.model.isPaused)
        h.model.isPaused = true
        #expect(h.model.settings.paused)
        #expect(h.savedSettings.paused)
        #expect(h.savedSettings.items == ["a"])

        let reopened = AppModel(
            settingsStore: SettingsStore(directory: h.directory),
            stateStore: StateStore(directory: h.directory),
            helper: FakeSystem(),
            reader: FakeSystem(),
            loginItem: FakeLoginItem()
        )
        #expect(reopened.isPaused)
        reopened.isPaused = false
        #expect(!h.savedSettings.paused)
    }

    @Test func pausingDoesNotStopManualNext() async throws {
        let h = try Harness(items: ["a", "b"])
        h.model.isPaused = true
        await h.model.advance()
        #expect(h.system.writes == ["a"])
    }
}

@Suite("Environment")
struct EnvironmentTests {
    @Test func dataDirectoryOverride() {
        let url = AppEnvironment.dataDirectory(environment: ["LOCKROTATE_DATA_DIR": "/tmp/lockrotate-dev"])
        #expect(url.path == "/tmp/lockrotate-dev")
    }

    @Test func tildeIsExpanded() {
        let url = AppEnvironment.dataDirectory(environment: ["LOCKROTATE_DATA_DIR": "~/lr-dev"])
        #expect(url.path == NSHomeDirectory() + "/lr-dev")
    }

    @Test func defaultsToApplicationSupport() {
        #expect(AppEnvironment.dataDirectory(environment: [:]) == LockRotateDirectory.defaultURL())
        #expect(AppEnvironment.dataDirectory(environment: ["LOCKROTATE_DATA_DIR": ""]) == LockRotateDirectory.defaultURL())
        #expect(AppEnvironment.dataDirectory(environment: [:]).path.hasSuffix("Application Support/LockRotate"))
    }

    @MainActor
    @Test func liveModelUsesTheOverrideDirectory() async throws {
        let dir = try makeTempDirectory()
        try SettingsStore(directory: dir).save(AppSettings(items: ["from override"]))
        let model = AppModel.live(environment: ["LOCKROTATE_DATA_DIR": dir.path])
        #expect(model.settings.items == ["from override"])
        model.settings.intervalMinutes = 77
        #expect(SettingsStore(directory: dir).load().intervalMinutes == 77)
    }
}

@MainActor
@Suite("Panel and settings state")
struct PanelStateTests {
    @Test func currentPositionFindsTheTextInTheList() async throws {
        let h = try Harness(items: ["a", "b", "c"], system: FakeSystem(text: "b"))
        #expect(h.model.currentPosition == 2)
        await h.model.advance()
        #expect(h.model.currentPosition == 1)
    }

    @Test func currentPositionIsNilForTextFromElsewhere() throws {
        #expect(try Harness(items: ["a"], system: FakeSystem(text: "set by hand")).model.currentPosition == nil)
        #expect(try Harness(items: ["a"], system: FakeSystem(text: nil)).model.currentPosition == nil)
    }

    @Test func startOpensAuthorizationOnlyWhileTheHelperIsMissing() async throws {
        let missing = try Harness(items: ["a"], system: FakeSystem(status: .notInstalled))
        await missing.model.start()
        #expect(missing.model.selectedTab == .helper)

        let installed = try Harness(items: ["a"])
        await installed.model.start()
        #expect(installed.model.selectedTab == .list)
    }
}
