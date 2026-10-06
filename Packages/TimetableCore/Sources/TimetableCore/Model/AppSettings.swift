import Foundation

/// App-wide settings. Exactly one live instance exists, always with `AppSettings.singletonID`, so that
/// settings created independently on two devices merge field by field instead of duplicating.
public struct AppSettings: SyncEntity {
    public typealias ID = EntityID<AppSettings>
    public static let entityType: EntityType = .settings

    /// The fixed identifier of the settings entity on every device.
    public static let singletonID = ID(UUID(uuidString: "7AB01A00-5E77-4000-8000-000000000001")!)

    /// Always `singletonID`.
    public var id: ID
    /// Sync metadata.
    public var meta: EntityMeta
    /// Who the user is (drives presets; changeable later).
    public var profile: UserProfile
    /// When onboarding finished; `nil` = onboarding not completed.
    public var onboardingCompletedAt: Date?
    /// Timetable shown at launch.
    public var activeTimetableID: Timetable.ID?
    /// Week start; `nil` = the locale's first weekday.
    public var weekStartOverride: Weekday?
    /// 12/24 h preference.
    public var hourCycle: HourCycle
    /// Device-following or fixed time zone.
    public var timeZoneMode: TimeZoneMode
    /// Light/dark/auto.
    public var appearance: Appearance
    /// Default palette pack.
    public var palettePackID: PalettePackID
    /// Quiet hours for every rule.
    public var globalQuietHours: QuietHours?
    /// Time Sensitive delivery policy.
    public var timeSensitivePolicy: TimeSensitivePolicy
    /// Loud alarm (AlarmKit) policy.
    public var alarmPolicy: AlarmPolicy
    /// iCloud sync switch (default on).
    public var syncEnabled: Bool

    /// Creates settings. `id` defaults to `singletonID`.
    public init(id: ID = AppSettings.singletonID, meta: EntityMeta, profile: UserProfile = .other,
                onboardingCompletedAt: Date? = nil, activeTimetableID: Timetable.ID? = nil,
                weekStartOverride: Weekday? = nil, hourCycle: HourCycle = .auto,
                timeZoneMode: TimeZoneMode = .followDevice, appearance: Appearance = .auto,
                palettePackID: PalettePackID = .classic, globalQuietHours: QuietHours? = nil,
                timeSensitivePolicy: TimeSensitivePolicy = TimeSensitivePolicy(),
                alarmPolicy: AlarmPolicy = AlarmPolicy(), syncEnabled: Bool = true) {
        self.id = id
        self.meta = meta
        self.profile = profile
        self.onboardingCompletedAt = onboardingCompletedAt
        self.activeTimetableID = activeTimetableID
        self.weekStartOverride = weekStartOverride
        self.hourCycle = hourCycle
        self.timeZoneMode = timeZoneMode
        self.appearance = appearance
        self.palettePackID = palettePackID
        self.globalQuietHours = globalQuietHours
        self.timeSensitivePolicy = timeSensitivePolicy
        self.alarmPolicy = alarmPolicy
        self.syncEnabled = syncEnabled
    }
}

/// Time Sensitive notification policy. JSON: `{"isEnabled":true,"maxLeadMinutes":60}`.
public struct TimeSensitivePolicy: Hashable, Sendable, Codable {
    /// `false` = every Time Sensitive request is delivered as standard.
    public var isEnabled: Bool
    /// Reminders with a longer lead time than this are downgraded to standard (default 60; decision D6).
    public var maxLeadMinutes: Int

    /// Creates a policy.
    public init(isEnabled: Bool = true, maxLeadMinutes: Int = 60) {
        self.isEnabled = isEnabled
        self.maxLeadMinutes = maxLeadMinutes
    }
}

/// Loud alarm (AlarmKit) policy. JSON: `{"allowsPresetRules":false,"isEnabled":false}`.
public struct AlarmPolicy: Hashable, Sendable, Codable {
    /// The user opted in to loud alarms (separate AlarmKit authorisation). Default off.
    public var isEnabled: Bool
    /// Whether preset rules may produce alarms. Default `false`: alarms only from user rules (decision D7).
    public var allowsPresetRules: Bool

    /// Creates a policy.
    public init(isEnabled: Bool = false, allowsPresetRules: Bool = false) {
        self.isEnabled = isEnabled
        self.allowsPresetRules = allowsPresetRules
    }
}
