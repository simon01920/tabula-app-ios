import Foundation

/// RFC 5545 iCalendar: one VEVENT per occurrence (rotations, holidays and overrides make RRULEs error-prone; the
/// date range bounds the size). CRLF line endings, lines folded at 75 octets, TEXT values escaped.
///
/// - **Times.** With a `timeZone` (the app passes `context.timeZone` when `AppSettings.timeZoneMode` is
///   `.fixed`), DTSTART/DTEND carry `TZID=<IANA id>` and a VTIMEZONE describes that zone's offsets across the
///   exported dates. With `nil` (`.followDevice`) times are **floating**: calendar apps show them at the same
///   wall-clock time in whatever zone the device is in, which matches how Tabula treats school times.
///   Wall-clock times in a DST gap or overlap are interpreted by the importer exactly as the engine does
///   (RFC 5545 §3.3.5: gap → shifted forward, overlap → first occurrence).
/// - **UID** `<lesson or override UUID>-<yyyyMMdd>@tabula`: stable, so re-importing updates events.
/// - **Cancelled** occurrences are kept with `STATUS:CANCELLED`, so a re-import cancels an event exported earlier
///   instead of leaving it behind.
public enum ICSExport {
    /// The `.ics` file of `rows`. `stamp` is the DTSTAMP of every event (the export instant; injected for
    /// determinism). `labels.teacher` and `labels.changeText` fill DESCRIPTION; `calendarName` sets X-WR-CALNAME.
    public static func data(rows: [ExportRow], labels: ExportLabels, timeZone: TimeZone?, stamp: Date,
                            calendarName: String? = nil) -> Data {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Tabula//Timetable Export//EN", "CALSCALE:GREGORIAN"]
        if let calendarName { lines.append("X-WR-CALNAME:" + escape(calendarName)) }
        if let timeZone, let first = rows.map(\.date).min(), let last = rows.map(\.date).max() {
            lines += vtimezone(timeZone, from: first, through: last)
        }
        let dtstamp = format(localSeconds: CalendarContext.floorSeconds(stamp)) + "Z"
        let tzParam = timeZone.map { ";TZID=" + $0.identifier } ?? ""
        for row in rows {
            let day = PaddedNumber.decimal(row.date.year, width: 4) + PaddedNumber.decimal(row.date.month, width: 2)
                + PaddedNumber.decimal(row.date.day, width: 2)
            lines += ["BEGIN:VEVENT",
                      "UID:\(row.sourceID.uuidString)-\(day)@tabula",
                      "DTSTAMP:" + dtstamp,
                      "DTSTART\(tzParam):" + format(row.date, row.start),
                      "DTEND\(tzParam):" + format(row.date, row.end),
                      "SUMMARY:" + escape(row.subject)]
            if let room = row.room { lines.append("LOCATION:" + escape(room)) }
            let change = labels.changeText(row)
            let description = [row.teacher.map { "\(labels.teacher): \($0)" }, change.isEmpty ? nil : change]
                .compactMap { $0 }.map(escape).joined(separator: "\\n")
            if !description.isEmpty { lines.append("DESCRIPTION:" + description) }
            if row.status == .cancelled { lines.append("STATUS:CANCELLED") }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return Data(lines.map(fold).joined().utf8)
    }

    /// TEXT escaping (§3.3.11): backslash, semicolon, comma, and any line break as `\n`.
    static func escape(_ text: String) -> String {
        var out = ""
        for character in text {
            switch character {
            case "\\": out += "\\\\"
            case ";": out += "\\;"
            case ",": out += "\\,"
            case _ where character.isNewline: out += "\\n"
            default: out.append(character)
            }
        }
        return out
    }

    /// One content line, folded (§3.1) so no physical line exceeds 75 octets before its CRLF; never splits a
    /// UTF-8 sequence. Continuation lines start with a space, which counts toward their 75.
    static func fold(_ line: String) -> String {
        var out = ""
        var octets = 0
        for scalar in line.unicodeScalars {
            let width = UTF8.width(scalar)
            if octets + width > 75 {
                out += "\r\n "
                octets = 1
            }
            out.unicodeScalars.append(scalar)
            octets += width
        }
        return out + "\r\n"
    }

    /// The VTIMEZONE of `zone` for the dates `first…last`: the observance in effect at the start of `first`, then
    /// one STANDARD/DAYLIGHT block per offset change Foundation reports before the end of `last`.
    static func vtimezone(_ zone: TimeZone, from first: LocalDate, through last: LocalDate) -> [String] {
        let context = CalendarContext(timeZone: zone, firstWeekday: .monday)
        let start = context.startOfDay(first)
        let end = context.startOfDay(last.adding(days: 1))
        var lines = ["BEGIN:VTIMEZONE", "TZID:" + zone.identifier]
        func observance(at instant: Date, offsetFrom: Int, offsetTo: Int, onset: String) {
            let kind = zone.isDaylightSavingTime(for: instant) ? "DAYLIGHT" : "STANDARD"
            lines += ["BEGIN:" + kind, "DTSTART:" + onset, "TZOFFSETFROM:" + offset(offsetFrom),
                      "TZOFFSETTO:" + offset(offsetTo), "END:" + kind]
        }
        let initial = zone.secondsFromGMT(for: start)
        observance(at: start, offsetFrom: initial, offsetTo: initial, onset: format(first, .midnight))
        var cursor = start
        while let transition = zone.nextDaylightSavingTimeTransition(after: cursor), transition < end {
            let from = zone.secondsFromGMT(for: transition.addingTimeInterval(-1))
            let to = zone.secondsFromGMT(for: transition)
            // Onset is the local time just before the change, i.e. in the old offset (§3.6.5).
            if from != to {
                observance(at: transition, offsetFrom: from, offsetTo: to,
                           onset: format(localSeconds: CalendarContext.floorSeconds(transition) + Int64(from)))
            }
            cursor = transition
        }
        return lines + ["END:VTIMEZONE"]
    }

    /// `yyyyMMddTHHmmss` of a wall-clock date and time.
    static func format(_ date: LocalDate, _ time: LocalTime) -> String {
        format(localSeconds: Int64(date.daysSinceEpoch) * 86_400 + Int64(time.minuteOfDay) * 60)
    }

    /// `yyyyMMddTHHmmss` of seconds since 1970-01-01T00:00 on the same clock.
    static func format(localSeconds: Int64) -> String {
        let days = CalendarContext.floorDiv(localSeconds, 86_400)
        let second = Int(localSeconds - days * 86_400)
        let date = LocalDate(daysSinceEpoch: Int(clamping: days)) ?? (days < 0 ? .earliest : .latest)
        return PaddedNumber.decimal(date.year, width: 4) + PaddedNumber.decimal(date.month, width: 2)
            + PaddedNumber.decimal(date.day, width: 2) + "T" + PaddedNumber.decimal(second / 3600, width: 2)
            + PaddedNumber.decimal(second / 60 % 60, width: 2) + PaddedNumber.decimal(second % 60, width: 2)
    }

    /// UTC offset as `±HHMM` (`±HHMMSS` when it has seconds).
    static func offset(_ seconds: Int) -> String {
        let magnitude = abs(seconds)
        var text = (seconds < 0 ? "-" : "+") + PaddedNumber.decimal(magnitude / 3600, width: 2)
            + PaddedNumber.decimal(magnitude / 60 % 60, width: 2)
        if magnitude % 60 != 0 { text += PaddedNumber.decimal(magnitude % 60, width: 2) }
        return text
    }
}
