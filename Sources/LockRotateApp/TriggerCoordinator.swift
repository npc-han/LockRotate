import Combine
import Foundation
import LockRotateCore

/// What the coordinator needs from the app model.
@MainActor
protocol TriggerHost: AnyObject {
    var settings: AppSettings { get }
    /// Emits the new settings synchronously on every change (and the current value on subscribe).
    var settingsPublisher: AnyPublisher<AppSettings, Never> { get }
    var isHelperInstalled: Bool { get }
    func refreshHelperStatus() async
    func advanceAutomatically() async
}

extension AppModel: TriggerHost {
    var settingsPublisher: AnyPublisher<AppSettings, Never> { $settings.eraseToAnyPublisher() }
}

/// Decides when the automatic triggers (timer, wake, unlock, app start) call `advanceAutomatically()`.
/// Each trigger is checked against the current settings when it fires; "Next" in the menu is not
/// handled here and always works.
@MainActor
final class TriggerCoordinator {
    /// Triggers closer together than this to the previous attempt are ignored: waking from sleep
    /// usually comes with an unlock, and one of them is enough.
    static let minimumGap: TimeInterval = 5
    /// Waits a moment after wake so the system (network, display) has settled.
    static let wakeDelay: TimeInterval = 3

    private weak var host: (any TriggerHost)?
    private let scheduler: any TriggerScheduling
    private let events: any SystemEventObserving

    private var started = false
    private var settingsSubscription: AnyCancellable?
    private var observations: [any TriggerCancellable] = []
    private var timer: (any TriggerCancellable)?
    private var timerInterval: TimeInterval?
    private var pendingWake: (any TriggerCancellable)?
    private var lastAttempt: Date?
    /// The advance started by the latest trigger; tests await it.
    private(set) var inFlight: Task<Void, Never>?

    init(host: any TriggerHost, scheduler: any TriggerScheduling, events: any SystemEventObserving) {
        self.host = host
        self.scheduler = scheduler
        self.events = events
    }

    /// Subscribes to settings and system events, then runs the one automatic rotation at app start.
    func start() async {
        guard !started, let host else { return }
        started = true

        settingsSubscription = host.settingsPublisher.sink { [weak self] settings in
            MainActor.assumeIsolated { self?.applyTimer(for: settings) }
        }
        observations.append(events.observe(.didWake) { [weak self] in self?.didWake() })
        observations.append(events.observe(.screenUnlocked) { [weak self] in
            self?.attempt { $0.unlock }
        })

        await host.refreshHelperStatus()
        guard shouldRotateAtStart(host.settings), host.isHelperInstalled, claimAttempt() else { return }
        await host.advanceAutomatically()
    }

    func stop() {
        settingsSubscription = nil
        observations.forEach { $0.cancel() }
        observations.removeAll()
        timer?.cancel()
        timer = nil
        timerInterval = nil
        pendingWake?.cancel()
        pendingWake = nil
        started = false
    }

    // MARK: Triggers

    private func shouldRotateAtStart(_ settings: AppSettings) -> Bool {
        let t = settings.triggers
        return !settings.paused && (t.timer || t.wake || t.unlock || t.login)
    }

    /// Reschedules only when the timer is switched on/off, paused, or the interval changes, so
    /// editing the list does not restart the countdown.
    private func applyTimer(for settings: AppSettings) {
        let wanted: TimeInterval? = settings.triggers.timer && !settings.paused
            ? TimeInterval(max(1, settings.intervalMinutes)) * 60
            : nil
        guard wanted != timerInterval else { return }
        timer?.cancel()
        timer = nil
        timerInterval = wanted
        if let wanted {
            timer = scheduler.every(wanted) { [weak self] in
                self?.attempt { $0.timer }
            }
        }
    }

    private func didWake() {
        guard let host, host.settings.triggers.wake, !host.settings.paused else { return }
        pendingWake?.cancel()
        pendingWake = scheduler.after(Self.wakeDelay) { [weak self] in
            self?.pendingWake = nil
            self?.attempt { $0.wake }
        }
    }

    /// Runs one rotation if the source is enabled, not paused, and not too close to the last attempt.
    private func attempt(source isEnabled: (TriggerSettings) -> Bool) {
        guard let host else { return }
        let settings = host.settings
        guard !settings.paused, isEnabled(settings.triggers), claimAttempt() else { return }
        inFlight = Task { [weak host] in await host?.advanceAutomatically() }
    }

    /// Records an attempt unless the previous one was less than `minimumGap` seconds ago.
    private func claimAttempt() -> Bool {
        let now = scheduler.now
        if let last = lastAttempt {
            let gap = now.timeIntervalSince(last)
            if gap >= 0 && gap < Self.minimumGap { return false }
        }
        lastAttempt = now
        return true
    }
}
