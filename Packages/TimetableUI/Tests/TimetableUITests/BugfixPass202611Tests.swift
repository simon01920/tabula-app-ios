// Regression tests of the 2026-11 QA bug fix pass (branch wip/bugfix-2026-11).
import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

@Suite("Bug fix pass 2026-11")
struct BugfixPass202611Tests {
    /// Fix 2: "Change for This Day" on a cancelled lesson must not preselect it (saving a change would undo the cancel).
    @Test func cancelledTappedLessonIsNotPreselected() {
        let tapped = Lesson.ID(UUID()), other = Lesson.ID(UUID())
        #expect(DayChangeDraft.preselectedLesson(tapped, available: [other, tapped]) == tapped)
        #expect(DayChangeDraft.preselectedLesson(tapped, available: [other]) == nil, "cancelled that day")
        #expect(DayChangeDraft.preselectedLesson(nil, available: [other, tapped]) == other)
        #expect(DayChangeDraft.preselectedLesson(nil, available: []) == nil)
    }
}
