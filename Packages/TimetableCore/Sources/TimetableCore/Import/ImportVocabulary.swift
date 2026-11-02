import Foundation

/// Day names, lesson-type words and room words in the 12 app languages (en sk cs pl hu ro de fr uk sr ja zh), matched
/// after `ImportText.fold` (so missing diacritics match too). Ambiguous abbreviations ("St" = Streda/Štvrtok,
/// "So" = Sobota/Sonntag, "Di" = Dienstag/dimanche) keep every candidate; `TimetableImportParser` picks by order.
enum ImportVocabulary {
    /// Monday … Sunday per language: full names first, then abbreviations.
    private static let dayNames: [[String]] = [
        // Monday
        ["monday", "mon", "mo", "pondelok", "po", "pondeli", "poniedzialek", "pon", "pn", "hetfo", "h", "he", "luni", "lu",
         "montag", "lundi", "lun", "понеділок", "пн", "понедељак", "пон", "ponedeljak", "月曜日", "月曜", "月",
         "星期一", "周一", "週一", "礼拜一", "禮拜一"],
        // Tuesday
        ["tuesday", "tue", "tues", "tu", "utorok", "ut", "utery", "wtorek", "wt", "kedd", "k", "ke", "marti", "ma",
         "dienstag", "di", "mardi", "mar", "вівторок", "вт", "уторак", "уто", "utorak", "uto", "火曜日", "火曜", "火",
         "星期二", "周二", "週二", "礼拜二", "禮拜二"],
        // Wednesday
        ["wednesday", "wed", "we", "streda", "st", "streda", "sroda", "sr", "szerda", "sze", "sz", "miercuri", "mi",
         "mittwoch", "mercredi", "mer", "me", "середа", "ср", "среда", "сре", "sreda", "sre", "水曜日", "水曜", "水",
         "星期三", "周三", "週三", "礼拜三", "禮拜三"],
        // Thursday
        ["thursday", "thu", "thur", "thurs", "th", "stvrtok", "st", "ctvrtek", "ct", "czwartek", "czw", "cz", "csutortok",
         "cs", "csut", "joi", "jo", "donnerstag", "do", "jeudi", "jeu", "je", "четвер", "чт", "четвртак", "чет",
         "cetvrtak", "cet", "木曜日", "木曜", "木", "星期四", "周四", "週四", "礼拜四", "禮拜四"],
        // Friday
        ["friday", "fri", "fr", "piatok", "pi", "patek", "pa", "piatek", "pt", "pia", "pentek", "p", "pe", "vineri",
         "vi", "freitag", "vendredi", "ven", "ve", "пʼятниця", "п'ятниця", "пятниця", "пт", "петак", "пет", "petak", "pet",
         "金曜日", "金曜", "金", "星期五", "周五", "週五", "礼拜五", "禮拜五"],
        // Saturday
        ["saturday", "sat", "sa", "sobota", "so", "sob", "szombat", "szo", "szom", "sambata", "sam", "samstag", "samedi",
         "субота", "сб", "суб", "subota", "sub", "土曜日", "土曜", "土", "星期六", "周六", "週六", "礼拜六", "禮拜六"],
        // Sunday
        ["sunday", "sun", "su", "nedela", "ne", "nedele", "niedziela", "nd", "niedz", "vasarnap", "v", "va", "duminica",
         "du", "sonntag", "so", "dimanche", "dim", "di", "неділя", "нд", "недеља", "нед", "nedelja", "ned", "日曜日",
         "日曜", "日", "星期日", "星期天", "周日", "週日", "礼拜日", "禮拜日", "礼拜天"],
    ]

    private static let dayIndex: [String: Set<Weekday>] = {
        var index: [String: Set<Weekday>] = [:]
        for (offset, names) in dayNames.enumerated() {
            for name in names { index[ImportText.fold(name), default: []].insert(Weekday(rawValue: offset + 1)!) }
        }
        return index
    }()

    /// Full names (≥ 5 letters) for prefix matches such as "Pond." or "Donn".
    private static let fullNames: [(String, Weekday)] = dayNames.enumerated().flatMap { offset, names in
        names.map(ImportText.fold).filter { $0.count >= 5 }.map { ($0, Weekday(rawValue: offset + 1)!) }
    }

