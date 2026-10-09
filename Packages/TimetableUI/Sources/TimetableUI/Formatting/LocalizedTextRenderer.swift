// Renders TimetableCore's `LocalizedText` (catalog key + typed arguments) into a user-facing string.
// Core never contains user-facing text; this is the one place where its keys meet the String Catalog.
//
// - The catalog value for the key is the *format* (`"Exam: %@"`, plural variations for `%lld`), looked up through
//   the injected `lookup` (the app passes `Bundle.main`, so `-AppleLanguages` and the per-app language apply).
// - Arguments are formatted with `TimetableFormatter` (dates, times honour locale and 12/24 h), nested
//   `LocalizedText` arguments are rendered recursively, user text is inserted verbatim. Nothing is concatenated:
//   the whole sentence comes from one catalog format.
// - On Apple platforms the format is applied with `String(format:locale:arguments:)`, which evaluates the plural
//   variations compiled into `.stringsdict`. Elsewhere (Linux tests) a plain positional substitution is used:
//   plural choice is then NOT exercised (device checklist: Slovak "1 hodina · 3 hodiny · 5 hodín").
import Foundation
import TimetableCore

/// One formatted argument for a catalog format.
public enum CatalogArgument: Sendable, Equatable {
    /// For `%lld` / `%ld` / `%d` (plural variations select on it).
    case integer(Int64)
    /// For `%@`.
    case text(String)
}

/// Renders `LocalizedText` with a catalog lookup and a formatter.
public struct LocalizedTextRenderer: Sendable {
    /// Returns the catalog value (format) for a key, or the key itself when missing (Bundle behaviour).
    public typealias Lookup = @Sendable (String) -> String

    private let lookup: Lookup
    /// Formatter used for date and time arguments.
    public let formatter: TimetableFormatter

    /// Creates a renderer.
    public init(formatter: TimetableFormatter, lookup: @escaping Lookup) {
        self.formatter = formatter
        self.lookup = lookup
    }

    /// The catalog value for `key` without arguments.
    public func string(forKey key: String) -> String { lookup(key) }

    /// The rendered text.
    public func string(_ text: LocalizedText) -> String {
        format(key: text.key, arguments: text.args.map(argument))
    }

    /// Looks up `key` and fills in already-formatted `arguments` (for UI-owned keys with arguments).
    public func format(key: String, arguments: [CatalogArgument]) -> String {
        let pattern = lookup(key)
        guard !arguments.isEmpty else { return pattern }
        return Self.apply(pattern, arguments, locale: formatter.locale)
    }

    /// `true` when the catalog has no value for `key` (the lookup echoed the key back).
    public func isMissing(_ key: String) -> Bool { lookup(key) == key }

    private func argument(_ value: LocalizedArgument) -> CatalogArgument {
        switch value {
        case .string(let text): return .text(text)
        case .integer(let number): return .integer(Int64(number))
        case .date(let date): return .text(formatter.date(date))
        case .time(let time): return .text(formatter.time(time))
        case .text(let nested): return .text(string(nested))
        }
    }

    /// Applies a printf-style catalog format.
    static func apply(_ pattern: String, _ arguments: [CatalogArgument], locale: Locale) -> String {
        #if canImport(Darwin)
        let varArgs: [any CVarArg] = arguments.map { argument -> any CVarArg in
            switch argument {
            case .integer(let number): return number
            case .text(let text): return NSString(string: text)
            }
        }
        return String(format: pattern, locale: locale, arguments: varArgs)
        #else
        return CatalogFormat.substitute(pattern, arguments)
        #endif
    }
}

/// Portable printf-subset substitution used where `String(format:)` cannot evaluate catalog plurals (Linux).
public enum CatalogFormat {
    /// Replaces `%@`, `%lld`, `%ld`, `%d` and their positional forms (`%2$@`) with `arguments`; `%%` → `%`.
    /// A missing argument becomes `?` (never crashes on a bad translation).
    public static func substitute(_ pattern: String, _ arguments: [CatalogArgument]) -> String {
        let rendered = arguments.map { argument -> String in
            switch argument {
            case .integer(let number): return String(number)
            case .text(let text): return text
            }
        }
        var result = ""
        var sequential = 0
        var index = pattern.startIndex
        while index < pattern.endIndex {
            let char = pattern[index]
            guard char == "%" else {
                result.append(char)
                index = pattern.index(after: index)
                continue
            }
            var cursor = pattern.index(after: index)
            guard cursor < pattern.endIndex else { result.append("%"); break }
            if pattern[cursor] == "%" {
                result.append("%")
                index = pattern.index(after: cursor)
                continue
            }
            var digits = ""
            var scan = cursor
            while scan < pattern.endIndex, pattern[scan].isASCII, pattern[scan].isNumber {
                digits.append(pattern[scan])
                scan = pattern.index(after: scan)
            }
            var position: Int?
            if !digits.isEmpty, scan < pattern.endIndex, pattern[scan] == "$" {
                position = Int(digits)
                cursor = pattern.index(after: scan)
            }
            var matched = false
            for spec in ["lld", "ld", "@", "d"] where pattern[cursor...].hasPrefix(spec) {
                let argIndex = (position ?? (sequential + 1)) - 1
                if position == nil { sequential += 1 }
                result += rendered.indices.contains(argIndex) ? rendered[argIndex] : "?"
                index = pattern.index(cursor, offsetBy: spec.count)
                matched = true
                break
            }
            if !matched {
                result.append("%")
                index = pattern.index(after: index)
            }
        }
        return result
    }
}
