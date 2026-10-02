import Foundation
import LockRotateCore
import LockRotateSystem

enum ListEditError: Error, Equatable, LocalizedError {
    case empty
    case duplicate
    case indexOutOfRange

    var errorDescription: String? {
        switch self {
        case .empty: localized("The entry is empty.")
        case .duplicate: localized("This entry is already in the list.")
        case .indexOutOfRange: localized("This entry no longer exists.")
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    enum HelperOperation: Equatable {
        case installing
        case uninstalling
    }

    /// Pages in the settings window's sidebar, in display order.
    enum SettingsTab: Hashable, CaseIterable, Identifiable {
        case list, rotation, helper
        var id: Self { self }
    }

    enum ImportMode: Equatable {
        case replace
        case append
    }

    struct Banner: Equatable {
        enum Kind: Equatable { case error, notice }
        enum Action: Equatable { case installHelper, openList }

        var kind: Kind
        var text: String
        var action: Action?
    }

    static let intervalRange = 1...1440

    // MARK: State

    @Published var settings: AppSettings {
        didSet { settingsDidChange(from: oldValue) }
    }
    @Published private(set) var rotationState: RotationState
    /// nil until the first check finishes.
    @Published private(set) var helperStatus: HelperStatus?
    @Published private(set) var currentText: String?
    @Published var banner: Banner?
    @Published private(set) var isAdvancing = false
    @Published private(set) var helperOperation: HelperOperation?
    /// What the system says about the login item; the toggle in the UI follows this, not the saved flag.
    @Published private(set) var loginItemStatus: LoginItemStatus
    /// The list page by default; `start()` switches to authorization while the helper is missing.
    @Published var selectedTab: SettingsTab = .list
    /// One-line result of the last import or edit; shown in the list tab.
    @Published private(set) var listMessage: String?
    /// A parsed file waiting for the user to choose replace or append.
    @Published private(set) var pendingImport: ImportResult?

    // MARK: Dependencies

    private let settingsStore: SettingsStore
    private let stateStore: StateStore
    private let helper: any HelperControlling
    private let reader: any LockTextReading
    private let loginItem: any LoginItemControlling
    /// The last login item error shown, so a later success can take it down again.
    private var loginErrorBanner: Banner?
    private let sanitizer: TextSanitizer
    private let importer: QuoteImporter

    init(
        settingsStore: SettingsStore,
        stateStore: StateStore,
        helper: any HelperControlling,
        reader: any LockTextReading,
        loginItem: any LoginItemControlling,
        sanitizer: TextSanitizer = TextSanitizer()
    ) {
        self.settingsStore = settingsStore
        self.stateStore = stateStore
        self.helper = helper
        self.reader = reader
        self.loginItem = loginItem
        self.sanitizer = sanitizer
        self.importer = QuoteImporter(sanitizer: sanitizer)

        var loaded = settingsStore.load()
        loaded.intervalMinutes = Self.clamp(loaded.intervalMinutes)
        self.settings = loaded
        self.rotationState = stateStore.load()
        self.currentText = reader.current()
        self.loginItemStatus = loginItem.status
    }

    /// Production wiring: real helper, real reader, data in `LOCKROTATE_DATA_DIR` or Application Support.
    static func live(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppModel {
        let directory = AppEnvironment.dataDirectory(environment: environment)
        #if DEBUG
        if let preview = PreviewMode.system(environment: environment) {
            let model = AppModel(
                settingsStore: SettingsStore(directory: directory),
                stateStore: StateStore(directory: directory),
                helper: preview,
                reader: preview,
                loginItem: MainAppLoginItem()
            )
            if let page = PreviewMode.page(environment: environment) { model.selectedTab = page }
            return model
        }
        #endif
        return AppModel(
            settingsStore: SettingsStore(directory: directory),
            stateStore: StateStore(directory: directory),
            helper: HelperManager(),
            reader: LockTextReader(),
            loginItem: MainAppLoginItem()
        )
    }

    /// Settings and state load in `init`; this refreshes what needs the system.
    func start() async {
        await refreshHelperStatus()
        if helperStatus == .notInstalled { selectedTab = .helper }
        refreshCurrentText()
        refreshLoginItem()
    }

    // MARK: Derived

    var isHelperInstalled: Bool { helperStatus == .installed }
    var showsInstallHelper: Bool { helperStatus == .notInstalled }
    var isBusy: Bool { isAdvancing || helperOperation != nil }

    /// 1-based position of the text on the lock screen in the list, or nil when it is not from the list.
    var currentPosition: Int? {
        guard let text = currentText, !text.isEmpty else { return nil }
        return settings.items.firstIndex(of: text).map { $0 + 1 }
    }

    /// Pauses the automatic triggers only; "Next" always works. Saved with the settings.
    var isPaused: Bool {
        get { settings.paused }
        set { settings.paused = newValue }
    }

    // MARK: Rotation

    /// Manual "Next": every problem is shown to the user.
    func advance() async {
        await advance(automatic: false)
    }

    /// Called by the automatic triggers. Stays quiet when there is nothing to do: paused, empty list,
    /// or helper not installed (then `helperStatus` becomes `.notInstalled`, which is what makes the
    /// menu offer "Install helper…"; no error is raised for every tick).
    func advanceAutomatically() async {
        guard !settings.paused, !isAdvancing, !settings.items.isEmpty else { return }
        if helperStatus != .installed {
            await refreshHelperStatus()
            guard helperStatus == .installed else { return }
        }
        await advance(automatic: true)
    }

    /// Picks the next entry, writes it through the helper, and only then commits the rotation state.
    private func advance(automatic: Bool) async {
        guard !isAdvancing else { return }
        guard !settings.items.isEmpty else {
            banner = Banner(kind: .notice, text: localized("The list is empty. Import a list first."), action: .openList)
            return
        }

        isAdvancing = true
        defer { isAdvancing = false }

        var rotator = Rotator(state: rotationState)
        guard let text = rotator.next(items: settings.items, mode: settings.mode) else { return }

        do {
            try await helper.setLockText(text)
        } catch let error as SystemError where automatic && error == .helperNotInstalled {
            // The helper disappeared since the last check; just remember it.
            helperStatus = .notInstalled
            return
        } catch {
            show(error)
            return
        }

        helperStatus = .installed
        rotationState = rotator.state
        do {
            try stateStore.save(rotationState)
            banner = nil
        } catch {
            banner = Banner(
                kind: .error,
                text: localized("Couldn't save the rotation state: \(error.localizedDescription)"),
                action: nil
            )
        }
        currentText = reader.current() ?? text
    }

    func refreshCurrentText() {
        currentText = reader.current()
    }

    // MARK: Helper

    func refreshHelperStatus() async {
        helperStatus = await helper.status()
    }

    func installHelper() async {
        await runHelperOperation(.installing) { try await $0.install() }
    }

    func uninstallHelper() async {
        await runHelperOperation(.uninstalling) { try await $0.uninstall() }
    }

    private func runHelperOperation(
        _ operation: HelperOperation,
        _ body: (any HelperControlling) async throws -> Void
    ) async {
        guard helperOperation == nil else { return }
        helperOperation = operation
        defer { helperOperation = nil }
        do {
            try await body(helper)
            if banner?.action == .installHelper { banner = nil }
        } catch let error as SystemError where error == .userCancelled {
            // The user closed the password prompt; that is not a failure.
        } catch {
            show(error)
        }
        await refreshHelperStatus()
        refreshCurrentText()
    }

    private func show(_ error: Error) {
        let text = error.localizedDescription
        if let system = error as? SystemError, system == .helperNotInstalled {
            helperStatus = .notInstalled
            banner = Banner(kind: .error, text: text, action: .installHelper)
        } else {
            banner = Banner(kind: .error, text: text, action: nil)
        }
    }

    func dismissBanner() { banner = nil }

    // MARK: Login item

    /// The toggle shows "on" while the item is enabled or waiting for the user's approval.
    var isLoginItemOn: Bool { Self.isOn(loginItemStatus) }
    var loginItemNeedsApproval: Bool { loginItemStatus == .requiresApproval }

    private static func isOn(_ status: LoginItemStatus) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    /// Reads the real state and makes the saved flag agree with it.
    func refreshLoginItem() {
        loginItemStatus = loginItem.status
        let on = Self.isOn(loginItemStatus)
        if settings.triggers.login != on { settings.triggers.login = on }
    }

    func setLoginItem(enabled: Bool) {
        do {
            if enabled {
                if loginItem.status != .enabled { try loginItem.register() }
            } else if Self.isOn(loginItem.status) {
                try loginItem.unregister()
            }
            if let shown = loginErrorBanner, banner == shown { banner = nil }
            loginErrorBanner = nil
        } catch {
            let failure = Banner(
                kind: .error,
                text: localized("Couldn't change launch at login: \(error.localizedDescription)"),
                action: nil
            )
            loginErrorBanner = failure
            banner = failure
        }
        // Whatever happened, the switch ends up showing the truth (a failed register bounces back to off).
        refreshLoginItem()
    }

    func openLoginItemsSettings() { loginItem.openSystemSettings() }

    // MARK: List editing

    /// Cleans `raw`, rejects empty text and duplicates. `replacing` is the index being edited.
    private func cleanedEntry(_ raw: String, replacing index: Int?) throws -> TextSanitizer.Cleaned {
        guard let cleaned = sanitizer.clean(raw) else { throw ListEditError.empty }
        let clash = settings.items.firstIndex(of: cleaned.text)
        if let clash, clash != index { throw ListEditError.duplicate }
        return cleaned
    }

    func addItem(_ raw: String) throws {
        let cleaned = try cleanedEntry(raw, replacing: nil)
        settings.items.append(cleaned.text)
        listMessage = cleaned.wasTruncated ? localized("The entry was shortened to fit the lock screen.") : nil
    }

    func updateItem(at index: Int, to raw: String) throws {
        guard settings.items.indices.contains(index) else { throw ListEditError.indexOutOfRange }
        let cleaned = try cleanedEntry(raw, replacing: index)
        settings.items[index] = cleaned.text
        listMessage = cleaned.wasTruncated ? localized("The entry was shortened to fit the lock screen.") : nil
    }

    func removeItems(_ texts: Set<String>) {
        guard !texts.isEmpty else { return }
        settings.items.removeAll { texts.contains($0) }
        listMessage = nil
    }

    // MARK: Import

    /// Parses a file. An empty list takes the result directly; otherwise the user chooses replace or append.
    func loadImport(from url: URL) {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            banner = Banner(
                kind: .error,
                text: localized("Couldn't read the file: \(error.localizedDescription)"),
                action: nil
            )
            return
        }
        stageImport(data: data, filename: url.lastPathComponent)
    }

    func stageImport(data: Data, filename: String?) {
        let result: ImportResult
        do {
            result = try importer.importData(data, filename: filename)
        } catch {
            banner = Banner(kind: .error, text: error.localizedDescription, action: nil)
            return
        }
        if settings.items.isEmpty {
            applyImport(result, mode: .replace)
        } else {
            pendingImport = result
        }
    }

    func cancelImport() { pendingImport = nil }

    func applyImport(_ result: ImportResult, mode: ImportMode) {
        pendingImport = nil
        banner = banner?.kind == .error ? nil : banner

        var added = result.items.count
        var duplicates = result.duplicatesRemoved
        switch mode {
        case .replace:
            settings.items = result.items
        case .append:
            // Deduplicate the whole list again; earlier entries win.
            let merged = sanitizer.sanitize(settings.items + result.items)
            added = merged.items.count - settings.items.count
            duplicates += result.items.count - added
            settings.items = merged.items
        }
        listMessage = Self.importSummary(
            added: added,
            skippedEmpty: result.skippedEmpty,
            truncated: result.truncated,
            duplicates: duplicates
        )
    }

    static func importSummary(added: Int, skippedEmpty: Int, truncated: Int, duplicates: Int) -> String {
        var parts = [localized("Imported \(added) entries.")]
        if skippedEmpty > 0 { parts.append(localized("Skipped \(skippedEmpty) empty.")) }
        if truncated > 0 { parts.append(localized("Shortened \(truncated) to fit.")) }
        if duplicates > 0 { parts.append(localized("Removed \(duplicates) duplicates.")) }
        return parts.joined(separator: localized("summary.separator"))
    }

    // MARK: Settings

    private static func clamp(_ minutes: Int) -> Int {
        min(max(minutes, intervalRange.lowerBound), intervalRange.upperBound)
    }

    private func settingsDidChange(from old: AppSettings) {
        let clamped = Self.clamp(settings.intervalMinutes)
        if clamped != settings.intervalMinutes { settings.intervalMinutes = clamped }
        guard settings != old else { return }
        do {
            try settingsStore.save(settings)
        } catch {
            banner = Banner(
                kind: .error,
                text: localized("Couldn't save settings: \(error.localizedDescription)"),
                action: nil
            )
        }
    }
}