    /// The weekdays `text` may name; empty when it is not a day label. Reads the first line, ignores brackets and
    /// trailing dots ("(月)", "Po.", "Mon,"). A label followed by a date ("Po 1.9.") still matches.
    static func days(in text: String) -> Set<Weekday> {
        guard let line = text.split(separator: "\n").first else { return [] }
        var word = ImportText.fold(String(line))
        word = word.trimmingCharacters(in: CharacterSet(charactersIn: "()[]（）.,:;-–— "))
        if let hit = dayIndex[word] { return hit }
        if let first = word.split(separator: " ").first, first.count < word.count {
            let head = String(first).trimmingCharacters(in: CharacterSet(charactersIn: "()[]（）.,:;"))
            if let hit = dayIndex[head], head.count >= 2 || !head.allSatisfy(\.isASCII) { return hit }
        }
        guard word.count >= 3, word.allSatisfy(\.isLetter) else { return [] }
        let hits = Set(fullNames.filter { $0.0.hasPrefix(word) }.map(\.1))
        return hits.count == 1 ? hits : []
    }

    // MARK: Lesson types

    /// Words (folded) that name a lesson type in any language.
    private static let typeWords: [LessonType: [String]] = [
        .lecture: ["lecture", "lect", "lec", "prednaska", "pred", "prednasky", "vorlesung", "vl", "wyklad", "eloadas", "ea",
                   "curs", "cours", "cm", "лекція", "лекция", "лек", "предавање", "predavanje", "講義", "讲座", "讲课", "講課"],
        .seminar: ["seminar", "sem", "seminare", "seminarium", "seminaire", "семінар", "семинар", "семинар", "ゼミ", "研讨课", "討論課"],
        .lab: ["lab", "laboratory", "labs", "laboratorium", "laboratorne", "labor", "laborator", "tp", "лаб", "лабораторна",
               "лабораторија", "実験", "实验", "實驗"],
        .tutorial: ["tutorial", "tut", "cvicenie", "cviceni", "cv", "cvic", "cwiczenia", "cw", "ubung", "ub", "ue", "gyakorlat",
                    "gyak", "gy", "td", "practica", "practical", "практичне", "практ", "вежбе", "vezbe", "演習", "习题课", "習題課"],
    ]

    /// Single-letter type codes, only trusted in brackets ("(P)") and only for the table's language.
    private static let typeLetters: [String: [String: LessonType]] = [
        "sk": ["p": .lecture, "c": .tutorial, "s": .seminar, "l": .lab],
        "cs": ["p": .lecture, "c": .tutorial, "s": .seminar, "l": .lab],
        "pl": ["w": .lecture, "c": .tutorial, "s": .seminar, "l": .lab],
        "ro": ["c": .lecture, "s": .seminar, "l": .lab],
        "hu": ["e": .lecture, "g": .tutorial, "l": .lab],
        "de": ["v": .lecture, "u": .tutorial, "s": .seminar, "p": .lab],
        "en": ["l": .lecture, "t": .tutorial, "s": .seminar],
    ]

    private static let typeIndex: [String: LessonType] = {
        var index: [String: LessonType] = [:]
        for (type, words) in typeWords { for word in words { index[ImportText.fold(word)] = type } }
        return index
    }()

    /// The lesson type `token` names. `bracketed` allows single-letter codes of `languages`.
    static func lessonType(_ token: String, bracketed: Bool, languages: [String]) -> LessonType? {
        let word = ImportText.fold(token).trimmingCharacters(in: CharacterSet(charactersIn: "()[]（）.,:;"))
        if let type = typeIndex[word] { return type }
        guard bracketed, word.count == 1 else { return nil }
        for language in languages {
            let code = String(language.prefix(2)).lowercased()
            if let type = typeLetters[code]?[word] { return type }
        }
        return nil
    }

    // MARK: Rooms and teachers

    /// Words that are rooms on their own ("Aula", "Gym") or introduce one ("Room 12", "uč. 12").
    static let roomWords: Set<String> = Set([
        "aula", "auditorium", "gym", "hall", "telocvicna", "lab", "labo", "poslucharen", "ucebna", "uc", "miestnost", "mistnost",
        "room", "rm", "raum", "turnhalle", "sporthalle", "sala", "sali", "salle", "gymnase", "terem", "tornaterem",
        "tornacsarnok", "amfi", "amfiteatru", "amfiteatr", "kab", "kabinet", "аудиторія", "ауд", "кабінет", "каб", "лаб",
        "спортзал", "учионица", "сала", "ucionica", "fiskulturna", "教室", "体育館", "体育馆", "礼堂", "講堂", "讲堂",
    ].map(ImportText.fold))

    /// Academic and courtesy titles that mark a teacher.
    static let teacherTitles: Set<String> = Set([
        "mgr", "ing", "bc", "dr", "phdr", "rndr", "paeddr", "mudr", "judr", "doc", "prof", "phd", "mr", "mrs", "ms",
        "miss", "herr", "frau", "mme", "mlle", "inz", "pan", "pani", "dott", "пан", "пані", "доц", "проф", "д-р", "др",
    ].map(ImportText.fold))
}
