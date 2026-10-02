import Foundation
import Testing
@testable import LockRotateCore

struct PersistenceTests {
    @Test func settingsDefaults() {
        let s = AppSettings()
        #expect(s.items.isEmpty)
        #expect(s.mode == .sequential)
        #expect(s.intervalMinutes == 30)
        #expect(s.triggers == TriggerSettings(timer: true, wake: true, unlock: true, login: false))
        #expect(s.paused == false)
    }

    @Test func pausedDefaultsToFalseWhenMissing() throws {
        let dir = try makeTempDirectory()
        try Data(#"{"items": ["a"]}"#.utf8).write(to: dir.appendingPathComponent("settings.json"))
        #expect(SettingsStore(directory: dir).load().paused == false)
    }

    @Test func pausedRoundTripsAndDecodesFromJSON() throws {
        let dir = try makeTempDirectory()
        let store = SettingsStore(directory: dir)
        try store.save(AppSettings(items: ["a"], paused: true))
        #expect(store.load().paused == true)
        try Data(#"{"paused": true}"#.utf8).write(to: dir.appendingPathComponent("settings.json"))
        #expect(store.load().paused == true)
    }

    @Test func missingFilesFallBackToDefaults() throws {
        let dir = try makeTempDirectory().appendingPathComponent("nested/not-yet", isDirectory: true)
        #expect(SettingsStore(directory: dir).load() == AppSettings())
        #expect(StateStore(directory: dir).load() == RotationState())
    }

    @Test func settingsRoundTrip() throws {
        let dir = try makeTempDirectory()
        let store = SettingsStore(directory: dir)
        let settings = AppSettings(
            items: ["你好", "multi\nline", "a/b"],
            mode: .random,
            intervalMinutes: 5,
            triggers: TriggerSettings(timer: false, wake: true, unlock: false, login: true)
        )
        try store.save(settings)
        #expect(SettingsStore(directory: dir).load() == settings)
    }

    @Test func saveCreatesDirectoryAndLeavesNoTempFiles() throws {
        let dir = try makeTempDirectory().appendingPathComponent("a/b", isDirectory: true)
        try SettingsStore(directory: dir).save(AppSettings(items: ["x"]))
        try StateStore(directory: dir).save(RotationState())
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == ["settings.json", "state.json"])
    }

    @Test func overwriteReplacesPreviousContent() throws {
        let dir = try makeTempDirectory()
        let store = SettingsStore(directory: dir)
        try store.save(AppSettings(items: ["old"]))
        try store.save(AppSettings(items: ["new"]))
        #expect(store.load().items == ["new"])
    }

    @Test func stateRoundTrip() throws {
        let dir = try makeTempDirectory()
        var rng = SplitMix64(seed: 5)
        var rotator = Rotator()
        _ = rotator.next(items: ["a", "b", "c"], mode: .random, using: &rng)
        let store = StateStore(directory: dir)
        try store.save(rotator.state)
        #expect(store.load() == rotator.state)
    }

    @Test(arguments: ["", "not json", "{\"items\": ", "[1,2,3]", "\u{0}\u{1}"])
    func corruptFilesFallBackToDefaults(garbage: String) throws {
        let dir = try makeTempDirectory()
        try Data(garbage.utf8).write(to: dir.appendingPathComponent("settings.json"))
        try Data(garbage.utf8).write(to: dir.appendingPathComponent("state.json"))
        #expect(SettingsStore(directory: dir).load() == AppSettings())
        #expect(StateStore(directory: dir).load() == RotationState())
    }

    @Test func wrongTypedFieldsFallBackToDefaults() throws {
        let dir = try makeTempDirectory()
        try Data(#"{"items": "oops", "mode": 3}"#.utf8).write(to: dir.appendingPathComponent("settings.json"))
        #expect(SettingsStore(directory: dir).load() == AppSettings())
    }

    @Test func partialSettingsFileKeepsDefaultsForMissingKeys() throws {
        let dir = try makeTempDirectory()
        try Data(#"{"items": ["a"], "triggers": {"login": true}}"#.utf8)
            .write(to: dir.appendingPathComponent("settings.json"))
        let s = SettingsStore(directory: dir).load()
        #expect(s.items == ["a"])
        #expect(s.intervalMinutes == 30)
        #expect(s.mode == .sequential)
        #expect(s.triggers == TriggerSettings(timer: true, wake: true, unlock: true, login: true))
    }

    @Test func intervalIsClampedToAtLeastOneMinute() throws {
        let dir = try makeTempDirectory()
        try Data(#"{"intervalMinutes": 0}"#.utf8).write(to: dir.appendingPathComponent("settings.json"))
        #expect(SettingsStore(directory: dir).load().intervalMinutes == 1)
        #expect(AppSettings(intervalMinutes: -5).intervalMinutes == 1)
    }

    @Test func defaultDirectoryIsUnderApplicationSupport() {
        let path = LockRotateDirectory.defaultURL().path
        #expect(path.hasSuffix("/Library/Application Support/LockRotate"))
    }
}
