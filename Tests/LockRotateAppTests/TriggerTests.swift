import Combine
import Foundation
import Testing
import LockRotateCore
import LockRotateSystem
@testable import LockRotateApp

// MARK: Fakes

@MainActor
final class FakeScheduler: TriggerScheduling {
    @MainActor
    final class Handle: TriggerCancellable {
        let interval: TimeInterval
        let repeats: Bool
        let action: @MainActor () -> Void
        private(set) var cancelled = false

        init(interval: TimeInterval, repeats: Bool, action: @escaping @MainActor () -> Void) {
            self.interval = interval
            self.repeats = repeats
            self.action = action
        }

        func cancel() { cancelled = true }
    }

    var now = Date(timeIntervalSince1970: 1_000_000)
    private(set) var handles: [Handle] = []

    var timers: [Handle] { handles.filter(\.repeats) }
    var activeTimers: [Handle] { timers.filter { !$0.cancelled } }
    var activeDelays: [Handle] { handles.filter { !$0.repeats && !$0.cancelled } }

    func every(_ interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any TriggerCancellable {
        let handle = Handle(interval: interval, repeats: true, action: action)
        handles.append(handle)
        return handle
    }

    func after(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any TriggerCancellable {
        let handle = Handle(interval: delay, repeats: false, action: action)
        handles.append(handle)
        return handle
    }

    func advanceTime(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }

    /// Fires a handle the way the real timer would (a one-shot is spent afterwards).
    func fire(_ handle: Handle) {
        guard !handle.cancelled else { return }
        handle.action()
        if !handle.repeats { handle.cancel() }
    }
}

@MainActor
final class FakeEvents: SystemEventObserving {
    private final class Registration: TriggerCancellable {
        var active = true
        let handler: @MainActor () -> Void
        init(handler: @escaping @MainActor () -> Void) { self.handler = handler }
        func cancel() { active = false }
    }

    private var registrations: [SystemEvent: [Registration]] = [:]

    func observe(_ event: SystemEvent, _ handler: @escaping @MainActor () -> Void) -> any TriggerCancellable {
        let registration = Registration(handler: handler)
        registrations[event, default: []].append(registration)
        return registration
    }

    func post(_ event: SystemEvent) {
        for registration in registrations[event] ?? [] where registration.active {
            registration.handler()
        }
    }

    func observerCount(_ event: SystemEvent) -> Int {
        (registrations[event] ?? []).filter(\.active).count
    }
}

@MainActor
final class FakeHost: TriggerHost {
    private let subject: CurrentValueSubject<AppSettings, Never>
    var isHelperInstalled: Bool
    private(set) var advanceCount = 0
    private(set) var refreshCount = 0

    init(settings: AppSettings = AppSettings(), helperInstalled: Bool = true) {
        subject = CurrentValueSubject(settings)
        isHelperInstalled = helperInstalled
    }

    var settings: AppSettings {
        get { subject.value }
        set { subject.send(newValue) }
    }

    var settingsPublisher: AnyPublisher<AppSettings, Never> { subject.eraseToAnyPublisher() }

    func refreshHelperStatus() async { refreshCount += 1 }
    func advanceAutomatically() async { advanceCount += 1 }
}

@MainActor
struct TriggerRig {
    let host: FakeHost
    let scheduler = FakeScheduler()
    let events = FakeEvents()
    let coordinator: TriggerCoordinator

    init(settings: AppSettings = AppSettings(), helperInstalled: Bool = true) {
        host = FakeHost(settings: settings, helperInstalled: helperInstalled)
        coordinator = TriggerCoordinator(host: host, scheduler: scheduler, events: events)
    }

    /// Lets the advance started by the last trigger finish.
    func settle() async { await coordinator.inFlight?.value }

    var advances: Int { host.advanceCount }
}

private func settings(
    timer: Bool = false, wake: Bool = false, unlock: Bool = false, login: Bool = false,
    minutes: Int = 30, paused: Bool = false
) -> AppSettings {
    AppSettings(
        intervalMinutes: minutes,
        triggers: TriggerSettings(timer: timer, wake: wake, unlock: unlock, login: login),
        paused: paused
    )
}

// MARK: Timer

@MainActor
@Suite("Trigger timer")
struct TimerTriggerTests {
    @Test func scheduledWhenEnabledAtTheConfiguredInterval() async {
        let rig = TriggerRig(settings: settings(timer: true, minutes: 15))
        await rig.coordinator.start()
        #expect(rig.scheduler.activeTimers.map(\.interval) == [15 * 60])
    }

    @Test func notScheduledWhenDisabledOrPaused() async {
        let off = TriggerRig(settings: settings(timer: false))
        await off.coordinator.start()
        #expect(off.scheduler.timers.isEmpty)

        let paused = TriggerRig(settings: settings(timer: true, paused: true))
        await paused.coordinator.start()
        #expect(paused.scheduler.timers.isEmpty)
    }

    @Test func firingAdvances() async {
        let rig = TriggerRig(settings: settings(timer: true))
        await rig.coordinator.start()
        rig.scheduler.advanceTime(by: 1800)
        rig.scheduler.fire(rig.scheduler.activeTimers[0])
        await rig.settle()
        // One for the app start, one for the timer.
        #expect(rig.advances == 2)
    }

    @Test func switchingOffCancelsAndOnSchedulesAgain() async {
        let rig = TriggerRig(settings: settings(timer: true))
        await rig.coordinator.start()
        let first = rig.scheduler.timers[0]

        rig.host.settings.triggers.timer = false
        #expect(first.cancelled)
        #expect(rig.scheduler.activeTimers.isEmpty)

        rig.host.settings.triggers.timer = true
        #expect(rig.scheduler.timers.count == 2)
        #expect(rig.scheduler.activeTimers.count == 1)
    }

    @Test func intervalChangeReplacesTheOldTimer() async {
        let rig = TriggerRig(settings: settings(timer: true, minutes: 30))
        await rig.coordinator.start()
        let first = rig.scheduler.timers[0]

        rig.host.settings.intervalMinutes = 5
        #expect(first.cancelled)
        #expect(rig.scheduler.activeTimers.map(\.interval) == [5 * 60])
    }

    @Test func unrelatedChangesKeepTheCountdown() async {
        let rig = TriggerRig(settings: settings(timer: true))
        await rig.coordinator.start()
        rig.host.settings.items = ["a", "b"]
        rig.host.settings.mode = .random
        rig.host.settings.triggers.wake = true
        #expect(rig.scheduler.timers.count == 1)
        #expect(!rig.scheduler.timers[0].cancelled)
    }

    @Test func pausingCancelsAndResumingSchedulesAgain() async {
        let rig = TriggerRig(settings: settings(timer: true))
        await rig.coordinator.start()

        rig.host.settings.paused = true
        #expect(rig.scheduler.activeTimers.isEmpty)

        rig.host.settings.paused = false
        #expect(rig.scheduler.activeTimers.count == 1)
    }

    @Test func realModelChangesReschedule() async throws {
        let h = try Harness(items: ["a"], system: FakeSystem(status: .installed))
        let scheduler = FakeScheduler()
        let coordinator = TriggerCoordinator(host: h.model, scheduler: scheduler, events: FakeEvents())
        await coordinator.start()
        #expect(scheduler.activeTimers.map(\.interval) == [30 * 60])

        h.model.settings.intervalMinutes = 10
        #expect(scheduler.activeTimers.map(\.interval) == [10 * 60])
        h.model.settings.triggers.timer = false
        #expect(scheduler.activeTimers.isEmpty)
        h.model.settings.triggers.timer = true
        h.model.isPaused = true
        #expect(scheduler.activeTimers.isEmpty)
        h.model.isPaused = false
        #expect(scheduler.activeTimers.map(\.interval) == [10 * 60])

        // The model clamps the interval after the change; the timer follows the final value.
        h.model.settings.intervalMinutes = 99_999
        #expect(scheduler.activeTimers.map(\.interval) == [1440 * 60])
    }
}

// MARK: Dedupe and pause

@MainActor
@Suite("Trigger dedupe and pause")
struct TriggerGateTests {
    @Test func triggersWithinFiveSecondsAreIgnored() async {
        let rig = TriggerRig(settings: settings(unlock: true))
        await rig.coordinator.start()   // app start counts as an attempt: 1
        #expect(rig.advances == 1)

        rig.scheduler.advanceTime(by: 4.9)
        rig.events.post(.screenUnlocked)
        await rig.settle()
        #expect(rig.advances == 1)

        rig.scheduler.advanceTime(by: 0.1)
        rig.events.post(.screenUnlocked)
        await rig.settle()
        #expect(rig.advances == 2)

        // An ignored trigger does not push the window forward.
        rig.scheduler.advanceTime(by: 3)
        rig.events.post(.screenUnlocked)
        rig.scheduler.advanceTime(by: 2.5)
        rig.events.post(.screenUnlocked)
        await rig.settle()
        #expect(rig.advances == 3)
    }

    @Test func differentSourcesShareTheWindow() async {
        let rig = TriggerRig(settings: settings(timer: true, wake: true, unlock: true))
        await rig.coordinator.start()
        rig.scheduler.advanceTime(by: 60)

        rig.events.post(.screenUnlocked)
        rig.scheduler.fire(rig.scheduler.activeTimers[0])
        await rig.settle()
        #expect(rig.advances == 2)   // start + unlock; the timer tick right after is dropped
    }

    @Test func wakeFollowedByUnlockRotatesOnce() async {
        let rig = TriggerRig(settings: settings(wake: true, unlock: true), helperInstalled: false)
        await rig.coordinator.start()
        #expect(rig.advances == 0)

        rig.events.post(.didWake)
        rig.scheduler.advanceTime(by: 1)
        rig.events.post(.screenUnlocked)          // unlock arrives first
        rig.scheduler.advanceTime(by: 2)
        rig.scheduler.fire(rig.scheduler.activeDelays[0])   // the delayed wake rotation
        await rig.settle()
        #expect(rig.advances == 1)
    }

    @Test func pausedMeansNoAutomaticTrigger() async {
        let rig = TriggerRig(settings: settings(timer: true, wake: true, unlock: true, login: true, paused: true))
        await rig.coordinator.start()
        rig.events.post(.screenUnlocked)
        rig.events.post(.didWake)
        await rig.settle()
        #expect(rig.advances == 0)
        #expect(rig.scheduler.handles.isEmpty)
    }

    @Test func pausingBetweenWakeAndTheDelayedRotation() async {
        let rig = TriggerRig(settings: settings(wake: true), helperInstalled: false)
        await rig.coordinator.start()
        rig.events.post(.didWake)
        rig.host.settings.paused = true
        rig.scheduler.advanceTime(by: 3)
        rig.scheduler.fire(rig.scheduler.activeDelays[0])
        await rig.settle()
        #expect(rig.advances == 0)
    }

    @Test func disabledSourcesAreIgnored() async {
        let rig = TriggerRig(settings: settings(timer: true), helperInstalled: false)
        await rig.coordinator.start()
        rig.events.post(.screenUnlocked)
        rig.events.post(.didWake)
        await rig.settle()
        #expect(rig.advances == 0)
        #expect(rig.scheduler.activeDelays.isEmpty)
    }

    @Test func settingChangesTakeEffectWithoutResubscribing() async {
        let rig = TriggerRig(settings: settings(unlock: false), helperInstalled: false)
        await rig.coordinator.start()
        rig.events.post(.screenUnlocked)
        await rig.settle()
        #expect(rig.advances == 0)

        rig.host.settings.triggers.unlock = true
        rig.events.post(.screenUnlocked)
        await rig.settle()
        #expect(rig.advances == 1)
    }

    @Test func stopRemovesEverything() async {
        let rig = TriggerRig(settings: settings(timer: true, wake: true, unlock: true))
        await rig.coordinator.start()
        rig.coordinator.stop()
        #expect(rig.scheduler.activeTimers.isEmpty)
        #expect(rig.events.observerCount(.didWake) == 0)
        #expect(rig.events.observerCount(.screenUnlocked) == 0)
        rig.host.settings.triggers.timer = false
        rig.host.settings.triggers.timer = true
        #expect(rig.scheduler.activeTimers.isEmpty)
    }
}

// MARK: App start

@MainActor
@Suite("Trigger app start")
struct StartupTriggerTests {
    @Test(arguments: [
        settings(timer: true), settings(wake: true), settings(unlock: true), settings(login: true),
    ])
    func anyEnabledTriggerRotatesOnceAtStart(configuration: AppSettings) async {
        let rig = TriggerRig(settings: configuration)
        await rig.coordinator.start()
        #expect(rig.advances == 1)
        #expect(rig.host.refreshCount == 1)
    }

    @Test func nothingEnabledMeansNoRotation() async {
        let rig = TriggerRig(settings: settings())
        await rig.coordinator.start()
        #expect(rig.advances == 0)
    }

    @Test func pausedMeansNoRotation() async {
        let rig = TriggerRig(settings: settings(timer: true, login: true, paused: true))
        await rig.coordinator.start()
        #expect(rig.advances == 0)
    }

    @Test func missingHelperMeansNoRotation() async {
        let rig = TriggerRig(settings: settings(timer: true, login: true), helperInstalled: false)
        await rig.coordinator.start()
        #expect(rig.advances == 0)
    }

    @Test func startingTwiceDoesNotDoubleRegister() async {
        let rig = TriggerRig(settings: settings(timer: true, wake: true, unlock: true))
        await rig.coordinator.start()
        await rig.coordinator.start()
        #expect(rig.advances == 1)
        #expect(rig.events.observerCount(.didWake) == 1)
        #expect(rig.scheduler.timers.count == 1)
    }

    @Test func startRotatesTheRealModelOnce() async throws {
        let h = try Harness(items: ["a", "b"], system: FakeSystem(status: .installed))
        let coordinator = TriggerCoordinator(host: h.model, scheduler: FakeScheduler(), events: FakeEvents())
        await coordinator.start()
        #expect(h.system.writes == ["a"])
    }
}

// MARK: Wake and unlock

@MainActor
@Suite("Trigger wake and unlock")
struct WakeUnlockTests {
    @Test func wakeWaitsThreeSecondsThenRotates() async {
        let rig = TriggerRig(settings: settings(wake: true), helperInstalled: false)
        await rig.coordinator.start()

        rig.events.post(.didWake)
        #expect(rig.advances == 0)
        let delays = rig.scheduler.activeDelays
        #expect(delays.map(\.interval) == [TriggerCoordinator.wakeDelay])
        #expect(TriggerCoordinator.wakeDelay == 3)

        rig.scheduler.fire(delays[0])
        await rig.settle()
        #expect(rig.advances == 1)
    }

    @Test func repeatedWakeKeepsOnlyTheLatestDelay() async {
        let rig = TriggerRig(settings: settings(wake: true), helperInstalled: false)
        await rig.coordinator.start()
        rig.events.post(.didWake)
        let first = rig.scheduler.handles[0]
        rig.events.post(.didWake)
        #expect(first.cancelled)
        #expect(rig.scheduler.activeDelays.count == 1)
    }

    @Test func wakeIgnoredWhenDisabled() async {
        let rig = TriggerRig(settings: settings(wake: false, unlock: true), helperInstalled: false)
        await rig.coordinator.start()
        rig.events.post(.didWake)
        #expect(rig.scheduler.handles.isEmpty)
    }

    @Test func unlockRotatesImmediately() async {
        let rig = TriggerRig(settings: settings(unlock: true), helperInstalled: false)
        await rig.coordinator.start()
        rig.events.post(.screenUnlocked)
        await rig.settle()
        #expect(rig.advances == 1)
    }

    @Test func realDistributedNotificationReachesTheCoordinator() async throws {
        let host = FakeHost(settings: settings(unlock: true), helperInstalled: false)
        let coordinator = TriggerCoordinator(
            host: host,
            scheduler: FakeScheduler(),
            events: NotificationEventSource()
        )
        await coordinator.start()
        defer { coordinator.stop() }
        #expect(host.advanceCount == 0)

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        // Delivery goes through the system's notification daemon, so give it a moment.
        for _ in 0..<100 {
            await coordinator.inFlight?.value
            if host.advanceCount > 0 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(host.advanceCount == 1)
    }
}

// MARK: Model side of automatic rotation

@MainActor
@Suite("Automatic advance in the model")
struct AutomaticAdvanceTests {
    @Test func missingHelperIsSkippedQuietly() async throws {
        let h = try Harness(items: ["a", "b"], system: FakeSystem(text: "old", status: .notInstalled))
        for _ in 0..<3 { await h.model.advanceAutomatically() }

        #expect(h.system.writes.isEmpty)
        #expect(h.model.banner == nil)
        #expect(h.model.helperStatus == .notInstalled)
        #expect(h.model.showsInstallHelper)
        #expect(h.model.rotationState == RotationState())
    }

    @Test func installingTheHelperLaterLetsRotationContinue() async throws {
        let h = try Harness(items: ["a"], system: FakeSystem(status: .notInstalled))
        await h.model.advanceAutomatically()
        #expect(h.system.writes.isEmpty)

        await h.model.installHelper()
        await h.model.advanceAutomatically()
        #expect(h.system.writes == ["a"])
    }

    @Test func helperRemovedBehindOurBackStaysQuiet() async throws {
        let system = FakeSystem(status: .installed)
        let h = try Harness(items: ["a"], system: system)
        await h.model.start()
        system.failSetText(with: .helperNotInstalled)
        await h.model.advanceAutomatically()
        #expect(h.model.banner == nil)
        #expect(h.model.helperStatus == .notInstalled)
    }

    @Test func pausedDoesNothingButManualStillWorks() async throws {
        let h = try Harness(items: ["a", "b"])
        h.model.isPaused = true
        await h.model.advanceAutomatically()
        #expect(h.system.writes.isEmpty)
        await h.model.advance()
        #expect(h.system.writes == ["a"])
    }

    @Test func emptyListIsQuietForAutomaticButNotManual() async throws {
        let h = try Harness()
        await h.model.advanceAutomatically()
        #expect(h.model.banner == nil)
        await h.model.advance()
        #expect(h.model.banner?.action == .openList)
    }

    @Test func installedHelperWritesAndSaves() async throws {
        let h = try Harness(items: ["a", "b", "c"])
        await h.model.advanceAutomatically()
        await h.model.advanceAutomatically()
        #expect(h.system.writes == ["a", "b"])
        #expect(h.savedState.position == 2)
    }

    @Test func realFailuresStillShow() async throws {
        let system = FakeSystem()
        system.failSetText(with: .timedOut)
        let h = try Harness(items: ["a"], system: system)
        await h.model.advanceAutomatically()
        #expect(h.model.banner?.text == SystemError.timedOut.localizedDescription)
    }
}

// MARK: Login item

@MainActor
@Suite("Login item")
struct LoginItemTests {
    @Test(arguments: [
        (LoginItemStatus.enabled, true),
        (.requiresApproval, true),
        (.notRegistered, false),
        (.notFound, false),
    ])
    func switchReflectsTheRealState(status: LoginItemStatus, expectedOn: Bool) async throws {
        let h = try Harness(loginItem: FakeLoginItem(status: status))
        #expect(h.model.isLoginItemOn == expectedOn)
        await h.model.start()
        #expect(h.model.isLoginItemOn == expectedOn)
        #expect(h.model.settings.triggers.login == expectedOn)
        #expect(h.savedSettings.triggers.login == expectedOn)
    }

    @Test func approvalNeededIsExposed() async throws {
        let h = try Harness(loginItem: FakeLoginItem(status: .requiresApproval))
        #expect(h.model.loginItemNeedsApproval)
        h.model.openLoginItemsSettings()
        #expect(h.loginItem.openedSettings == 1)

        h.loginItem.setStatus(.enabled)
        h.model.refreshLoginItem()
        #expect(!h.model.loginItemNeedsApproval)
        #expect(h.model.isLoginItemOn)
    }

    @Test func enablingRegistersAndPersists() async throws {
        let h = try Harness()
        h.model.setLoginItem(enabled: true)
        #expect(h.loginItem.registerCalls == 1)
        #expect(h.model.isLoginItemOn)
        #expect(h.model.settings.triggers.login)
        #expect(h.savedSettings.triggers.login)
        #expect(h.model.banner == nil)
    }

    @Test func enablingCanLandOnNeedsApproval() async throws {
        let h = try Harness()
        h.loginItem.registerLeaves(.requiresApproval)
        h.model.setLoginItem(enabled: true)
        #expect(h.model.isLoginItemOn)
        #expect(h.model.loginItemNeedsApproval)
        #expect(h.model.settings.triggers.login)
    }

    @Test func failedRegistrationShowsTheErrorAndSwitchesBackOff() async throws {
        let h = try Harness()
        h.loginItem.failRegister(true)
        h.model.setLoginItem(enabled: true)

        #expect(!h.model.isLoginItemOn)
        #expect(!h.model.settings.triggers.login)
        #expect(!h.savedSettings.triggers.login)
        #expect(h.model.banner?.kind == .error)
        #expect(h.model.banner?.text.contains("Operation not permitted") == true)
    }

    @Test func aLaterSuccessTakesTheErrorDown() async throws {
        let h = try Harness()
        h.loginItem.failRegister(true)
        h.model.setLoginItem(enabled: true)
        #expect(h.model.banner != nil)

        h.loginItem.failRegister(false)
        h.model.setLoginItem(enabled: true)
        #expect(h.model.banner == nil)
        #expect(h.model.isLoginItemOn)
    }

    @Test func aLaterSuccessKeepsUnrelatedBanners() async throws {
        let h = try Harness()
        h.model.stageImport(data: Data(), filename: "x.txt")
        let other = h.model.banner
        #expect(other != nil)
        h.model.setLoginItem(enabled: true)
        #expect(h.model.banner == other)
    }

    @Test func disablingUnregisters() async throws {
        let h = try Harness(loginItem: FakeLoginItem(status: .enabled))
        await h.model.start()
        h.model.setLoginItem(enabled: false)
        #expect(h.loginItem.unregisterCalls == 1)
        #expect(!h.model.isLoginItemOn)
        #expect(!h.savedSettings.triggers.login)
    }

    @Test func failedUnregisterKeepsTheSwitchOn() async throws {
        let h = try Harness(loginItem: FakeLoginItem(status: .enabled))
        await h.model.start()
        h.loginItem.failUnregister(true)
        h.model.setLoginItem(enabled: false)
        #expect(h.model.isLoginItemOn)
        #expect(h.model.settings.triggers.login)
        #expect(h.model.banner?.kind == .error)
    }

    @Test func alreadyEnabledIsNotRegisteredAgain() async throws {
        let h = try Harness(loginItem: FakeLoginItem(status: .enabled))
        h.model.setLoginItem(enabled: true)
        #expect(h.loginItem.registerCalls == 0)
        #expect(h.model.isLoginItemOn)
    }

    @Test func removedBehindOurBackIsPickedUpOnRefresh() async throws {
        let h = try Harness(settings: settings(login: true), loginItem: FakeLoginItem(status: .enabled))
        await h.model.start()
        #expect(h.model.settings.triggers.login)

        h.loginItem.setStatus(.notRegistered)
        h.model.refreshLoginItem()
        #expect(!h.model.isLoginItemOn)
        #expect(!h.savedSettings.triggers.login)
    }

    @Test func staleSavedFlagIsCorrectedAtStart() async throws {
        let h = try Harness(settings: settings(login: true), loginItem: FakeLoginItem(status: .notRegistered))
        await h.model.start()
        #expect(!h.model.settings.triggers.login)
    }
}

// MARK: Persistence

@MainActor
@Suite("Trigger settings persistence")
struct TriggerPersistenceTests {
    @Test func allTriggerSettingsAreSaved() async throws {
        let h = try Harness()
        h.model.settings.triggers.timer = false
        h.model.settings.triggers.wake = false
        h.model.settings.triggers.unlock = false
        h.model.settings.intervalMinutes = 7
        h.model.isPaused = true

        let saved = h.savedSettings
        #expect(saved.triggers == TriggerSettings(timer: false, wake: false, unlock: false, login: false))
        #expect(saved.intervalMinutes == 7)
        #expect(saved.paused)
    }
}
