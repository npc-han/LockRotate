import SwiftUI

struct HelperSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 14) {
                    statusIcon
                        .font(.system(size: 26, weight: .regular))
                        .frame(width: 34)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)

                    Spacer(minLength: 12)

                    // The button keeps its full title; the text beside it wraps instead.
                    action
                        .fixedSize()
                }
                .padding(.vertical, 6)
            }

            Section {
                StepRow(text: loc("You enter your administrator password once, in the standard macOS prompt."), symbol: "key")
                StepRow(text: loc("LockRotate installs a small helper that can only change the lock screen text."), symbol: "checkmark.shield")
                StepRow(text: loc("Removing authorization deletes the helper and clears the lock screen text."), symbol: "arrow.uturn.backward")
            } header: {
                Text(loc("How it works"))
            }
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch model.helperStatus {
        case .installed?:
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.primary)
        case .notInstalled?:
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
        case nil:
            Image(systemName: "shield")
                .foregroundStyle(.tertiary)
        }
    }

    private var title: LocalizedStringResource {
        switch model.helperStatus {
        case .installed?: loc("Authorized")
        case .notInstalled?: loc("Not authorized yet")
        case nil: loc("Checking…")
        }
    }

    private var subtitle: LocalizedStringResource {
        switch model.helperStatus {
        case .installed?: loc("LockRotate can change the lock screen text.")
        case .notInstalled?: loc("Authorize once so LockRotate can change the lock screen text.")
        case nil: loc("Looking for the helper…")
        }
    }

    @ViewBuilder
    private var action: some View {
        if let operation = model.helperOperation {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(loc(operation == .installing ? "Authorizing…" : "Removing…"))
                    .foregroundStyle(.secondary)
            }
        } else {
            switch model.helperStatus {
            case .installed?:
                Button(loc("Remove authorization…")) {
                    Task { await model.uninstallHelper() }
                }
                .buttonStyle(SecondaryButtonStyle())
            case .notInstalled?:
                Button(loc("Authorize…")) {
                    Task { await model.installHelper() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            case nil:
                EmptyView()
            }
        }
    }
}

/// A line in "How it works". Form rows otherwise keep a label to one line and cut it off in a
/// narrow window.
private struct StepRow: View {
    let text: LocalizedStringResource
    let symbol: String

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        .padding(.vertical, 3)
    }
}
