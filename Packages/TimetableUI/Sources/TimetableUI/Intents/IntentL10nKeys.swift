// Catalog keys of the App Intents (Phase 4 B3). Intent titles, descriptions and parameter titles are
// `LocalizedStringResource` literals in the intent types (App/Sources/Intents, WidgetExtension/Sources/Intents), which
// validate_config.py's literal-key scan does not see; listing them here lets `DynamicL10nKeyTests` prove they exist in
// Resources/Localizable.xcstrings in all 12 languages. The App Shortcut phrases live in Resources/AppShortcuts.xcstrings
// (validate_config.py checks that catalog).
public enum IntentL10nKeys {
    public static let allKeys: [String] = [
        "intent.markTaskDone.title", "intent.markTaskDone.description", "intent.markExamDone.title",
        "intent.markExamDone.description", "intent.param.task", "intent.param.exam", "intent.whatsNext.title",
        "intent.whatsNext.description", "intent.whatsNext.shortTitle", "intent.addHomework.title",
        "intent.addHomework.description", "intent.addHomework.shortTitle", "intent.selectTimetable.title",
        "intent.selectTimetable.description", "intent.param.timetable", "intent.timetable.typeName",
        "intent.timetable.activeSubtitle", "widget.homework.markDone", "alarm.button.done",
    ]
}
