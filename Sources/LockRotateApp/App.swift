import AppKit
import SwiftUI

enum WindowID {
    static let settings = "settings"
}

struct LockRotateMenuApp: App {
    @StateObject private var model: AppModel
    /// Lives as long as the app; its timers and observers stop when it goes away.
    private let triggers: TriggerCoordinator

    init() {
        #if DEBUG
        PreviewMode.applyAppearance(environment: ProcessInfo.processInfo.environment)
        #endif
        let model = AppModel.live()
        let triggers = TriggerCoordinator(
            host: model,
            scheduler: TimerScheduler(),
            events: NotificationEventSource()
        )
        _model = StateObject(wrappedValue: model)
        self.triggers = triggers
        Task {
            await model.start()
            await triggers.start()
            #if DEBUG
            PreviewMode.showSnapshotWindows(model: model, environment: ProcessInfo.processInfo.environment)
            #endif
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(model: model)
        } label: {
            // Without this VoiceOver reads the SF Symbol's own name.
            Image(systemName: "text.quote")
                .accessibilityLabel(Text(loc("LockRotate")))
        }
        .menuBarExtraStyle(.window)

        Window(Text(loc("LockRotate Settings")), id: WindowID.settings) {
            SettingsView(model: model)
        }
        .defaultSize(width: 720, height: 480)
        .windowResizability(.contentMinSize)
    }
}

/// Brings the app to the front; a menu bar app is not active when its menu item is chosen.
/// The activation policy stays as is (no Dock icon).
@MainActor
func activateApp() {
    // Since macOS 14 the cooperative `activate()` is sometimes ignored when a menu item triggered it,
    // while the older call still works. Deployment target is 13, so this raises no deprecation warning.
    NSApp.activate(ignoringOtherApps: true)

    // `openWindow` creates the window asynchronously, so look for it a few times.
    Task { @MainActor in
        for delay in [0, 100, 300] as [UInt64] {
            if delay > 0 { try? await Task.sleep(nanoseconds: delay * 1_000_000) }
            if let window = settingsWindow() {
                bringToActiveSpace(window)
                return
            }
        }
    }
}

/// Shows the window on the Space the user is looking at, including over a full-screen app.
/// Without this a menu bar app's window opens on the desktop Space it was created on, and
/// choosing "Settings…" from a full-screen app appears to do nothing.
@MainActor
private func bringToActiveSpace(_ window: NSWindow) {
    window.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])
    if !window.isOnActiveSpace { window.orderOut(nil) }
    window.makeKeyAndOrderFront(nil)
}

/// The settings window: matched by its scene identifier (its title follows the selected page),
/// otherwise the only titled window that can take focus (the menu bar panel has no title bar).
@MainActor
func settingsWindow() -> NSWindow? {
    let candidates = NSApp.windows.filter { $0.styleMask.contains(.titled) && $0.canBecomeKey }
    return candidates.first { $0.identifier?.rawValue.contains(WindowID.settings) == true }
        ?? candidates.first
}
