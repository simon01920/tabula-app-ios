// App Preview capture shots (CI only: .github/workflows/app-preview-capture.yml records the simulator screen with
// `simctl io recordVideo` around each test). One test per shot; real app binary, real taps, no debug routes standing in
// for a flow (S8 uses real view routes on purpose). Calm, human pacing: the clips are edited later.
// Not part of the xtool/SwiftPM path (Package.swift, xtool.yml): XcodeGen target `TabulaPreviewCapture` only.
// Env (xcodebuild passes TEST_RUNNER_<NAME> to the runner as <NAME>): TABULA_SEED (default "preview").
import XCTest

@MainActor
final class PreviewCaptureTests: XCTestCase {
    private var seed: String { ProcessInfo.processInfo.environment["TABULA_SEED"] ?? "preview" }

    // MARK: Shots

    func test_S1_today_to_week() {
        let app = launch()
        wait(app.tabBars.buttons["Today"], app)
        hold(3)
        tab("Timetable", app)
        wait(app.buttons.matching(NSPredicate(format: "label CONTAINS 'period'")).firstMatch, app)
        hold(3.5)
    }

    /// The workflow adds video/assets/import-source.png (phone-style photo) to Photos before this test.
    func test_S2_photo_import() { photoImport() }

    /// Same as S2; the workflow adds video/assets/import-source-flat.png instead (does Vision read the flat sheet?).
    func test_S2b_photo_import_flat() { photoImport() }

