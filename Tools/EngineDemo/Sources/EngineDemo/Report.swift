import Foundation
import TimetableCore

/// Renders a `Scenario` as one self-contained HTML page (inline CSS, no scripts, no external resources).
/// Everything shown is a value returned by TimetableCore; the only things this file computes itself are
/// presentation details (English day/month names, the visual gap rows between bell periods, CSS positions
/// derived from the engine's fractions, and the approximate English rendering of catalog keys).
struct Report {
    let s: Scenario
    let catalog: StringCatalog

    private var subjectsByID: [Subject.ID: Subject] {
        Dictionary(uniqueKeysWithValues: s.db.subjects.map { ($0.id, $0) })
    }

    // MARK: - Page

    func render() -> String {
        let body = [
            banner(), glance(), onboarding(), weekGrids(), dayView(), overrides(), timeBlocks(), reminders(), share(),
            validation(), footer(),
        ].joined(separator: "\n")
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Tabula Engine Demo</title>
        <style>\(Self.css)</style>
        </head>
        <body>
        <main>
        \(body)
        </main>
        </body>
        </html>

        """
    }

    // MARK: - Sections

    private func banner() -> String {
        """
        <header class="banner" role="note">
          <p class="eyebrow">Phase 1 · TimetableCore · engine demo</p>
          <h1>Engine output rendered for inspection — <em>not the app's UI</em></h1>
          <p>This page is produced by <code>Tools/EngineDemo</code>, which runs the real <code>TimetableCore</code>
          code (public API only) on fixed sample data and prints the results as HTML. The layout, colours and
          wording here are a debugging view. The iPhone/Watch UI is built in <strong>Phase 2</strong> and will look
          different. Strings are shown as String Catalog keys; English text next to them is read from
          <code>Resources/Localizable.xcstrings</code> by this tool (\(catalog.isLoaded ? "\(catalog.count) keys loaded" : "catalog not loaded")).</p>
          <p class="facts">Fixed “now”: <strong>\(esc(instant(s.now)))</strong> · zone <code>\(esc(s.zone.identifier))</code>
          · week starts Monday · schema v\(TabulaDatabase.currentSchemaVersion) · IDs from <code>SequentialIDGenerator</code>
          · timestamps from <code>HybridLogicalClock</code>. Re-running produces the same file.</p>
        </header>
        """
    }

    private func glance() -> String {
        let nn = s.nowNext
        let current = nn.current.map { "\($0.subject.shortName ?? $0.subject.name) until \($0.endTime)" } ?? "—"
        let next = nn.next.map { "\($0.subject.shortName ?? $0.subject.name) at \($0.startTime)" } ?? "—"
        let errors = s.issues.filter { $0.severity == .error }.count
        let tiles: [(String, String, String)] = [
            ("This week", "Week \(s.thisWeek.cycleLabel ?? "?")", "cycle week \(s.thisWeek.cycleWeek.map(String.init) ?? "–") · ISO W\(s.today.isoWeek.week)"),
            ("Next week", "Week \(s.nextWeek.cycleLabel ?? "?")", "cycle week \(s.nextWeek.cycleWeek.map(String.init) ?? "–") · ISO W\(s.today.adding(days: 7).isoWeek.week)"),
            ("Now", current, nn.remaining.map { "\(minutes($0)) min remaining" } ?? stateName(nn.state)),
            ("Next", next, nn.untilNext.map { "in \(minutes($0)) min" } ?? "—"),
            ("Reminders planned", "\(s.plan.notifications.count + s.plan.alarms.count)",
             "next 14 days · \(s.plan.dropped.count) dropped · budget \(s.plannerInput.budget.available)"),
            ("Share", "\(s.shareEnvelope.compressedByteCount) B", "compressed · route \(s.shareEnvelope.route.rawValue)"),
            ("Validation", errors == 0 ? "valid" : "\(errors) errors", "\(s.issues.count) issues total"),
        ]
        let html = tiles.map { label, value, note in
            "<div class=\"tile\"><div class=\"tile-label\">\(esc(label))</div><div class=\"tile-value\">\(esc(value))</div><div class=\"tile-note\">\(esc(note))</div></div>"
        }.joined()
        return "<section class=\"tiles\" aria-label=\"At a glance\">\(html)</section>"
    }

    private func onboarding() -> String {
        let tt = s.timetable
        let preset = s.preset
        var rotation = "none"
        if case .weekCycle(let cycle) = tt.rotation {
            var anchor = ""
            switch cycle.anchor {
            case let .isoWeekParity(policy, offset): anchor = "ISO-week parity, policy <code>\(policy.rawValue)</code>, offset \(offset)"
            case let .referenceWeek(date, week): anchor = "reference week \(date) = \(week)"
            }
            rotation = "week cycle of \(cycle.length) (\(anchor)); labels \(esc((cycle.labels ?? []).joined(separator: " / ")))"
        }
        let rows: [(String, String)] = [
            ("API", "<code>OnboardingBuilder.makeInitialDatabase(answers:ids:clock:now:)</code> at \(esc(instant(s.onboardingInstant)))"),
            ("Profile", "<code>\(s.answers.profile.rawValue)</code> → <code>ProfilePreset.secondary</code>"),
            ("Timetable", "\(esc(tt.emoji ?? "")) \(esc(tt.name)) · id <code>\(tt.id)</code>"),
            ("Rotation", rotation + " · <code>rotationWeekStart</code> = \(dayName(tt.rotationWeekStart))"),
            ("Enabled days", tt.enabledDays.sorted().map(dayName).joined(separator: ", ")),
            ("Time structure", "preset bell schedule template: 8 × 45 min from 08:00, breaks 10 / 20 / 10 min → “\(esc(s.regularBell.name))”"),
            ("Visible fields (preset)", preset.visibleFields.sorted().map { "<code>\($0.rawValue)</code>" }.joined(separator: " ")),
            ("Default view", "<code>\(tt.defaultView.rawValue)</code> · exams \(preset.examProminence.rawValue) · rotation prompt \(preset.rotationPrompt.rawValue)"),
            ("Term", s.db.terms.map { "\(esc($0.name)) (\($0.range))" }.joined(separator: ", ")),
            ("Palette", "<code>PalettePack.classic</code> (\(PalettePack.classic.colors.count) colours), text colour from <code>ColorValue.preferredTextColor</code>"),
        ]
        let ruleRows = s.db.reminderRules.map { rule in
            "<tr><td><code>\(rule.target.rawValue)</code></td><td>\(rule.offsets.map(offsetText).joined(separator: "; "))</td><td>\(rule.followUp.map(followUpText) ?? "—")</td><td><code>\(rule.tier.rawValue)</code></td><td>\(rule.isEnabled ? "on" : "<span class=muted>off</span>")</td><td>\(rule.origin.rawValue)</td></tr>"
        }.joined()

        let regular = s.regularBell.lessonPeriods
        let short = s.shortBell.lessonPeriods
        let bellRows = regular.enumerated().map { index, period in
            let alt = short.first { $0.id == period.id }
            return "<tr><td>\(index + 1)</td><td>\(period.start)–\(period.end)</td><td>\(period.durationMinutes) min</td><td>\(alt.map { "\($0.start)–\($0.end)" } ?? "—")</td><td><code class=small>\(period.id.uuidString.suffix(12))</code></td></tr>"
        }.joined()

        let subjectRows = s.db.subjects.map { subject -> String in
            let text = subject.color.preferredTextColor
            let ratio = Contrast.ratio(text, subject.color)
            let aa = Contrast.meetsAA(foreground: text, background: subject.color)
            var colourName = "—"
            if case .key(let key)? = subject.colorName { colourName = "<code>\(esc(key))</code>" }
            var emoji = ""
            if case .emoji(let value)? = subject.symbol { emoji = value }
            return """
            <tr><td><span class="swatch" style="background:\(subject.color.hexString);color:\(text.hexString)">\(esc(subject.shortName ?? ""))</span></td>
            <td>\(esc(emoji)) \(esc(subject.name))</td><td>\(colourName)</td><td><code>\(subject.color.hexString)</code></td>
            <td><code>\(text.hexString)</code></td><td>\(fmt2(ratio)):1 \(aa ? "<span class=ok>AA</span>" : "<span class=bad>fails AA</span>")</td>
            <td>\(esc(subject.defaultRoom ?? "—"))</td><td>\(esc(subject.defaultTeacher ?? "—"))</td></tr>
            """
        }.joined()

        let lessons = s.db.lessons
        let everyWeek = lessons.filter { $0.occurrence.cycleWeeks == nil }.count
        let weekA = lessons.filter { $0.occurrence.cycleWeeks == [1] }.count
        let weekB = lessons.filter { $0.occurrence.cycleWeeks == [2] }.count
        let withBring = lessons.filter { !$0.bringList.isEmpty }.count

        return """
        <section>
          <h2><span class="num">1</span> Onboarding</h2>
          <p class="lead">A secondary-school profile with odd/even weeks. The builder creates settings, the timetable,
          the preset bell schedule, the term and the preset reminder rules; the demo then adds \(s.db.subjects.count)
          subjects and \(lessons.count) lessons (\(everyWeek) every week, \(weekA) only in week A, \(weekB) only in week B,
          \(withBring) with a bring-list).</p>
          <table class="kv">\(rows.map { "<tr><th scope=row>\($0.0)</th><td>\($0.1)</td></tr>" }.joined())</table>
          <h3>Preset reminder rules (homework, exam and pack-tonight enabled in the answers)</h3>
          <div class="scroll"><table><thead><tr><th>Target</th><th>Offsets</th><th>Follow-up</th><th>Tier</th><th>Enabled</th><th>Origin</th></tr></thead><tbody>\(ruleRows)</tbody></table></div>
          <h3>Bell schedules</h3>
          <p class="note">The preset generates lesson periods only; breaks are gaps between them. The second column is the
          “\(esc(s.shortBell.name))” schedule used by the override in section 4 (same period IDs, 30-minute lessons).</p>
          <div class="scroll"><table><thead><tr><th>#</th><th>\(esc(s.regularBell.name))</th><th>Length</th><th>\(esc(s.shortBell.name))</th><th>Period ID (tail)</th></tr></thead><tbody>\(bellRows)</tbody></table></div>
          <h3>Subjects, palette colours and computed text colours</h3>
          <div class="scroll"><table><thead><tr><th>Cell</th><th>Subject</th><th>Colour name key</th><th>Colour</th><th>Text</th><th>Contrast</th><th>Default room</th><th>Default teacher</th></tr></thead><tbody>\(subjectRows)</tbody></table></div>
        </section>
        """
    }

    private func weekGrids() -> String {
        """
        <section>
          <h2><span class="num">2</span> Week grids (<code>GridLayout.week(containing:resolver:)</code>)</h2>
          <p class="lead">Rows are the periods of the default bell schedule, columns the enabled days. The week label is
          <code>GridLayout.cycleLabel</code> (the rotation resolver's label for the week's cycle week). Hover a lesson to
          see its WCAG contrast ratio. Break rows are drawn by this page from the gaps between periods.</p>
          \(grid(s.thisWeek, title: "This week"))
          \(grid(s.nextWeek, title: "Next week"))
        </section>
        """
    }

    private func grid(_ layout: GridLayout, title: String) -> String {
        enum HRow {
            case period(GridLayout.Row)
            case gap(Int)
        }
        var hrows: [HRow] = []
        var htmlIndex: [Int: Int] = [:]
        for (i, row) in layout.rows.enumerated() {
            if i > 0 {
                let gap = layout.rows[i - 1].end.minutes(to: row.start)
                if gap > 0 { hrows.append(.gap(gap)) }
            }
            htmlIndex[row.index] = hrows.count
            hrows.append(.period(row))
        }
        struct Group {
            var span: Int
            var cells: [GridLayout.Cell]
        }
        struct Pos: Hashable {
            var column: Int
            var row: Int
        }
        var groups: [Pos: Group] = [:]
        var coveredBy: [Pos: Pos] = [:]
        for cell in layout.cells {
            guard let top = htmlIndex[cell.row], let bottom = htmlIndex[cell.row + cell.rowSpan - 1] else { continue }
            let start = Pos(column: cell.column, row: top)
            if let owner = coveredBy[start] {
                groups[owner]?.cells.append(cell)
                continue
            }
            var group = groups[start] ?? Group(span: 1, cells: [])
            group.cells.append(cell)
            group.span = max(group.span, bottom - top + 1)
            groups[start] = group
            for r in top...(top + group.span - 1) { coveredBy[Pos(column: cell.column, row: r)] = start }
        }
        let empty = Set(layout.emptySlots.map { Pos(column: $0.column, row: htmlIndex[$0.row] ?? -1) })

        let head = layout.columns.map { column -> String in
            var notes: [String] = []
            if let label = column.cycleLabel { notes.append("Week \(esc(label))") }
            if column.date == s.today { notes.append("<span class=\"badge today\">today</span>") }
            if let bell = column.bellScheduleID, bell != s.regularBell.id,
               let name = s.db.bellSchedules.first(where: { $0.id == bell })?.name {
                notes.append("<span class=\"badge mod\">\(esc(name))</span>")
            }
            if column.cancellingOverrideID != nil { notes.append("<span class=\"badge cancel\">day cancelled</span>") }
            if !column.isSchoolDay { notes.append("<span class=muted>no school</span>") }
            return "<th scope=col class=\"\(column.date == s.today ? "is-today" : "")\">\(dayName(column.weekday))<br><span class=small>\(dayMonth(column.date))</span><br><span class=small>\(notes.joined(separator: " "))</span></th>"
        }.joined()

        var body = ""
        for (h, hrow) in hrows.enumerated() {
            switch hrow {
            case .period(let row):
                body += "<tr><th scope=row class=period>\(row.lessonNumber.map { "\($0)." } ?? esc(row.label ?? ""))<br><span class=small>\(row.start)–\(row.end)</span></th>"
            case .gap(let minutes):
                body += "<tr class=gap><th scope=row class=gap>break<br><span class=small>\(minutes) min</span></th>"
            }
            for column in layout.columns {
                let pos = Pos(column: column.index, row: h)
                if let group = groups[pos] {
                    let resolution = s.resolutions[column.date]
                    let content = group.cells.map { lessonCard($0.entry, resolution: resolution, conflict: $0.isInConflict) }.joined()
                    body += "<td rowspan=\"\(group.span)\" class=lesson-td>\(content)</td>"
                } else if coveredBy[pos] != nil {
                    continue
                } else if case .gap = hrow {
                    body += "<td class=gap></td>"
                } else if empty.contains(pos) {
                    body += "<td class=free title=\"empty slot (GridLayout.emptySlots)\">·</td>"
                } else {
                    body += "<td class=off></td>"
                }
            }
            body += "</tr>"
        }
        let unplaced = layout.unplaced.isEmpty ? "" :
            "<p class=note>Unplaced (no matching row): \(layout.unplaced.map { esc($0.subject.name) }.joined(separator: ", "))</p>"
        let caption = "\(title): week of \(shortDate(layout.weekStart ?? s.today)) · <strong>Week \(esc(layout.cycleLabel ?? "?"))</strong> (cycle week \(layout.cycleWeek.map(String.init) ?? "–")) · \(layout.cells.count) cells, \(layout.emptySlots.count) empty slots"
        return """
        <figure class="grid-wrap">
          <figcaption>\(caption)</figcaption>
          <div class="scroll"><table class="grid"><thead><tr><th></th>\(head)</tr></thead><tbody>\(body)</tbody></table></div>
          \(unplaced)
        </figure>
        """
    }

    private func lessonCard(_ entry: ResolvedLesson, resolution: DayResolution?, conflict: Bool) -> String {
        let bg = entry.subject.color
        let fg = bg.preferredTextColor
        let ratio = Contrast.ratio(fg, bg)
        let reasons = resolution?.reasons(for: entry.id) ?? []
        var badges = ""
        switch entry.status {
        case .scheduled: break
        case .cancelled: badges += "<span class=\"badge cancel\">cancelled</span>"
        case .modified: badges += "<span class=\"badge mod\">modified</span>"
        case .added: badges += "<span class=\"badge add\">added</span>"
        }
        badges += reasons.map { "<span class=\"badge reason\" title=\"\($0.l10nKey)\">\(esc(english(LocalizedText(key: $0.l10nKey)) ?? $0.rawValue))</span>" }.joined()
        if conflict { badges += "<span class=\"badge cancel\">conflict</span>" }
        let detail = [entry.room, entry.teacher].compactMap { $0 }.joined(separator: " · ")
        let title = "\(entry.subject.name) · \(entry.startTime)–\(entry.endTime) · text \(fg.hexString) on \(bg.hexString) = contrast \(fmt2(ratio)):1 (\(ratio >= 4.5 ? "AA" : "below AA")) · status \(entry.status.rawValue)"
        var emoji = ""
        if case .emoji(let value)? = entry.subject.symbol { emoji = value + " " }
        let bring = entry.bringList.isEmpty ? "" : "<span class=bring>🎒 \(entry.bringList.count)</span>"
        return """
        <div class="card status-\(entry.status.rawValue)" style="background:\(bg.hexString);color:\(fg.hexString)" title="\(esc(title))">
          <span class=subj>\(esc(emoji))\(esc(entry.subject.shortName ?? entry.subject.name))</span>\(bring)
          <span class=meta>\(esc(detail))</span>
          <span class=meta>\(entry.startTime)–\(entry.endTime)</span>
          \(badges.isEmpty ? "" : "<span class=badges>\(badges)</span>")
        </div>
        """
    }

    private func dayView() -> String {
        let nn = s.nowNext
        let rows = s.todaySchedule.entries.map { entry -> String in
            let isCurrent = entry.id == nn.current?.id
            let isNext = entry.id == nn.next?.id
            let marker = isCurrent ? "<span class=\"badge today\">now</span>" : (isNext ? "<span class=\"badge add\">next</span>" : "")
            return "<tr class=\"\(isCurrent ? "current" : "")\"><td>\(entry.periodNumber.map { "\($0)." } ?? "")</td><td>\(entry.startTime)–\(entry.endTime)</td><td><span class=dot style=\"background:\(entry.subject.color.hexString)\"></span>\(esc(entry.subject.name))</td><td>\(esc(entry.room ?? "—"))</td><td>\(esc(entry.teacher ?? "—"))</td><td>\(esc(entry.notes ?? ""))\(entry.bringList.isEmpty ? "" : " 🎒 " + esc(entry.bringList.joined(separator: ", ")))</td><td>\(entry.status.rawValue) \(marker)</td></tr>"
        }.joined()
        func lessonLine(_ lesson: ResolvedLesson?) -> String {
            guard let lesson else { return "—" }
            return "\(esc(lesson.subject.name)) · \(shortDate(lesson.date)) \(lesson.startTime)–\(lesson.endTime) · \(esc(lesson.room ?? "—"))"
        }
        return """
        <section>
          <h2><span class="num">3</span> Day view for “now” + Now &amp; Next (<code>ScheduleResolver.nowAndNext(at:)</code>)</h2>
          <div class="nownext">
            <div><div class="tile-label">State</div><div class="big">\(stateName(nn.state))</div></div>
            <div><div class="tile-label">Current</div><div class="big">\(lessonLine(nn.current))</div>
              <div class="tile-note">remaining: \(nn.remaining.map { "\(minutes($0)) min (\(Int($0)) s)" } ?? "—")</div></div>
            <div><div class="tile-label">Next</div><div class="big">\(lessonLine(nn.next))</div>
              <div class="tile-note">starts in: \(nn.untilNext.map { "\(minutes($0)) min" } ?? "—")</div></div>
          </div>
          <p class="note">\(shortDate(s.today)): day key <code>\(s.todaySchedule.dayKey.map(dayKeyText) ?? "nil")</code>,
          cycle week \(s.todaySchedule.cycleWeek.map(String.init) ?? "–") (label “\(esc(s.todaySchedule.cycleLabel ?? "–"))”),
          school day: \(s.todaySchedule.isSchoolDay), term: \(s.todaySchedule.termID.flatMap { id in s.db.terms.first { $0.id == id }?.name }.map(esc) ?? "—").</p>
          <div class="scroll"><table><thead><tr><th>#</th><th>Time</th><th>Subject</th><th>Room</th><th>Teacher</th><th>Notes / bring</th><th>Status</th></tr></thead><tbody>\(rows)</tbody></table></div>
        </section>
        """
    }

    private func overrides() -> String {
        let overrides = s.db.overrides.filter { $0.date == s.overrideDate }
        let list = overrides.map { "<li><code>\(kindName($0.change))</code> — \(overrideText($0.change)) <span class=small>(id …\($0.id.uuidString.suffix(4)))</span></li>" }.joined()
        guard let resolution = s.resolutions[s.overrideDate] else { return "" }
        let rows = resolution.schedule.entries.map { entry -> String in
            let reasons = resolution.reasons(for: entry.id)
            let reasonText = reasons.isEmpty ? "—" : reasons.map { "<code>\($0.l10nKey)</code> “\(esc(english(LocalizedText(key: $0.l10nKey)) ?? ""))”" }.joined(separator: "<br>")
            let applied = entry.appliedOverrideIDs.map { id in overrides.first { $0.id == id }.map { kindName($0.change) } ?? "?" }
            return "<tr><td>\(entry.periodNumber.map { "\($0)." } ?? "")</td><td>\(entry.startTime)–\(entry.endTime)</td><td><span class=dot style=\"background:\(entry.subject.color.hexString)\"></span>\(esc(entry.subject.shortName ?? entry.subject.name))</td><td>\(esc(entry.room ?? "—"))</td><td>\(esc(entry.teacher ?? "—"))</td><td><span class=\"badge \(statusClass(entry.status))\">\(entry.status.rawValue)</span></td><td>\(reasonText)</td><td>\(applied.joined(separator: ", "))</td></tr>"
        }.joined()
        let warnings = resolution.warnings.isEmpty ? "none" : resolution.warnings.map { "<code>\($0.kind.l10nKey)</code>" }.joined(separator: ", ")
        let bellName = resolution.schedule.bellScheduleID.flatMap { id in s.db.bellSchedules.first { $0.id == id }?.name } ?? "—"
        return """
        <section>
          <h2><span class="num">4</span> One-off overrides on \(shortDate(s.overrideDate))</h2>
          <p class="lead">Four <code>ScheduleOverride</code>s on one date of this week. The table is
          <code>ScheduleResolver.resolution(for:)</code>: status and modification reasons exactly as the resolver reports them.</p>
          <ul class="overrides">\(list)</ul>
          <p class="note">Bell schedule used: “\(esc(bellName))” (via <code>bellScheduleOverrideID</code>
          \(resolution.bellScheduleOverrideID == nil ? "nil" : "set")) · resolution warnings: \(warnings) · conflicts: \(resolution.schedule.conflicts.count)</p>
          <div class="scroll"><table><thead><tr><th>#</th><th>Time</th><th>Subject</th><th>Room</th><th>Teacher</th><th>Status</th><th>Modification reasons (key → English)</th><th>Applied overrides</th></tr></thead><tbody>\(rows)</tbody></table></div>
        </section>
        """
    }

    private func timeBlocks() -> String {
        let layout = s.timeBlocks
        let height = 560
        let marks = layout.hourMarks.map { mark in
            "<div class=hourline style=\"top:\(pct(mark.position))\"><span>\(LocalTime(minuteOfDay: mark.minuteOfDay)?.isoString ?? "24:00")</span></div>"
        }.joined()
        let columns = layout.columns.map { column -> String in
            let blocks = layout.blocks.filter { $0.column == column.index }.map { block -> String in
                let entry = block.entry
                let bg = entry.subject.color, fg = bg.preferredTextColor
                let width = 100.0 / Double(block.laneCount)
                let title = "\(entry.subject.name) \(entry.startTime)–\(entry.endTime) · top \(fmt4(block.top)) · height \(fmt4(block.height)) · lane \(block.lane)/\(block.laneCount)"
                return "<div class=\"block status-\(entry.status.rawValue)\" style=\"top:\(pct(block.top));height:\(pct(block.height));left:\(fmt2(width * Double(block.lane)))%;width:\(fmt2(width))%;background:\(bg.hexString);color:\(fg.hexString)\" title=\"\(esc(title))\"><strong>\(esc(entry.subject.shortName ?? ""))</strong> \(entry.startTime)\(entry.status == .scheduled ? "" : " · " + entry.status.rawValue)</div>"
            }.joined()
            return "<div class=tb-col><div class=tb-head>\(shortDate(column.date))\(column.date == s.overrideDate ? " · short day" : "")</div><div class=tb-body style=\"height:\(height)px\">\(marks)\(blocks)</div></div>"
        }.joined()
        let numbers = layout.blocks.map { block in
            "<tr><td>\(shortDate(block.entry.date))</td><td>\(esc(block.entry.subject.shortName ?? ""))</td><td>\(block.entry.startTime)–\(block.entry.endTime)</td><td>\(fmt4(block.top))</td><td>\(fmt4(block.height))</td><td>\(block.lane)/\(block.laneCount)</td><td>\(block.entry.status.rawValue)</td></tr>"
        }.joined()
        return """
        <section>
          <h2><span class="num">5</span> Time-block layout (<code>TimeBlockLayout.make(days:)</code>)</h2>
          <p class="lead">Today next to the short day. Visible range \(LocalTime(minuteOfDay: layout.startMinute)?.isoString ?? "?")–\(LocalTime(minuteOfDay: layout.endMinute)?.isoString ?? "24:00")
          (automatic bounds snapped to full hours). Box <code>top</code>/<code>height</code> are the engine's fractions of that range, used directly as CSS percentages.</p>
          <div class="tb">\(columns)</div>
          <details><summary>Fractions returned by the engine (\(layout.blocks.count) blocks)</summary>
          <div class="scroll"><table><thead><tr><th>Date</th><th>Subject</th><th>Time</th><th>top</th><th>height</th><th>lane</th><th>status</th></tr></thead><tbody>\(numbers)</tbody></table></div></details>
        </section>
        """
    }

    private func reminders() -> String {
        let plan = s.plan
        let rules = Dictionary(uniqueKeysWithValues: s.db.reminderRules.map { ($0.id, $0) })
        var rows = ""
        for (index, item) in plan.notifications.enumerated() {
            let ruleText = item.ruleID.flatMap { rules[$0] }.map { "rule <code>\($0.target.rawValue)</code>" } ?? "item override"
            let tier = item.requestedTier == item.effectiveTier
                ? "<code>\(item.effectiveTier.rawValue)</code>"
                : "<code>\(item.requestedTier.rawValue)</code> → <code>\(item.effectiveTier.rawValue)</code>"
            let reasons = item.tierChanges.isEmpty ? "—" : item.tierChanges.map { "<code>\($0.rawValue)</code><br><span class=small>\(esc(english(LocalizedText(key: $0.l10nKey)) ?? ""))</span>" }.joined(separator: "<br>")
            rows += """
            <tr><td>\(index + 1)</td><td class=nowrap>\(esc(instant(item.fireDate)))</td><td>\(sourceText(item.source))\(item.isFollowUp ? " <span class=\"badge mod\">follow-up</span>" : "")\(item.movedByQuietHours ? " <span class=badge>quiet hours</span>" : "")<br><span class=small>\(ruleText)</span></td>
            <td>\(tier)</td><td>\(reasons)</td><td>\(textCell(item.content.title))</td><td>\(textCell(item.content.body))\(item.content.subtitle.map { "<br>" + textCell($0) } ?? "")</td></tr>
            """
        }
        let alarms = plan.alarms.isEmpty ? "" : "<p class=note>Loud alarms: \(plan.alarms.count)</p>"
        let dropped = plan.dropped.map { drop in
            "<tr><td>\(drop.fireDate.map { esc(instant($0)) } ?? "—")</td><td>\(sourceText(drop.source))\(drop.isFollowUp ? " (follow-up)" : "")</td><td><code>\(drop.reason.l10nKey)</code><br><span class=small>\(esc(english(LocalizedText(key: drop.reason.l10nKey)) ?? ""))</span></td></tr>"
        }.joined()
        let dst = "The window crosses the end of summer time (Sun 25 Oct 2026, 03:00 CEST → 02:00 CET): reminders after it show UTC+01:00 at the same wall-clock time."
        return """
        <section>
          <h2><span class="num">6</span> Reminder plan (<code>ReminderPlanner.plan</code>, next \(s.plannerInput.horizonDays) days)</h2>
          <p class="lead">Input: \(s.db.tasks.count) tasks (one completed), \(s.db.exams.count) exams, the enabled preset rules,
          \(s.plannerInput.lessons.count) resolved lesson occurrences and \(s.plannerInput.packTonight.count) pack-tonight days
          (<code>PackTonightDay.days(from:)</code>). <code>canScheduleAlarms = false</code> (no AlarmKit here); the biology exam
          asks for a loud alarm through its reminder override, the essay asks for Time Sensitive.</p>
          <p class="note">Planned: <strong>\(plan.notifications.count)</strong> notifications, \(plan.alarms.count) alarms ·
          dropped: \(plan.dropped.count) · budget \(s.plannerInput.budget.available) of \(s.plannerInput.budget.maxPending) · saturated: \(plan.isSaturated)
          · horizon end \(esc(instant(plan.horizonEnd))) · next re-plan \(esc(instant(plan.nextReplanDate))). \(dst)</p>
          \(alarms)
          <div class="scroll"><table class="reminders"><thead><tr><th>#</th><th>Fires (local)</th><th>Source</th><th>Tier requested → effective</th><th>Tier change</th><th>Title (key → English)</th><th>Body / subtitle</th></tr></thead><tbody>\(rows)</tbody></table></div>
          <h3>Dropped</h3>
          \(dropped.isEmpty ? "<p class=note>none</p>" : "<div class=\"scroll\"><table><thead><tr><th>Would fire</th><th>Source</th><th>Reason</th></tr></thead><tbody>\(dropped)</tbody></table></div>")
        </section>
        """
    }

    private func share() -> String {
        let env = s.shareEnvelope
        let payload = s.decodedPayload
        let shownLink = s.inlineLink.count > 140 ? String(s.inlineLink.prefix(140)) + "…" : s.inlineLink
        let routeLink = env.route == .inline ? s.inlineLink : s.codeLink
        let warnings = s.shareWarnings.isEmpty ? "none" : s.shareWarnings.map { "<code>\(esc($0.description))</code>" }.joined(separator: ", ")
        let rows: [(String, String)] = [
            ("API", "<code>ShareExport.encode(from:timetableID:includeTasks: true)</code> → <code>ShareCodec.decode</code> round-trip"),
            ("Canonical JSON", "\(env.jsonByteCount) bytes"),
            ("Compressed (raw DEFLATE)", "<strong>\(env.compressedByteCount) bytes</strong> (\(fmt2(Double(env.compressedByteCount) / Double(max(1, env.jsonByteCount)) * 100)) % of JSON) · inline limit \(ShareLimits.inlineCompressedBytes) bytes"),
            ("Envelope", "\(env.text.utf8.count) characters (<code>\(esc(String(env.text.prefix(24))))…</code>)"),
            ("Route", "<strong><code>\(env.route.rawValue)</code></strong> → link length \(routeLink.utf8.count) characters"),
            ("Inline link", "<code class=wrap>\(esc(shownLink))</code> (\(s.inlineLink.utf8.count) characters)"),
            ("Sample short code", "<code>\(s.sampleCode.rawValue)</code> · display <code>\(s.sampleCode.formatted)</code> · <code>\(esc(s.codeLink))</code> (\(s.codeLink.utf8.count) characters; seeded RNG, not registered anywhere)"),
            ("Link parse round-trip", s.parsedLinkMatches ? "<span class=ok>ShareLink.parse returns the same link</span>" : "<span class=bad>mismatch</span>"),
            ("Decoded payload", "“\(esc(payload.timetable.name))”: \(payload.subjects.count) subjects, \(payload.lessons.count) lessons, \(payload.bellSchedules.count) bell schedules, \(payload.terms.count) terms, \(payload.breaks.count) breaks, \(payload.tasks.count) tasks, \(payload.exams.count) exams"),
            ("Export warnings", warnings),
        ]
        return """
        <section>
          <h2><span class="num">7</span> Share (<code>ShareCodec</code>)</h2>
          <p class="lead">The timetable with open tasks and exams. Per SHARE_FORMAT v1, overrides, reminder rules, settings, IDs and
          completed items are not shared (the completed task is absent from the decoded payload).</p>
          <table class="kv">\(rows.map { "<tr><th scope=row>\($0.0)</th><td>\($0.1)</td></tr>" }.joined())</table>
        </section>
        """
    }

    private func validation() -> String {
        let db = s.db
        let counts: [(String, Int, Int)] = [
            ("timetables", db.timetables.count, db.timetables.filter(\.isDeleted).count),
            ("subjects", db.subjects.count, db.subjects.filter(\.isDeleted).count),
            ("bellSchedules", db.bellSchedules.count, db.bellSchedules.filter(\.isDeleted).count),
            ("lessons", db.lessons.count, db.lessons.filter(\.isDeleted).count),
            ("terms", db.terms.count, db.terms.filter(\.isDeleted).count),
            ("breaks", db.breaks.count, db.breaks.filter(\.isDeleted).count),
            ("overrides", db.overrides.count, db.overrides.filter(\.isDeleted).count),
            ("tasks", db.tasks.count, db.tasks.filter(\.isDeleted).count),
            ("exams", db.exams.count, db.exams.filter(\.isDeleted).count),
            ("reminderRules", db.reminderRules.count, db.reminderRules.filter(\.isDeleted).count),
        ]
        let countRows = counts.map { "<tr><td><code>\($0.0)</code></td><td>\($0.1)</td><td>\($0.2)</td></tr>" }.joined()
        let issueRows = s.issues.map { issue in
            "<tr><td>\(issue.severity.rawValue)</td><td><code>\(issue.code.l10nKey)</code><br><span class=small>\(esc(english(issue.message) ?? ""))</span></td><td>\(issue.entityType.rawValue)</td><td>\(esc(issue.field ?? "—"))</td></tr>"
        }.joined()
        let tt = s.timetable
        let override = db.overrides.first
        let meta = [
            "timetable <code>\(tt.id)</code>: createdAt <code>\(tt.meta.createdAt)</code>, updatedAt <code>\(tt.meta.updatedAt)</code>, isDeleted \(tt.meta.isDeleted)",
            override.map { "override <code>\($0.id)</code>: createdAt <code>\($0.meta.createdAt)</code>, isDeleted \($0.meta.isDeleted)" } ?? "",
        ].filter { !$0.isEmpty }.map { "<li>\($0)</li>" }.joined()
        return """
        <section>
          <h2><span class="num">8</span> Validation &amp; persistence</h2>
          <p class="lead"><code>TabulaDatabase.validate()</code>: <strong>\(s.issues.isEmpty ? "no issues" : "\(s.issues.count) issue(s)")</strong>
          · schema version \(db.schemaVersion) · canonical JSON \(s.jsonBytes) bytes (pretty \(s.prettyJSONBytes) bytes)
          · encode → decode round-trip equal: \(s.roundTripEqual ? "<span class=ok>yes</span>" : "<span class=bad>no</span>")</p>
          \(s.issues.isEmpty ? "" : "<div class=\"scroll\"><table><thead><tr><th>Severity</th><th>Code</th><th>Entity</th><th>Field</th></tr></thead><tbody>\(issueRows)</tbody></table></div>")
          <div class="scroll"><table><thead><tr><th>Collection</th><th>Entities</th><th>Tombstoned</th></tr></thead><tbody>\(countRows)</tbody></table></div>
          <h3>Sync metadata (sample)</h3>
          <ul class="overrides">\(meta)</ul>
        </section>
        """
    }

    private func footer() -> String {
        """
        <footer>
          <p>Generated by <code>bash scripts/engine-demo.sh</code> (SwiftPM package <code>Tools/EngineDemo</code>, depends on
          <code>Packages/TimetableCore</code> and <code>Packages/TimetableUI</code> by path). Inputs live in <code>Packages/TimetableUI/Sources/TimetableUI/Samples/SecondaryScenario.swift</code> (shared with the app's <code>-TabulaSeed secondary</code>).
          No JavaScript, no external resources. Reminder: this is an inspection view of engine output, not the app's UI.</p>
        </footer>
        """
    }

    // MARK: - Text helpers

    private func english(_ text: LocalizedText) -> String? {
        catalog.english(text, format: argumentText)
    }

    private func argumentText(_ argument: LocalizedArgument) -> String {
        switch argument {
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .date(let value): return shortDate(value)
        case .time(let value): return value.isoString
        case .text(let value): return value.description
        }
    }

    private func textCell(_ text: LocalizedText) -> String {
        "<code class=small>\(esc(text.description))</code><br>\(esc(english(text) ?? "(key not in catalog)"))"
    }

    private func sourceText(_ source: ReminderSource) -> String {
        switch source {
        case .task(let id): return "task “\(esc(s.db.tasks.first { $0.id == id }?.title ?? "?"))”"
        case .exam(let id): return "exam “\(esc(s.db.exams.first { $0.id == id }?.title ?? "?"))”"
        case .lesson(let occurrence): return "lesson \(esc(occurrence.rawValue))"
        case .packTonight(let date): return "pack tonight for \(shortDate(date))"
        }
    }

    private func lessonLabel(_ id: Lesson.ID) -> String {
        guard let lesson = s.db.lessons.first(where: { $0.id == id }) else { return "?" }
        return "\(subjectsByID[lesson.subjectID]?.shortName ?? "?") (\(slotText(lesson.slot)))"
    }

    private func slotText(_ slot: LessonSlot) -> String {
        switch slot {
        case let .period(id, span):
            let number = (s.regularBell.lessonPeriods.firstIndex { $0.id == id } ?? -1) + 1
            return span > 1 ? "periods \(number)–\(number + span - 1)" : "period \(number)"
        case let .time(start, end): return "\(start)–\(end)"
        }
    }

    private func kindName(_ change: OverrideChange) -> String {
        switch change {
        case .cancelLesson: return "cancelLesson"
        case .modifyLesson: return "modifyLesson"
        case .addLesson: return "addLesson"
        case .cancelDay: return "cancelDay"
        case .useBellSchedule: return "useBellSchedule"
        case .followDay: return "followDay"
        case .unknown: return "unknown"
        }
    }

    private func overrideText(_ change: OverrideChange) -> String {
        switch change {
        case .cancelLesson(let id): return esc(lessonLabel(id))
        case let .modifyLesson(id, patch):
            var parts: [String] = []
            if let room = patch.room { parts.append("room = “\(esc(room))”") }
            if let teacher = patch.teacher { parts.append("teacher = “\(esc(teacher))”") }
            if let notes = patch.notes { parts.append("notes = “\(esc(notes))”") }
            return "\(esc(lessonLabel(id))): \(parts.joined(separator: ", "))"
        case .addLesson(let lesson):
            return "\(esc(subjectsByID[lesson.subjectID]?.shortName ?? "?")) in \(slotText(lesson.slot))\(lesson.notes.map { " — “\(esc($0))”" } ?? "")"
        case .cancelDay(let note): return note.map(esc) ?? ""
        case .useBellSchedule(let id): return "“\(esc(s.db.bellSchedules.first { $0.id == id }?.name ?? "?"))”"
        case let .followDay(day, week): return "\(dayKeyText(day)) week \(week.map(String.init) ?? "own")"
        case .unknown: return ""
        }
    }

    private func statusClass(_ status: ResolvedLesson.Status) -> String {
        switch status {
        case .scheduled: return ""
        case .modified: return "mod"
        case .added: return "add"
        case .cancelled: return "cancel"
        }
    }

    private func stateName(_ state: NowNext.State) -> String {
        switch state {
        case .inLesson: return "inLesson"
        case .betweenLessons: return "betweenLessons"
        case .beforeFirstLesson: return "beforeFirstLesson"
        case .afterLastLesson: return "afterLastLesson"
        case .noLessonsToday: return "noLessonsToday"
        case .inBreak: return "inBreak"
        }
    }

    private func dayKeyText(_ key: DayKey) -> String {
        switch key {
        case .weekday(let weekday): return ".weekday(\(dayName(weekday)))"
        case .cycleDay(let index): return ".cycleDay(\(index))"
        }
    }

    private func offsetText(_ offset: ReminderOffset) -> String {
        switch offset {
        case .minutesBefore(let minutes): return "\(minutes) min before"
        case let .daysBefore(days, at): return "\(days) day\(days == 1 ? "" : "s") before at \(at)"
        case .unknown: return "unknown"
        }
    }

    private func followUpText(_ followUp: FollowUp) -> String {
        switch followUp {
        case .afterMinutes(let minutes): return "after \(minutes) min"
        case .nextMorning(let at): return "next morning at \(at)"
        case .unknown: return "unknown"
        }
    }

    private static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private func dayName(_ weekday: Weekday) -> String { Self.dayNames[weekday.rawValue - 1] }

    private func dayMonth(_ date: LocalDate) -> String { "\(date.day) \(Self.monthNames[date.month - 1])" }

    private func shortDate(_ date: LocalDate) -> String {
        "\(dayName(date.weekday)) \(date.day) \(Self.monthNames[date.month - 1])"
    }

    /// Local wall clock of `date` in the scenario's zone plus its UTC offset (shows DST).
    private func instant(_ date: Date) -> String {
        let local = s.context.local(from: date)
        let offset = s.zone.secondsFromGMT(for: date)
        let sign = offset < 0 ? "-" : "+"
        let hours = abs(offset) / 3600, mins = abs(offset) % 3600 / 60
        return "\(shortDate(local.date)) \(local.date.year) \(local.time) (UTC\(sign)\(hours < 10 ? "0" : "")\(hours):\(mins < 10 ? "0" : "")\(mins))"
    }

    private func minutes(_ seconds: TimeInterval) -> Int { Int((seconds / 60).rounded()) }

    private func fmt2(_ value: Double) -> String { fixed(value, digits: 2) }
    private func fmt4(_ value: Double) -> String { fixed(value, digits: 4) }
    private func pct(_ fraction: Double) -> String { fixed(fraction * 100, digits: 3) + "%" }

    /// Locale-independent fixed-point formatting (no `String(format:)`).
    private func fixed(_ value: Double, digits: Int) -> String {
        var scale = 1.0
        for _ in 0..<digits { scale *= 10 }
        let scaled = Int64((abs(value) * scale).rounded())
        let whole = scaled / Int64(scale)
        var fraction = String(scaled % Int64(scale))
        while fraction.count < digits { fraction = "0" + fraction }
        return "\(value < 0 && scaled != 0 ? "-" : "")\(whole)\(digits > 0 ? "." + fraction : "")"
    }

    private func esc(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for char in text {
            switch char {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(char)
            }
        }
        return out
    }

    // MARK: - Style

    static let css = """
    :root{--bg:#f6f7f9;--surface:#ffffff;--text:#16181d;--muted:#5b6270;--line:#d9dde4;--accent:#1e5bd8;
    --banner-bg:#fff4d6;--banner-line:#e0b44c;--gap:#eef0f4;--off:#f1f2f5;--ok:#1b7a3a;--bad:#b3261e;
    --badge-bg:#e8ebf1;--badge-text:#16181d;--mod:#8a4b00;--mod-bg:#ffe7c2;--add:#0b5e3b;--add-bg:#cdf3df;
    --cancel:#8f1d17;--cancel-bg:#ffd9d6;--today:#1e5bd8;color-scheme:light}
    @media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#111317;--surface:#1a1d23;--text:#e9ecf1;
    --muted:#a2a9b6;--line:#2e333c;--accent:#7aa7ff;--banner-bg:#3a2e0f;--banner-line:#8a6d22;--gap:#16191e;--off:#15181d;
    --ok:#6fd38f;--bad:#ff8a80;--badge-bg:#2a2f38;--badge-text:#e9ecf1;--mod:#ffcf8a;--mod-bg:#4a3210;--add:#8ff0bd;
    --add-bg:#11402b;--cancel:#ffb3ac;--cancel-bg:#4d1915;--today:#7aa7ff;color-scheme:dark}}
    :root[data-theme="dark"]{--bg:#111317;--surface:#1a1d23;--text:#e9ecf1;--muted:#a2a9b6;--line:#2e333c;--accent:#7aa7ff;
    --banner-bg:#3a2e0f;--banner-line:#8a6d22;--gap:#16191e;--off:#15181d;--ok:#6fd38f;--bad:#ff8a80;--badge-bg:#2a2f38;
    --badge-text:#e9ecf1;--mod:#ffcf8a;--mod-bg:#4a3210;--add:#8ff0bd;--add-bg:#11402b;--cancel:#ffb3ac;--cancel-bg:#4d1915;
    --today:#7aa7ff;color-scheme:dark}
    *{box-sizing:border-box}
    body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
    main{max-width:1180px;margin:0 auto;padding:24px 16px 48px}
    h1{font-size:1.6rem;line-height:1.25;margin:.2rem 0 .6rem}
    h2{font-size:1.25rem;margin:0 0 .5rem;display:flex;align-items:center;gap:.5rem}
    h3{font-size:1rem;margin:1.2rem 0 .4rem}
    .num{display:inline-grid;place-items:center;width:1.7rem;height:1.7rem;border-radius:50%;background:var(--accent);color:var(--surface);font-size:.9rem}
    section,.banner,footer{background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:18px 20px;margin:0 0 18px}
    .banner{background:var(--banner-bg);border:2px solid var(--banner-line)}
    .eyebrow{text-transform:uppercase;letter-spacing:.06em;font-size:.75rem;color:var(--muted);margin:0}
    .lead{margin:.2rem 0 .8rem}.note{color:var(--muted);font-size:.9rem}.muted{color:var(--muted)}
    .small{font-size:.78rem;color:var(--muted)}.facts{font-size:.9rem}
    code{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:.85em}
    code.wrap{word-break:break-all}
    code,table.kv td,h2,.lead,.note,li{overflow-wrap:anywhere}
    .scroll{overflow-x:auto;-webkit-overflow-scrolling:touch}
    table{border-collapse:collapse;width:100%;font-size:.9rem}
    th,td{border:1px solid var(--line);padding:6px 8px;text-align:left;vertical-align:top}
    thead th{background:var(--gap);font-weight:600}
    table.kv th{width:210px;background:var(--gap);font-weight:600}
    .tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;background:none;border:0;padding:0}
    .tile{background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:12px}
    .tile-label{font-size:.75rem;text-transform:uppercase;letter-spacing:.05em;color:var(--muted)}
    .tile-value{font-size:1.15rem;font-weight:650;margin:.15rem 0}.tile-note{font-size:.8rem;color:var(--muted)}
    .swatch{display:inline-block;min-width:3.2rem;text-align:center;border-radius:6px;padding:3px 6px;font-weight:650}
    .dot{display:inline-block;width:.7rem;height:.7rem;border-radius:50%;margin-right:.4rem;vertical-align:baseline}
    .ok{color:var(--ok);font-weight:600}.bad{color:var(--bad);font-weight:600}
    .grid-wrap{margin:0 0 20px}.grid-wrap figcaption{font-weight:600;margin:0 0 6px}
    table.grid{table-layout:fixed;min-width:760px}
    table.grid th.period,table.grid th.gap{width:92px;background:var(--gap)}
    table.grid thead th{text-align:center}table.grid thead th.is-today{box-shadow:inset 0 -3px 0 var(--today)}
    table.grid td{padding:3px;height:62px}
    table.grid tr.gap td,table.grid tr.gap th{height:auto;padding:2px 6px;background:var(--gap);font-size:.75rem}
    td.off{background:var(--off)}td.free{text-align:center;color:var(--muted)}
    .card{border-radius:8px;padding:5px 7px;height:100%;min-height:54px;display:flex;flex-direction:column;gap:1px;margin-bottom:3px}
    .card .subj{font-weight:700}.card .meta{font-size:.75rem;opacity:.92}.card .bring{font-size:.75rem;float:right}
    .status-cancelled{opacity:.55;text-decoration:line-through}
    .badges{display:flex;flex-wrap:wrap;gap:3px;margin-top:2px;text-decoration:none}
    .badge{display:inline-block;font-size:.7rem;line-height:1.3;padding:1px 6px;border-radius:999px;background:var(--badge-bg);color:var(--badge-text);font-weight:600;text-decoration:none}
    .badge.mod{background:var(--mod-bg);color:var(--mod)}.badge.add{background:var(--add-bg);color:var(--add)}
    .badge.cancel{background:var(--cancel-bg);color:var(--cancel)}.badge.today{background:var(--today);color:var(--surface)}
    .badge.reason{background:var(--surface);color:var(--text);border:1px solid var(--line)}
    .nownext{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px;margin:0 0 10px}
    .nownext>div{border:1px solid var(--line);border-radius:10px;padding:10px 12px}
    .big{font-size:1.05rem;font-weight:650}
    tr.current td{background:var(--mod-bg)}
    ul.overrides{margin:.2rem 0 .6rem;padding-left:1.2rem}
    .tb{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:14px;margin:6px 0 10px}
    .tb-head{font-weight:600;margin:0 0 4px;padding-left:48px}
    .tb-body{position:relative;border:1px solid var(--line);border-radius:8px;margin-left:48px;background:var(--gap)}
    .hourline{position:absolute;left:0;right:0;border-top:1px dashed var(--line)}
    .hourline span{position:absolute;left:-48px;top:-.6rem;font-size:.72rem;color:var(--muted);width:44px;text-align:right}
    .block{position:absolute;border-radius:6px;padding:2px 6px;font-size:.75rem;overflow:hidden;border:1px solid rgba(0,0,0,.15)}
    details{margin-top:8px}summary{cursor:pointer;color:var(--accent)}
    .nowrap{white-space:nowrap}
    table.reminders td{font-size:.85rem}table.reminders td:nth-child(3){min-width:190px}
    footer{font-size:.85rem;color:var(--muted)}
    @media (max-width:600px){main{padding:16px 16px 32px}section,.banner,footer{padding:14px}table.kv th{width:120px}}
    """
}
