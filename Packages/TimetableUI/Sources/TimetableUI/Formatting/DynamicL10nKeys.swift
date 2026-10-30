// Every String Catalog key the app builds at runtime from an enum value (key families). The App target must obtain
// such keys here and wrap them with `LocalizedStringKey(String)` of a variable — never with an interpolated literal
// (`LocalizedStringKey("a.\(x)")` becomes the format key "a.%@", which is not in the catalog and shows raw).
// `DynamicL10nKeyTests` enumerates `allKeys` and asserts that each exists in Resources/Localizable.xcstrings.
import Foundation
import TimetableCore

public enum DynamicL10nKeys {
    public static func profile(_ value: UserProfile) -> String { "settings.profile." + value.rawValue }
    public static func periodKind(_ value: PeriodKind) -> String { "editor.bell.kind." + value.rawValue }
    public static func breakKind(_ value: BreakKind) -> String { "editor.breaks.kind." + value.rawValue }
    public static func rotationKind(_ value: TimetableDraft.RotationKind) -> String { "editor.rotation.kind." + value.rawValue }
    public static func lessonField(_ value: LessonField) -> String { "editor.field." + value.rawValue }
    public static func defaultView(_ value: TimetableViewKind) -> String { "editor.view." + value.rawValue }
    public static func reminderTarget(_ value: ReminderTarget) -> String { "onboarding.reminders.target." + value.rawValue }
    public static func examKind(_ value: ExamKind) -> String { "exams.kind." + value.rawValue }
    /// Name of an attachment kind (stage B3); unknown kinds (newer app versions) → "Attachment".
    public static func attachmentKind(_ value: AttachmentKind) -> String {
        AttachmentKind.knownValues.contains(value) ? "attachments.kind." + value.rawValue : "attachments.kind.unknown"
    }
    /// Catalog key of a lesson field's name in the lesson detail list (`LessonDetailView`).
    public static func lessonDetailField(_ field: LessonField) -> String {
        switch field {
        case .room: return "timetable.detail.field.room"
        case .building: return "timetable.detail.field.building"
        case .teacher: return "timetable.detail.field.teacher"
        case .lessonType: return "timetable.detail.field.lessonType"
        case .notes: return "timetable.detail.field.notes"
        default: return "timetable.detail.field.bringList"
        }
    }

    /// Titles of the timetable-level editors listed in the options menu (`ManagementSheet.entries`).
    public static let managementTitleKeys: [String] = [
        "editor.timetable.title", "editor.bell.title", "editor.subjects.title", "editor.terms.title",
    ]

    /// `base` + the profile's terminology suffix (selects between two complete catalog strings).
    public static func term(_ base: String, _ terminology: ProfilePreset.Terminology) -> String {
        base + "." + terminology.rawValue
    }

    /// Bases passed to `term(_:_:)` by the onboarding screens.
    public static let termBases: [String] = [
        "onboarding.time.title", "onboarding.time.length", "onboarding.time.firstStart", "onboarding.time.count",
        "onboarding.time.longBreak", "onboarding.time.preview.row", "onboarding.reminders.target",
    ]

    /// All keys of all families, for every possible value.
    public static var allKeys: [String] {
        var keys: [String] = []
        keys += UserProfile.knownValues.map(profile)
        keys += PeriodKind.knownValues.map(periodKind)
        keys += BreakKind.knownValues.map(breakKind)
        keys += TimetableDraft.RotationKind.allCases.map(rotationKind)
        keys += LessonField.knownValues.map(lessonField)
        keys += TimetableViewKind.knownValues.map(defaultView)
        keys += ReminderTarget.knownValues.map(reminderTarget)
        keys += ExamKind.knownValues.map(examKind)
        keys += ExamWhen.allKeys
        keys += ExamDraft.Issue.allCases.map(\.l10nKey)
        for base in termBases {
            keys += ProfilePreset.Terminology.allCases.map { term(base, $0) }
        }
        // Keys produced by model types.
        keys += TimetableViewKind.knownValues.map(TimetableViewChoice.nameKey)
        keys += DayChangeDraft.Kind.allCases.map(\.l10nKey)
        keys += DayChangeDraft.Issue.allCases.map(\.l10nKey)
        keys += SlotDraft.Issue.allCases.map(\.l10nKey)
        keys += LessonDraft.Issue.allCases.map(\.l10nKey)
        keys += SubjectDraft.Issue.allCases.map(\.l10nKey)
        keys += TimetableDraft.Issue.allCases.map(\.l10nKey)
        keys += ProfilePreset.Terminology.allCases.map(\.l10nKey)
        keys += ProfileChoices.offered.map(ProfileChoices.terminologyKey(for:))
        keys += LessonField.knownValues.map(lessonDetailField)
        keys += managementTitleKeys
        // Known lesson types only: an unknown type has no key and shows its raw text (user / newer-version data).
        keys += LessonType.knownValues.compactMap(VisibleLessonFields.nameKey(of:))
        keys += CycleLabel.allCatalogKeys
        keys += QuickAddScope.allCatalogKeys   // Phase 4U U4
        keys += TimetableSubtitle.catalogKeys
        keys += TodayHeroText.catalogKeys   // Phase 4U U3
        keys += ReminderUIKeys.allKeys
        keys += ReminderRuleDefaults.targets.map { ReminderKindList.titleKey($0, terminology: .classLecture) }
        keys += IntentL10nKeys.allKeys   // Phase 4 B3: App Intent titles / parameters, checkbox + alarm "Done"
        keys += TaskL10nKeys.allKeys
        keys += AttachmentKind.knownValues.map(attachmentKind) + [attachmentKind(AttachmentKind(rawValue: "future"))]
        keys += widgetKeys
        keys += liveActivityKeys
        keys += ModificationReason.allCases.map(\.l10nKey)
        return Array(Set(keys)).sorted()
    }

