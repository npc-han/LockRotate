import Foundation

public struct TriggerSettings: Codable, Equatable, Sendable {
    public var timer: Bool
    public var wake: Bool
    public var unlock: Bool
    public var login: Bool

    public init(timer: Bool = true, wake: Bool = true, unlock: Bool = true, login: Bool = false) {
        self.timer = timer
        self.wake = wake
        self.unlock = unlock
        self.login = login
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TriggerSettings()
        timer = try c.decodeIfPresent(Bool.self, forKey: .timer) ?? d.timer
        wake = try c.decodeIfPresent(Bool.self, forKey: .wake) ?? d.wake
        unlock = try c.decodeIfPresent(Bool.self, forKey: .unlock) ?? d.unlock
        login = try c.decodeIfPresent(Bool.self, forKey: .login) ?? d.login
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let defaultIntervalMinutes = 30

    public var items: [String]
    public var mode: PlaybackMode
    public var intervalMinutes: Int
    public var triggers: TriggerSettings
    /// Pauses the automatic triggers; the manual "Next" action still works.
    public var paused: Bool

    public init(
        items: [String] = [],
        mode: PlaybackMode = .sequential,
        intervalMinutes: Int = AppSettings.defaultIntervalMinutes,
        triggers: TriggerSettings = TriggerSettings(),
        paused: Bool = false
    ) {
        self.items = items
        self.mode = mode
        self.intervalMinutes = max(1, intervalMinutes)
        self.triggers = triggers
        self.paused = paused
    }

    // Missing keys fall back to defaults so files written by older versions keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        self.init(
            items: try c.decodeIfPresent([String].self, forKey: .items) ?? d.items,
            mode: try c.decodeIfPresent(PlaybackMode.self, forKey: .mode) ?? d.mode,
            intervalMinutes: try c.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? d.intervalMinutes,
            triggers: try c.decodeIfPresent(TriggerSettings.self, forKey: .triggers) ?? d.triggers,
            paused: try c.decodeIfPresent(Bool.self, forKey: .paused) ?? d.paused
        )
    }
}
