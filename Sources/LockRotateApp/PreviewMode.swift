#if DEBUG
import AppKit
import Foundation
import LockRotateSystem
import os
import SwiftUI

/// Development only (debug builds). With `LOCKROTATE_PREVIEW=1` the helper and the lock text
/// reader are replaced by an in-memory stand-in, so every state of the panel and the settings
/// window can be looked at without installing anything or touching the real lock screen.
///
/// - `LOCKROTATE_PREVIEW_HELPER=missing` starts as if the helper were not installed.
/// - `LOCKROTATE_PREVIEW_TEXT=...` is the text "on the lock screen" at launch.
/// - `LOCKROTATE_PREVIEW_PAGE=list|rotation|helper` picks the settings page.
/// - `LOCKROTATE_APPEARANCE=light|dark` forces the appearance.
/// - `LOCKROTATE_SNAPSHOT_SIZE=640x420` sets the snapshot settings window's content size.
/// - `LOCKROTATE_PREVIEW_EDITOR=new|edit` also shows the entry editor sheet in its own snapshot
///   window (`edit` opens the first entry in the list).
enum PreviewMode {
    static func system(environment: [String: String]) -> PreviewSystem? {
        guard environment["LOCKROTATE_PREVIEW"] == "1" else { return nil }
        return PreviewSystem(
            installed: environment["LOCKROTATE_PREVIEW_HELPER"] != "missing",
            text: environment["LOCKROTATE_PREVIEW_TEXT"]
        )
    }

    static func page(environment: [String: String]) -> AppModel.SettingsTab? {
        switch environment["LOCKROTATE_PREVIEW_PAGE"] {
        case "list": .list
        case "rotation": .rotation
        case "helper": .helper
        default: nil
        }
    }

    @MainActor
    static func applyAppearance(environment: [String: String]) {
        switch environment["LOCKROTATE_APPEARANCE"] {
        case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }

    /// `LOCKROTATE_SNAPSHOT=1` also puts the panel and the settings window in windows placed
    /// behind the desktop picture, so they can be captured by window id (`screencapture -l`)
    /// without showing anything on the display or needing clicks. The panel's window is 320 pt
    /// wide and the settings window 720 pt unless `LOCKROTATE_SNAPSHOT_SIZE` says otherwise.
    @MainActor
    static func showSnapshotWindows(model: AppModel, environment: [String: String]) {
        guard environment["LOCKROTATE_SNAPSHOT"] == "1" else { return }

        let panelContent = NSHostingView(rootView: MenuPanel(model: model))
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .withinWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        panelContent.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(panelContent)
        NSLayoutConstraint.activate([
            panelContent.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            panelContent.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            panelContent.topAnchor.constraint(equalTo: background.topAnchor),
            panelContent.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        let panel = NSWindow(
            contentRect: NSRect(origin: .zero, size: panelContent.fittingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = background
        panel.level = behindDesktop
        panel.setFrameOrigin(NSPoint(x: 40, y: 40))
        panel.orderFrontRegardless()

        let controller = NSHostingController(rootView: SettingsView(model: model))
        if #available(macOS 14.0, *) { controller.sceneBridgingOptions = [.toolbars, .title] }
        let settings = NSWindow(contentViewController: controller)
        settings.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        settings.toolbarStyle = .unified
        settings.setContentSize(snapshotSize(environment: environment))
        settings.level = behindDesktop
        settings.setFrameOrigin(NSPoint(x: 400, y: 40))
        settings.orderFrontRegardless()

        snapshotWindows = [panel, settings]

        // Sized to the editor's own fitting size, the way a sheet is.
        if let target = editorTarget(model: model, environment: environment) {
            let content = NSHostingView(rootView: EntryEditor(model: model, target: target))
            let editor = NSWindow(
                contentRect: NSRect(origin: .zero, size: content.fittingSize),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            editor.backgroundColor = .windowBackgroundColor
            editor.contentView = content
            editor.level = behindDesktop
            editor.setFrameOrigin(NSPoint(x: 40, y: 400))
            editor.orderFrontRegardless()
            snapshotWindows.append(editor)
        }
    }

    @MainActor private static var snapshotWindows: [NSWindow] = []

    @MainActor
    private static func editorTarget(model: AppModel, environment: [String: String]) -> EntryEditorTarget? {
        switch environment["LOCKROTATE_PREVIEW_EDITOR"] {
        case "new": EntryEditorTarget(index: nil, text: "")
        case "edit": model.settings.items.first.map { EntryEditorTarget(index: 0, text: $0) }
        default: nil
        }
    }

    private static func snapshotSize(environment: [String: String]) -> NSSize {
        let parts = (environment["LOCKROTATE_SNAPSHOT_SIZE"] ?? "").split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? NSSize(width: parts[0], height: parts[1]) : NSSize(width: 720, height: 480)
    }

    private static var behindDesktop: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
    }
}

/// Behaves like the real helper with a short delay, so progress indicators show.
final class PreviewSystem: HelperControlling, LockTextReading {
    private struct State {
        var installed: Bool
        var text: String?
    }

    private let state: OSAllocatedUnfairLock<State>

    init(installed: Bool, text: String?) {
        state = OSAllocatedUnfairLock(initialState: State(installed: installed, text: text))
    }

    func status() async -> HelperStatus {
        state.withLock { $0.installed ? .installed : .notInstalled }
    }

    func setLockText(_ text: String) async throws {
        try await Task.sleep(nanoseconds: 300_000_000)
        try state.withLock {
            guard $0.installed else { throw SystemError.helperNotInstalled }
            $0.text = text
        }
    }

    func install() async throws {
        try await Task.sleep(nanoseconds: 800_000_000)
        state.withLock { $0.installed = true }
    }

    func uninstall() async throws {
        try await Task.sleep(nanoseconds: 800_000_000)
        state.withLock {
            $0.installed = false
            $0.text = nil
        }
    }

    func current() -> String? {
        state.withLock { $0.text }
    }
}
#endif
