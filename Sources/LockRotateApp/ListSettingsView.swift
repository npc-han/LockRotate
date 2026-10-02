import AppKit
import LockRotateCore
import SwiftUI
import UniformTypeIdentifiers

struct ListSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selection = Set<String>()
    @State private var editor: EntryEditorTarget?
    @State private var showsFormatHelp = false

    var body: some View {
        Group {
            if model.settings.items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    chooseFile()
                } label: {
                    Label(loc("Import list…"), systemImage: "square.and.arrow.down")
                }
                .help(Text(loc("Import list…")))

                Button {
                    editor = EntryEditorTarget(index: nil, text: "")
                } label: {
                    Label(loc("Add entry…"), systemImage: "plus")
                }
                .help(Text(loc("Add entry…")))
            }
        }
        .sheet(item: $editor) { target in
            EntryEditor(model: model, target: target)
        }
        .confirmationDialog(
            Text(loc("Import into a list that already has entries")),
            isPresented: Binding(
                get: { model.pendingImport != nil },
                set: { if !$0 { model.cancelImport() } }
            ),
            titleVisibility: .visible,
            presenting: model.pendingImport
        ) { result in
            Button(loc("Replace current list")) { model.applyImport(result, mode: .replace) }
            Button(loc("Append to end")) { model.applyImport(result, mode: .append) }
            Button(loc("Cancel"), role: .cancel) { model.cancelImport() }
        } message: { result in
            Text(loc("The file has \(result.items.count) entries. Replace the current list, or add them to the end?"))
        }
    }

    // MARK: Pieces

    private var list: some View {
        List(selection: $selection) {
            ForEach(Array(model.settings.items.enumerated()), id: \.element) { index, item in
                EntryRow(
                    number: index + 1,
                    text: item,
                    isShowing: item == model.currentText,
                    edit: { editor = EntryEditorTarget(index: index, text: item) },
                    delete: { delete([item]) }
                )
                .tag(item)
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count == 1, let id = ids.first, let target = target(forText: id) {
                Button(loc("Edit…")) { editor = target }
            }
            if !ids.isEmpty {
                Button(loc("Delete"), role: .destructive) { delete(ids) }
            }
        } primaryAction: { ids in
            if ids.count == 1, let id = ids.first, let target = target(forText: id) {
                editor = target
            }
        }
        .onDeleteCommand { delete(selection) }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.quote")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(loc("Your list is empty"))
                    .font(.title3.weight(.semibold))
                Text(loc("Import a text or JSON file, or add entries one at a time."))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button(loc("Import list…")) { chooseFile() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                Button(loc("Add entry…")) {
                    editor = EntryEditorTarget(index: nil, text: "")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Button(loc("Which files work?")) { showsFormatHelp.toggle() }
                .buttonStyle(.link)
                .font(.callout)
                .popover(isPresented: $showsFormatHelp, arrowEdge: .bottom) {
                    FormatHelp()
                }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Entry count on the left, the result of the last import or edit after it.
    private var statusBar: some View {
        HStack(spacing: 6) {
            Text(loc("\(model.settings.items.count) entries"))
                .monospacedDigit()
            if let message = model.listMessage {
                Text(verbatim: "·")
                Text(message)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(message)
            }
            Spacer(minLength: 8)
            if !model.settings.items.isEmpty {
                Button {
                    showsFormatHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .help(Text(loc("File format help")))
                .accessibilityLabel(Text(loc("File format help")))
                .popover(isPresented: $showsFormatHelp, arrowEdge: .top) {
                    FormatHelp()
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: Actions

    private func target(forText text: String) -> EntryEditorTarget? {
        model.settings.items.firstIndex(of: text).map { EntryEditorTarget(index: $0, text: text) }
    }

    private func delete(_ texts: Set<String>) {
        model.removeItems(texts)
        selection.subtract(texts)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = localized("Choose a .txt or .json list to import")
        panel.prompt = localized("Import")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.loadImport(from: url)
    }
}

/// One list entry: its number, the text, a tag on the one on the lock screen, and edit/delete
/// buttons that show while the pointer is over the row.
private struct EntryRow: View {
    let number: Int
    let text: String
    let isShowing: Bool
    let edit: () -> Void
    let delete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number, format: .number)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(minWidth: 22, alignment: .trailing)
                .accessibilityHidden(true)

            Text(text)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isShowing {
                Label(loc("On lock screen"), systemImage: "lock.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                    .fixedSize()
            }

            // Kept in the layout (only faded) so rows do not shift on hover, and still reachable
            // with VoiceOver and the keyboard.
            HStack(spacing: 2) {
                Button(action: edit) {
                    Image(systemName: "pencil")
                }
                .help(Text(loc("Edit…")))
                .accessibilityLabel(Text(loc("Edit…")))

                Button(action: delete) {
                    Image(systemName: "trash")
                }
                .help(Text(loc("Delete")))
                .accessibilityLabel(Text(loc("Delete")))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

private struct FormatHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("Text file (.txt)")).font(.headline)
            Text(loc("One entry per line. Write \\n inside a line for a line break. Lines that start with # are comments."))
            Text(loc("JSON file (.json)")).font(.headline)
                .padding(.top, 4)
            Text(loc("An array of strings, for example [\"First\", \"Second\"]."))
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 300, alignment: .leading)
        .padding(16)
    }
}

struct EntryEditorTarget: Identifiable {
    let id = UUID()
    /// nil adds a new entry at the end.
    let index: Int?
    let text: String
}

struct EntryEditor: View {
    @ObservedObject var model: AppModel
    let target: EntryEditorTarget
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var errorMessage: String?

    init(model: AppModel, target: EntryEditorTarget) {
        self.model = model
        self.target = target
        _text = State(initialValue: target.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc(target.index == nil ? "New entry" : "Edit entry"))
                .font(.title3.weight(.semibold))

            TextEditor(text: $text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(width: 400, height: 132)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12))
                )
                .accessibilityLabel(Text(loc("Entry text")))

            HStack(alignment: .firstTextBaseline) {
                Text(loc("Use line breaks for multiple lines. Long text is shortened to fit the lock screen."))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Text(verbatim: "\(characterCount) / \(limits.maxLength)")
                    .monospacedDigit()
                    .foregroundStyle(isOverLimit ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                    .accessibilityLabel(Text(loc("\(characterCount) of \(limits.maxLength) characters")))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                Spacer()
                Button(loc("Cancel"), role: .cancel) { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(loc("Save")) { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(trimmed.isEmpty)
            }
        }
        // A fixed width keeps the wrapping hint from being measured one word per line, which
        // otherwise makes the sheet far taller than its content.
        .frame(width: 400, alignment: .leading)
        .padding(22)
    }

    /// The sanitizer's defaults are what the list applies when saving.
    private var limits: TextSanitizer { TextSanitizer() }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var characterCount: Int { trimmed.count }
    private var isOverLimit: Bool {
        characterCount > limits.maxLength
            || trimmed.split(whereSeparator: \.isNewline).count > limits.maxLines
    }

    private func save() {
        do {
            if let index = target.index {
                try model.updateItem(at: index, to: text)
            } else {
                try model.addItem(text)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