    /// Keys the widget presenter (`NowNextPresenter`) picks at runtime by state; looked up through the widget's
    /// renderer in the app's language (Phase 4 A).
    public static let widgetKeys: [String] = [
        "today.header.now", "today.header.next", "today.header.first", "today.header.nextLesson",
        "today.header.timeLeft", "today.header.startsIn", "today.header.dayOver", "today.header.free",
        "today.header.holiday", "today.header.dayCancelled", "today.header.nothingAhead", "today.header.tomorrow",
        "today.header.dayAndTime", "a11y.separator", "a11y.lesson.time", "a11y.lesson.room", "a11y.lesson.cancelled",
        "a11y.lesson.added", "a11y.lesson.modified", "a11y.lesson.modifiedReasons", "lesson.status.cancelled",
        "lesson.status.added", "lesson.status.modified", "widget.nowNext.nextShort", "widget.nowNext.later",
        "widget.nowNext.a11y.endsAt", "widget.nowNext.a11y.startsAt", "widget.open.title", "widget.open.noTimetable",
        "widget.open.noSnapshot", "widget.open.outdated", "widget.pro.title", "widget.pro.short",
        // Phase 4 B1 (Today / Homework / Next exam presenters; the due phrases `tasks.due.*`, `exams.when.*` and the
        // priority sentences are in their own families above).
        "shell.tab.today", "today.section.tomorrow", "today.section.dueToday", "widget.today.dueTomorrow",
        "widget.homework.name", "widget.homework.count", "widget.homework.allDone.title",
        "widget.homework.allDone.detail", "widget.homework.overdue", "widget.more", "widget.exam.name",
        "widget.exam.inProgress", "widget.exam.finished", "widget.exam.empty.detail", "exams.empty.upcoming.title",
        "exams.a11y.room", "a11y.task.overdue", "a11y.task.due", "widget.separator",
        // The interpolated `Text` key of NowNextInlineView (subject + live timer); validate.sh skips interpolated keys.
        "widget.nowNext.inline.current %@ %@",
        // Phase 4U U7: time-first Lock Screen text, countdown units and durations (WidgetCountdown.swift).
        "widget.dayOver", "widget.nowNext.inline.next", "widget.countdown.left", "widget.countdown.untilStart",
        "widget.countdown.leftPhrase", "widget.countdown.inPhrase", "widget.duration.min", "widget.duration.h",
        "widget.duration.hm",
    ]

    /// Keys the Live Activity presenter and planner (`LiveActivityPresenter`, `LiveActivityPlanner` alerts) pick at
    /// runtime, looked up in the app's language (Phase 4 B2). The Today header / widget keys they share are listed in
    /// `widgetKeys`.
    public static let liveActivityKeys: [String] = [
        "liveActivity.exam.today", "liveActivity.exam.inProgress", "liveActivity.exam.finished", "liveActivity.alert.at",
        "today.header.first", "today.header.dayOver", "widget.nowNext.nextShort", "widget.nowNext.a11y.endsAt",
        "widget.nowNext.a11y.startsAt", "widget.dayOver", "widget.countdown.left", "widget.countdown.untilStart",
        "widget.countdown.leftPhrase", "widget.countdown.inPhrase", "widget.duration.min", "widget.duration.h",
        "widget.duration.hm",
    ]
}
