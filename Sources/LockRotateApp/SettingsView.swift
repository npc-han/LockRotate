import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                ForEach(AppModel.SettingsTab.allCases) { tab in
                    SidebarRow(tab: tab, model: model)
                        .tag(tab)
                }
            }
            .modifier(HidesSidebarToggle())
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 260)
        } detail: {
            VStack(spacing: 0) {
                if let banner = model.banner {
                    BannerView(banner: banner, model: model)
                        .padding([.horizontal, .top], 16)
                        .padding(.bottom, 4)
                }
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(Text(model.selectedTab.title))
        }
        .frame(minWidth: 640, minHeight: 420)
        .onAppear {
            model.refreshCurrentText()
            model.refreshLoginItem()
        }
        .task { await model.refreshHelperStatus() }
        // The user may have approved the login item in System Settings and switched back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshLoginItem()
        }
    }

    @ViewBuilder
    private var page: some View {
        switch model.selectedTab {
        case .list: ListSettingsView(model: model)
        case .rotation: RotationSettingsView(model: model)
        case .helper: HelperSettingsView(model: model)
        }
    }

    /// The sidebar always has a page selected; clicking empty space does not clear it.
    private var selection: Binding<AppModel.SettingsTab?> {
        Binding(
            get: { model.selectedTab },
            set: { if let tab = $0 { model.selectedTab = tab } }
        )
    }
}

extension AppModel.SettingsTab {
    var title: LocalizedStringResource {
        switch self {
        case .list: loc("List")
        case .rotation: loc("Rotation")
        case .helper: loc("Authorization")
        }
    }

    var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .rotation: "arrow.triangle.2.circlepath"
        case .helper: "lock.shield"
        }
    }
}

private struct SidebarRow: View {
    let tab: AppModel.SettingsTab
    @ObservedObject var model: AppModel

    var body: some View {
        Label {
            HStack {
                Text(tab.title)
                Spacer()
                accessory
            }
        } icon: {
            Image(systemName: tab.symbol)
        }
    }

    @ViewBuilder
    private var accessory: some View {
        switch tab {
        case .list:
            Text(model.settings.items.count, format: .number)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(loc("\(model.settings.items.count) entries")))
        case .rotation:
            if model.isPaused {
                Image(systemName: "pause.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(loc("Paused")))
            }
        case .helper:
            if model.helperStatus == .notInstalled {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text(loc("Not authorized")))
            }
        }
    }
}

/// The sidebar holds three short items and the window is small; collapsing it only hides the
/// way back to the other pages.
private struct HidesSidebarToggle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}

struct BannerView: View {
    let banner: AppModel.Banner
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: banner.kind == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(banner.kind == .error ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)

            Text(banner.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let action = banner.action {
                switch action {
                case .installHelper:
                    Button(loc("Go to Authorization")) { model.selectedTab = .helper }
                case .openList:
                    Button(loc("Go to List")) { model.selectedTab = .list }
                }
            }

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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
    }
}