    private func photoImport() {
        // previewBlank: English empty start (Class 11B, same bells, London, Tue 10 Nov 10:20).
        let app = launch(seed: "previewBlank")
        wait(app.tabBars.buttons["Today"], app)
        hold(1.5)
        tab("Timetable", app)
        hold(1.5)
        tap(app.buttons["View Options"], app)
        hold(1)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Import from Photo'")).firstMatch, app)
        hold(2)
        tap(app.buttons["Choose Photo"], app)
        hold(2.5)
        // The PHPicker grid runs out of process and is not in the app's accessibility tree (run 41748424916: only the
        // app's own "photo.on.rectangle" icon matched). shortcut: a real tap at the first grid cell (newest first = the
        // `simctl addmedia` photo, below the "Private Access to Photos" card of a fresh simulator, 440x956 pt);
        // upgrade if the picker layout changes.
        // The picker shows "Loading…" for ~5–10 s on a fresh simulator (run 41756161098): tap once the grid is up.
        hold(12)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 72, dy: 388)).tap()
        let add = app.buttons["Add"]
        if add.waitForExistence(timeout: 2) { add.tap() }
        // Processing → review ("Check Timetable"). Vision on the simulator can take a while.
        wait(app.buttons["Approve"], app, timeout: 150)
        hold(3)
        tap(app.buttons["Approve"], app)
        hold(2)
        tap(app.buttons["Add as New Timetable"], app)
        wait(app.tabBars.buttons["Timetable"], app)
        hold(3)
    }

    func test_S3_lesson_homework() {
        let app = launch()
        wait(app.tabBars.buttons["Today"], app)
        hold(1.5)
        tab("Timetable", app)
        hold(2)
        // "Finish algebra exercises" is due for Wednesday's first Maths lesson (preview seed).
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Mathematics' AND label CONTAINS 'Wednesday' AND label CONTAINS 'period 1'")).firstMatch, app)
        hold(2)
        let task = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Finish algebra exercises'")).firstMatch
        tap(task, app)
        hold(2)
        let subtask = app.buttons.matching(NSPredicate(format: "value == 'not done'")).firstMatch
        if subtask.waitForExistence(timeout: 3) {
            subtask.tap()
            hold(2)
        } else {
            print("S3: no open subtask on the task; skipping the tick")
        }
        // Lesson detail and task detail are both sheets with a Close button: the top one is the last in the tree.
        let closes = app.buttons.matching(identifier: "Close")
        wait(closes.firstMatch, app)
        closes.element(boundBy: closes.count - 1).tap()
        hold(1.5)
        tap(app.buttons["Add Homework"], app)
        hold(1.5)
        let field = [app.textViews["Task title"], app.textFields["Task title"]].first { $0.waitForExistence(timeout: 3) }
            ?? app.textViews["Task title"]
        tap(field, app)
        for character in "Practice worksheet" {
            app.typeText(String(character))   // the field's query stops matching once it has text (run 41756161098)
            hold(0.08)
        }
        hold(1.5)
        tap(app.buttons["Save"], app)
        wait(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Practice worksheet'")).firstMatch, app)
        hold(3)
    }

    func test_S4_exam() {
        let app = launch()
        wait(app.tabBars.buttons["Today"], app)
        hold(1.5)
        tab("Exams", app)
        hold(3)
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Biology quiz'")).firstMatch, app)
        hold(2.5)
        // The reminder choice lives in the exam's editor (ReminderOverrideSection), not on the detail page.
        tap(app.navigationBars.buttons["Edit"], app)
        hold(1.5)
        let reminders = app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Reminders'")).firstMatch
        for _ in 0..<6 where !(reminders.exists && reminders.isHittable) {
            app.swipeUp(velocity: .slow)
            hold(0.8)
        }
        wait(reminders, app)
        hold(3)
        tap(app.buttons["Cancel"], app)
        hold(1.5)
    }

    func test_S5_reminders() {
        let app = launch()
        wait(app.tabBars.buttons["Today"], app)
        hold(1.5)
        tab("Settings", app)
        hold(2)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reminders'")).firstMatch, app)
        hold(2.5)
        for _ in 0..<3 {
            app.swipeUp(velocity: .slow)
            hold(2)
        }
        wait(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'loud alarm'")).firstMatch, app)
        hold(2)
    }

    /// Real store (no seed: seed runs never write the App Group snapshot or touch ActivityKit, AppEnvironment.swift),
    /// onboarding with the example timetable, then a real Home Screen widget added through SpringBoard.
    func test_S6_widgets_live() {
        let app = launch(realStore: true)
        onboardWithExample(app)
        hold(4)
        XCUIDevice.shared.press(.home)
        hold(2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["Tabula"]
        wait(icon, springboard)
        icon.press(forDuration: 1.5)
        tap(springboard.buttons["Edit Home Screen"], springboard)
        hold(1)
        tap(springboard.buttons["Edit"], springboard)
        hold(1)
        tap(springboard.buttons["Add Widget"], springboard)
        hold(1.5)
        let search = springboard.searchFields.firstMatch
        tap(search, springboard)
        search.typeText("Tabula")
        hold(1.5)
        tap(springboard.cells["Tabula"], springboard)   // not `label == 'Tabula'`: that is the Home Screen icon behind
        hold(2)
        // Label is " Add Widget" (leading glyph space, run 41756161098).
        tap(springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Add Widget'")).firstMatch, springboard)
        hold(1.5)
        tap(springboard.buttons["Done"], springboard)
        hold(5)
        print("SPRINGBOARD AFTER ADD:\n\(springboard.debugDescription)")
    }

    /// Phone side of the watch shot: real store + example timetable, kept in the foreground so WatchConnectivity sends
    /// the snapshot to the paired watch simulator (the workflow launches and records the watch app).
    func test_S7_watch() {
        let app = launch(realStore: true)
        onboardWithExample(app)
        hold(25)
    }

    func test_S8a_day() {
        let app = launch(screen: "timetable.day")
        wait(app.tabBars.buttons["Timetable"], app)
        hold(4)
    }

    func test_S8b_tiles() {
        let app = launch(screen: "timetable.tiles")
        wait(app.tabBars.buttons["Timetable"], app)
        hold(4)
    }

    // MARK: Helpers

    /// `-TabulaSeed <seed>` (default TABULA_SEED), or the real on-disk store when `realStore`.
    private func launch(seed: String? = nil, realStore: Bool = false, screen: String? = nil,
                        extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        var arguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        if !realStore { arguments = ["-TabulaSeed", seed ?? self.seed] + arguments }
        if let screen { arguments += ["-TabulaScreen", screen] }
        arguments += extra
        app.launchArguments = arguments
        print("LAUNCH ARGUMENTS: \(arguments)")
        app.launch()
        return app
    }

    private func onboardWithExample(_ app: XCUIApplication) {
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Secondary / high school'")).firstMatch, app)
        hold(1)
        tap(app.buttons["Continue"], app)
        hold(1.5)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Just look around'")).firstMatch, app)
        hold(1)
        tap(app.buttons["Open Example"], app)
        wait(app.tabBars.buttons["Today"], app, timeout: 20)
    }

    private func tab(_ name: String, _ app: XCUIApplication) {
        tap(app.tabBars.buttons[name], app)
    }

    private func hold(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    private func tap(_ element: XCUIElement, _ app: XCUIApplication, timeout: TimeInterval = 15,
                     file: StaticString = #filePath, line: UInt = #line) {
        wait(element, app, timeout: timeout, file: file, line: line)
        element.tap()
    }

    /// Waits for `element`; on timeout prints and attaches the accessibility tree (we cannot see the CI screen).
    private func wait(_ element: XCUIElement, _ app: XCUIApplication, timeout: TimeInterval = 15,
                      file: StaticString = #filePath, line: UInt = #line) {
        guard !element.waitForExistence(timeout: timeout) else { return }
        let tree = app.debugDescription
        print("HIERARCHY >>>\n\(tree)\n<<< HIERARCHY")
        add(XCTAttachment(string: tree))
        XCTFail("timed out after \(timeout) s waiting for \(element)", file: file, line: line)
    }
}
