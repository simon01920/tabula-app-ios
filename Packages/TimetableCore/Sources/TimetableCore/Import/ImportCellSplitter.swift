import Foundation

/// Splits one cell's text into lessons and fields (subject, room, teacher, type, notes) with reasons and alternatives.
enum ImportCellSplitter {
    struct Part: Hashable {
        var weeks: Set<Int>?
        var subject = ""
        var room: String?
        var teacher: String?
        var lessonType: LessonType?
        var notes: [String] = []
        var reasons: Set<ImportConfidenceReason> = []
        var alternatives: [ImportAlternative] = []
    }

    /// One part per week marker group ("MAT (A)" / "B: FYZ"), else one part. Never returns a part without text.
    static func split(_ text: String, options: ImportParserOptions, languages: [String]) -> [Part] {
        weekGroups(text).compactMap { weeks, lines in
            var part = fields(lines, options: options, languages: languages)
            guard !part.subject.isEmpty else { return nil }
            part.weeks = weeks
            return part
        }
    }

    // MARK: Week markers

    private static var prefixMarker: Regex<(Substring, Substring, Substring)> { /^\s*[\(\[]?\s*([ABab])\s*[\)\]:]\s*(.*)$/ } // Regex is not Sendable

    private static func weekGroups(_ text: String) -> [(Set<Int>?, [String])] {
        var lines: [String] = []
        for line in text.split(separator: "\n").map(String.init) {
            let halves = line.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            if halves.count == 2, halves.allSatisfy({ marker($0) != nil }) { lines += halves } else { lines.append(line) }
        }
        guard lines.contains(where: { marker($0) != nil }) else { return [(nil, lines)] }
        // "A: MAT" opens a group that the following lines join; a bare "(A)" closes the unmarked lines before it.
        var groups: [(Set<Int>?, [String])] = []
        var open: Int?
        var pending: [String] = []
        for line in lines {
            if let (week, rest) = marker(line) {
                if rest.isEmpty, !pending.isEmpty {
                    groups.append(([week], pending))
                    open = nil
                } else {
                    groups.append(([week], pending + (rest.isEmpty ? [] : [rest])))
                    open = groups.count - 1
                }
                pending = []
            } else if let open {
                groups[open].1.append(line)
            } else {
                pending.append(line)
            }
        }
        if !pending.isEmpty { groups[groups.count - 1].1 += pending }
        return groups
    }

