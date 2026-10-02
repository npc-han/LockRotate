import AppKit
import SwiftUI

/// Colors: black, white and gray only. System controls keep the system accent color.
enum Palette {
    static let graphite = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
    static let ink = Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0B / 255)
    static let paper = Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255)
}

/// The one main action on a screen: near-black in light mode, near-white in dark mode.
struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, prominent: true, fullWidth: fullWidth)
    }
}

/// A quieter companion to `PrimaryButtonStyle`, a light gray fill that follows the color scheme.
struct SecondaryButtonStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, prominent: false, fullWidth: fullWidth)
    }
}

private struct StyledButton: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let fullWidth: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        let dark = colorScheme == .dark
        let fill: Color = prominent
            ? (dark ? Palette.paper : Palette.graphite)
            : Color.primary.opacity(isHovered ? 0.11 : 0.07)
        let text: Color = prominent ? (dark ? Palette.ink : .white) : .primary

        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(text)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 30)
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { isHovered = $0 }
    }
}

/// Text-only button with a soft hover background, for the panel's footer.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietButton(configuration: configuration)
    }
}

private struct QuietButton: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(isHovered ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.12 : (isHovered ? 0.07 : 0)),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

/// The text as it appears on the lock screen: white on a dark card, centered, under a small lock.
/// The card is dark in both appearances, like the lock screen itself.
struct LockScreenCard: View {
    let text: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }
    private var hasText: Bool { !(text ?? "").isEmpty }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .accessibilityHidden(true)

            // A ZStack lets the old and new text cross-fade in place instead of stacking.
            ZStack {
                Group {
                    if let text, hasText {
                        Text(text)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineSpacing(3)
                            .lineLimit(8)
                            .textSelection(.enabled)
                    } else {
                        Text(loc("No lock screen text yet"))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .id(text ?? "")
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(
            LinearGradient(colors: [Palette.graphite, Palette.ink], startPoint: .top, endPoint: .bottom),
            in: shape
        )
        .overlay(shape.strokeBorder(.white.opacity(0.08)))
        // Selection highlight and other system colors inside the card should match its dark look.
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.25), value: text)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(loc("Lock screen text")))
        .accessibilityValue(hasText ? Text(text ?? "") : Text(loc("No lock screen text yet")))
    }
}

/// Reports the hosting `NSWindow` once the view is in one. The reference is kept in a plain
/// holder so that setting it does not cause another SwiftUI update.
@MainActor
final class WindowReference {
    weak var window: NSWindow?
}

struct WindowReader: NSViewRepresentable {
    let reference: WindowReference

    func makeNSView(context: Context) -> NSView {
        let view = ObservingView()
        view.reference = reference
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ObservingView: NSView {
        var reference: WindowReference?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reference?.window = window
        }
    }
}
