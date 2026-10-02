import AppKit
import Foundation
import ServiceManagement

// Small protocols around the system pieces the triggers use (clock/timers, notifications, the
// login item) so tests can replace them. The live implementations are at the bottom.

// MARK: Login item

enum LoginItemStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

protocol LoginItemControlling: Sendable {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

/// `SMAppService.mainApp`. Registering fails for builds the system won't accept, for example an
/// ad-hoc signed copy that is not in /Applications; the caller shows that error.
struct MainAppLoginItem: LoginItemControlling {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

// MARK: Scheduling

@MainActor
protocol TriggerCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol TriggerScheduling: AnyObject {
    var now: Date { get }
    /// Runs `action` every `interval` seconds until cancelled. Missed periods are not made up.
    func every(_ interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any TriggerCancellable
    func after(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any TriggerCancellable
}

@MainActor
final class TimerHandle: TriggerCancellable {
    private var timer: Timer?

    init(_ timer: Timer) { self.timer = timer }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
final class TimerScheduler: TriggerScheduling {
    var now: Date { Date() }

    func every(_ interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any TriggerCancellable {
        make(interval, repeats: true, action)
    }

    func after(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any TriggerCancellable {
        make(delay, repeats: false, action)
    }

    private func make(_ interval: TimeInterval, repeats: Bool, _ action: @escaping @MainActor () -> Void) -> TimerHandle {
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in
            MainActor.assumeIsolated { action() }
        }
        // `.common` so it also fires while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        return TimerHandle(timer)
    }
}

// MARK: System events

enum SystemEvent: Equatable, Sendable {
    case didWake
    case screenUnlocked
}

@MainActor
protocol SystemEventObserving: AnyObject {
    func observe(_ event: SystemEvent, _ handler: @escaping @MainActor () -> Void) -> any TriggerCancellable
}

@MainActor
final class NotificationObservation: TriggerCancellable {
    private let center: NotificationCenter
    private var token: (any NSObjectProtocol)?

    init(center: NotificationCenter, token: any NSObjectProtocol) {
        self.center = center
        self.token = token
    }

    func cancel() {
        if let token { center.removeObserver(token) }
        token = nil
    }
}

@MainActor
final class NotificationEventSource: SystemEventObserving {
    /// Posted by the system to the distributed center when the user unlocks the screen. This is
    /// not a documented API, so it may change or disappear; if it is never posted, the unlock
    /// trigger simply never fires and nothing else is affected.
    static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")

    private let workspaceCenter: NotificationCenter
    private let distributedCenter: NotificationCenter

    init(
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        distributedCenter: NotificationCenter = DistributedNotificationCenter.default()
    ) {
        self.workspaceCenter = workspaceCenter
        self.distributedCenter = distributedCenter
    }

    func observe(_ event: SystemEvent, _ handler: @escaping @MainActor () -> Void) -> any TriggerCancellable {
        let center: NotificationCenter
        let name: Notification.Name
        switch event {
        case .didWake:
            center = workspaceCenter
            name = NSWorkspace.didWakeNotification
        case .screenUnlocked:
            center = distributedCenter
            name = Self.screenUnlocked
        }
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        return NotificationObservation(center: center, token: token)
    }
}