    private static func marker(_ line: String) -> (Int, String)? {
        if let match = line.wholeMatch(of: prefixMarker) {
            return (match.output.1.uppercased() == "A" ? 1 : 2, String(match.output.2).trimmingCharacters(in: .whitespaces))
        }
        // "MAT 204 (A)": checked by hand, a lazy-prefix regex is quadratic on long text.
        let chars = Array(line.trimmingCharacters(in: .whitespaces).suffix(3))
        if chars.count == 3, "([".contains(chars[0]), ")]".contains(chars[2]), "ABab".contains(chars[1]) {
            let rest = line.trimmingCharacters(in: .whitespaces).dropLast(3)
            return (chars[1].uppercased() == "A" ? 1 : 2, rest.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    // MARK: Fields

    private static var bracketed: Regex<(Substring, Substring)> { /[\(\[]([^\)\]]{1,12})[\)\]]/ } // Regex is not Sendable
    /// "204", "3P1", "H5S1", "B-204", "C1.04", "2O4" (a letter or two, then a digit). Not "TPVAJ1" or "ANJ1".
    private static var roomToken: Regex<Substring> { /[A-Za-zÀ-ž]{0,2}[-.]?[0-9][A-Za-z0-9.\/-]{0,6}/ } // Regex is not Sendable
    private static var personName: Regex<(Substring, Substring?)> { /\p{Lu}\p{Ll}+(\s\p{Lu}\p{Ll}+){1,2}|\p{Lu}\.\s?\p{Lu}\p{Ll}+|\p{Lu}\p{Ll}+,?\s\p{Lu}\./ } // Regex is not Sendable
    private static let suffixTitles: Set<String> = ["phd", "csc", "msc", "mba", "dis", "bsc", "drsc"]

    static func isRoomToken(_ token: String) -> Bool {
        token.count >= 2 && token.wholeMatch(of: roomToken) != nil && token.wholeMatch(of: /\d{1,2}\./) == nil
    }

    private static func isRoomWord(_ token: String) -> Bool {
        ImportVocabulary.roomWords.contains(ImportText.fold(token).trimmingCharacters(in: CharacterSet(charactersIn: ".,:")))
    }

    /// A whole line that is a room: "204", "Aula", "Room 12", "uč. 12".
    private static func isRoomPhrase(_ line: String) -> Bool {
        let tokens = line.split(separator: " ").map(String.init)
        if tokens.count == 1 { return isRoomToken(tokens[0]) || isRoomWord(tokens[0]) }
        return tokens.count <= 3 && isRoomWord(tokens[0]) // "Lab 2", "Sala de sport"
    }

    private static func fields(_ lines: [String], options: ImportParserOptions, languages: [String]) -> Part {
        var part = Part()
        var typeText: String?
        var subjectParts: [String] = []
        for raw in lines {
            var line = raw.trimmingCharacters(in: .whitespaces)
            for match in line.matches(of: bracketed).reversed() where part.lessonType == nil {
                if let type = ImportVocabulary.lessonType(String(match.output.1), bracketed: true, languages: languages) {
                    part.lessonType = type
                    typeText = String(match.output.0)
                    line.removeSubrange(match.range)
                }
            }
            line = line.split(separator: " ").joined(separator: " ")
            guard !line.isEmpty else { continue }
            if part.teacher == nil, let (before, teacher) = teacherSpan(line) {
                part.teacher = teacher
                line = before
                guard !line.isEmpty else { continue }
            }
            let firstContent = subjectParts.isEmpty
            if !firstContent, part.lessonType == nil, !line.contains(" "),
               let type = ImportVocabulary.lessonType(line, bracketed: false, languages: languages) {
                part.lessonType = type
                typeText = line
                continue
            }
            if !firstContent, part.room == nil, isRoomPhrase(line) {
                part.room = line
                continue
            }
            var tokens = line.split(separator: " ").map(String.init)
            while tokens.count > 1 {
                let last = tokens[tokens.count - 1]
                if part.room == nil, tokens.count > 2, isRoomWord(tokens[tokens.count - 2]), last.count <= 6 {
                    part.room = tokens.suffix(2).joined(separator: " ") // "sala 12"
                    tokens.removeLast(2)
                } else if part.room == nil, isRoomToken(last) || isRoomWord(last) {
                    part.room = last
                    tokens.removeLast()
                } else if part.lessonType == nil, last.count <= 5,
                          let type = ImportVocabulary.lessonType(last, bracketed: false, languages: languages) {
                    part.lessonType = type
                    typeText = last
                    tokens.removeLast()
                } else {
                    break
                }
            }
            subjectParts.append(tokens.joined(separator: " "))
        }

        part.subject = subjectParts.first ?? ""
        for extra in subjectParts.dropFirst() {
            if part.room == nil, !extra.contains(" "), extra.count <= 6 {
                part.room = extra // aSc puts the room on the line under the subject
            } else if part.teacher == nil, extra.wholeMatch(of: personName) != nil {
                part.teacher = extra
            } else {
                part.notes.append(extra)
                part.reasons.insert(.ambiguousSplit)
                part.alternatives.append(ImportAlternative(field: .subject, kind: .split,
                                                           values: [part.subject, part.subject + " " + extra]))
            }
        }
        if part.subject.isEmpty, let room = part.room {
            part.subject = room // a cell with only a room-like text: keep it, but ask
            part.room = nil
            part.reasons.insert(.ambiguousSplit)
        }
        if let room = part.room {
            let fixed = fixLookAlikes(room)
            if fixed != room {
                part.room = fixed
                part.reasons.insert(.ocrConfusion)
                part.alternatives.append(ImportAlternative(field: .room, kind: .ocrReading, values: [fixed, room]))
            }
        }
        // Hidden fields go to notes, never lost.
        if !options.enabledFields.contains(.room), let room = part.room { part.notes.append(room); part.room = nil }
        if !options.enabledFields.contains(.teacher), let teacher = part.teacher { part.notes.append(teacher); part.teacher = nil }
        if !options.enabledFields.contains(.lessonType), part.lessonType != nil {
            part.notes.append(typeText ?? part.lessonType!.rawValue)
            part.lessonType = nil
        }
        abbreviation(&part, known: options.knownSubjects)
        return part
    }

    /// (text before the teacher, teacher) when `line` names one ("Mgr. Kováčová", "Novák, PhD.", "田中先生").
    private static func teacherSpan(_ line: String) -> (String, String)? {
        for suffix in ["先生", "老师", "老師"] where line.hasSuffix(suffix) && line.count > suffix.count { return ("", line) }
        let tokens = line.split(separator: " ").map(String.init)
        for (index, token) in tokens.enumerated() {
            let word = ImportText.fold(token).trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            if suffixTitles.contains(word), index > 0 {
                let start = index - 1
                return (tokens[..<start].joined(separator: " "), tokens[start...].joined(separator: " "))
            }
            guard ImportVocabulary.teacherTitles.contains(word), index + 1 < tokens.count,
                  tokens[index + 1].first?.isUppercase == true else { continue }
            var teacher = Array(tokens[index...])
            var before = Array(tokens[..<index])
            if teacher.count > 2, isRoomToken(teacher.last!) { before.append(teacher.removeLast()) }
            return (before.joined(separator: " "), teacher.joined(separator: " "))
        }
        return nil
    }

    /// Room look-alikes: O/o → 0 and l/I → 1 next to a digit ("2O4" → "204").
    static func fixLookAlikes(_ room: String) -> String {
        let chars = Array(room)
        var out = chars
        for index in chars.indices {
            // Between two digits only: "I3" (informatics room 3) stays, "2O4" becomes "204".
            let between = index > 0 && chars[index - 1].isNumber && index + 1 < chars.count && chars[index + 1].isNumber
            guard between else { continue }
            switch chars[index] {
            case "O", "o": out[index] = "0"
            case "l", "I": out[index] = "1"
            default: break
            }
        }
        return String(out)
    }

    /// "Bio" → question "Is “Bio” Biology?" when exactly one known subject starts with it or has it as initials.
    private static func abbreviation(_ part: inout Part, known: [String]) {
        let subject = ImportText.fold(part.subject).replacingOccurrences(of: ".", with: "")
        guard subject.count >= 2, !known.isEmpty else { return }
        if let exact = known.first(where: { ImportText.fold($0) == ImportText.fold(part.subject) }) {
            part.subject = exact
            return
        }
        let matches = known.filter { name in
            let folded = ImportText.fold(name)
            let initials = String(folded.split(whereSeparator: { !$0.isLetter }).compactMap(\.first))
            return (folded.hasPrefix(subject) && folded.count > subject.count) || (initials.count >= 2 && initials == subject)
        }
        guard matches.count == 1 else { return }
        part.reasons.insert(.abbreviation)
        part.alternatives.append(ImportAlternative(field: .subject, kind: .abbreviation, values: [part.subject, matches[0]]))
    }
}
