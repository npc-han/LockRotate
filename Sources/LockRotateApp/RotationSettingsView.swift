import LockRotateCore
import SwiftUI

struct RotationSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            if model.isPaused {
                Section {
                    HStack {
                        Label(loc("Automatic rotation is paused"), systemImage: "pause.circle")
                        Spacer()
                        Button(loc("Resume")) { model.isPaused = false }
                    }
                }
            }

            Section {
                Picker(loc("Order"), selection: $model.settings.mode) {
                    Text(loc("In order")).tag(PlaybackMode.sequential)
                    Text(loc("Shuffle")).tag(PlaybackMode.random)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(loc(model.settings.mode == .sequential
                    ? "Goes through the list from top to bottom, then starts over."
                    : "Plays every entry once in random order, then shuffles again. The same entry never shows twice in a row."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle(loc("On a timer"), isOn: $model.settings.triggers.timer)

                if model.settings.triggers.timer {
                    LabeledContent {
                        HStack(spacing: 6) {
                            TextField("", value: $model.settings.intervalMinutes, format: .number)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .frame(width: 56)
                                .accessibilityLabel(Text(loc("Minutes between rotations")))

                            Stepper("", value: $model.settings.intervalMinutes, in: AppModel.intervalRange)
                                .labelsHidden()
                                .accessibilityLabel(Text(loc("Minutes between rotations")))

                            Text(loc("min"))
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Text(loc("Every"))
                    }
                }

                Toggle(loc("When the Mac wakes"), isOn: $model.settings.triggers.wake)
                Toggle(loc("When I unlock the screen"), isOn: $model.settings.triggers.unlock)
            } header: {
                Text(loc("When to rotate"))
            } footer: {
                Text(loc("“Next” in the menu bar works any time, even while paused."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    loc("Open LockRotate at login"),
                    isOn: Binding(
                        get: { model.isLoginItemOn },
                        set: { model.setLoginItem(enabled: $0) }
                    )
                )

                if model.loginItemNeedsApproval {
                    HStack(alignment: .firstTextBaseline) {
                        Text(loc("Needs approval in System Settings → General → Login Items."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(loc("Open Login Items Settings")) {
                            model.openLoginItemsSettings()
                        }
                        .controlSize(.small)
                    }
                }
            } header: {
                Text(loc("General"))
            }
        }
        .formStyle(.grouped)
        .animation(.easeOut(duration: 0.2), value: model.settings.triggers.timer)
        .animation(.easeOut(duration: 0.2), value: model.isPaused)
    }
}
