import AppKit
import LockRotateCore
import SwiftUI

/// The panel under the menu bar icon: the lock screen text as it looks there, what happens next,
/// and the few actions people need without opening settings.
struct MenuPanel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var panel = WindowReference()

    var body: some View {
        VStack(spacing: 12) {
            header
            VStack(spacing: 8) {
                LockScreenCard(text: model.currentText)
                positionLine
            }
            if let banner = model.banner {
                PanelBanner(banner: banner, model: model) { openSettings($0) }
            }
            actions
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .background(WindowReader(reference: panel))
        .onAppear { model.refreshCurrentText() }
        // The panel's view stays alive between openings; refresh each time it is shown.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if let window = note.object as? NSWindow, window === panel.window {
                model.refreshCurrentText()
            }
        }
    }

    // MARK: State

    private enum Phase {
        case checking, needsHelper, emptyList, ready
    }

    private var phase: Phase {
        switch model.helperStatus {
        case nil: .checking
        case .notInstalled?: .needsHelper
        case .installed?: model.settings.items.isEmpty ? .emptyList : .ready
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: "LockRotate")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            status
        }
    }

    private var status: some View {
        let (symbol, text, warning) = statusContent
        return Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(warning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private var statusContent: (String, LocalizedStringResource, Bool) {
        let settings = model.settings
        switch phase {
        case .checking:
            return ("ellipsis.circle", loc("Checking…"), false)
        case .needsHelper:
            return ("exclamationmark.circle.fill", loc("Not authorized"), true)
        case .emptyList:
            return ("tray", loc("List is empty"), false)
        case .ready:
            if settings.paused { return ("pause.circle", loc("Paused"), false) }
            if settings.triggers.timer { return ("clock", loc("Every \(settings.intervalMinutes) min"), false) }
            if settings.triggers.wake || settings.triggers.unlock {
                return ("sunrise", loc("On wake or unlock"), false)
            }
            return ("hand.tap", loc("Manual only"), false)
        }
    }

    @ViewBuilder
    private var positionLine: some View {
        let count = model.settings.items.count
        if count > 0 {
            let mode = Text(loc(model.settings.mode == .sequential ? "In order" : "Shuffle"))
            Group {
                if let position = model.currentPosition {
                    Text(loc("No. \(position) of \(count)")) + Text(verbatim: "  ·  ") + mode
                } else {
                    Text(loc("\(count) entries")) + Text(verbatim: "  ·  ") + mode
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch phase {
        case .needsHelper:
            Button(loc("Authorize…")) { openSettings(.helper) }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .keyboardShortcut(.defaultAction)
        case .emptyList:
            Button(loc("Import list…")) { openSettings(.list) }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .keyboardShortcut(.defaultAction)
        case .checking, .ready:
            HStack(spacing: 8) {
                Button {
                    Task { await model.advance() }
                } label: {
                    HStack(spacing: 6) {
                        if model.isAdvancing {
                            ProgressView().controlSize(.small).tint(.secondary)
                        }
                        Text(loc("Next"))
                    }
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .keyboardShortcut(.defaultAction)
                .disabled(model.isBusy)

                Button {
                    model.isPaused.toggle()
                } label: {
                    Label(
                        loc(model.isPaused ? "Resume" : "Pause"),
                        systemImage: model.isPaused ? "play.fill" : "pause.fill"
                    )
                    .labelStyle(.titleAndIcon)
                }
                .buttonStyle(SecondaryButtonStyle())
                .help(Text(loc(model.isPaused ? "Resume automatic rotation" : "Pause automatic rotation")))
                .accessibilityLabel(Text(loc(model.isPaused ? "Resume automatic rotation" : "Pause automatic rotation")))
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                openSettings()
            } label: {
                Label(loc("Settings…"), systemImage: "gearshape")
            }
            .keyboardShortcut(",")

            Spacer()

            Button(loc("Quit")) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(QuietButtonStyle())
        .padding(.horizontal, -8)
    }

    // MARK: Actions

    private func openSettings(_ tab: AppModel.SettingsTab? = nil) {
        if let tab { model.selectedTab = tab }
        MenuBarPanel.dismiss(panel.window)
        openWindow(id: WindowID.settings)
        activateApp()
    }
}

/// A notice or error in the panel, with the action that resolves it.
private struct PanelBanner: View {
    let banner: AppModel.Banner
    @ObservedObject var model: AppModel
    let open: (AppModel.SettingsTab) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: banner.kind == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(banner.kind == .error ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(banner.text)
                    .font(.callout)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if let action = banner.action {
                    switch action {
                    case .installHelper:
                        Button(loc("Go to Authorization")) { open(.helper) }
                    case .openList:
                        Button(loc("Go to List")) { open(.list) }
                    }
                }
            }
            .buttonStyle(.link)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                model.dismissBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text(loc("Dismiss")))
        }
        .padding(10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// Closing the `MenuBarExtra` panel from code. Closing its window directly leaves the extra
/// believing it is still open, so the next click on the menu bar icon is swallowed; clicking the
/// status item's own button keeps the two in step.
@MainActor
enum MenuBarPanel {
    static func dismiss(_ panel: NSWindow?) {
        guard let panel, panel.isVisible else { return }
        if let button = statusButton() {
            button.performClick(nil)
        } else {
            panel.orderOut(nil)
        }
    }

    private static func statusButton() -> NSStatusBarButton? {
        for window in NSApp.windows {
            if let content = window.contentView, let button = find(in: content) { return button }
        }
        return nil
    }

    private static func find(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = find(in: subview) { return button }
        }
        return nil
    }
}
