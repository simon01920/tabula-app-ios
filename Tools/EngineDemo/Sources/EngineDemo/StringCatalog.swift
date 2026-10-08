import Foundation
import TimetableCore

/// Reads the English values of `Resources/Localizable.xcstrings` so the report can show what a `LocalizedText`
/// key would read like. This is an approximation for inspection only: the app formats arguments with the user's
/// locale (dates, times, plural rules); here plural = "one" when the first integer argument is 1, else "other".
struct StringCatalog {
    private struct Entry {
        var one: String?
        var other: String
    }

    private var entries: [String: Entry] = [:]
    private(set) var isLoaded = false

    static let empty = StringCatalog()

    private init() {}

    init(path: String) {
        guard let data = FileManager.default.contents(atPath: path),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let strings = root["strings"] as? [String: Any] else { return }
        for (key, value) in strings {
            guard let entry = value as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any],
                  let english = localizations["en"] as? [String: Any] else { continue }
            if let unit = english["stringUnit"] as? [String: Any], let text = unit["value"] as? String {
                entries[key] = Entry(one: nil, other: text)
            } else if let variations = english["variations"] as? [String: Any],
                      let plural = variations["plural"] as? [String: Any] {
                func form(_ name: String) -> String? {
                    ((plural[name] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
                }
                if let other = form("other") { entries[key] = Entry(one: form("one"), other: other) }
            }
        }
        isLoaded = !entries.isEmpty
    }

    var count: Int { entries.count }

    /// The English rendering of `text`, or `nil` when the key is not in the catalog.
    func english(_ text: LocalizedText, format: (LocalizedArgument) -> String) -> String? {
        guard let entry = entries[text.key] else { return nil }
        let firstInteger = text.args.lazy.compactMap { argument -> Int? in
            if case .integer(let value) = argument { return value }
            return nil
        }.first
        let pattern = (firstInteger == 1 ? entry.one : nil) ?? entry.other
        let rendered = text.args.map { argument -> String in
            if case .text(let nested) = argument { return english(nested, format: format) ?? nested.description }
            return format(argument)
        }
        return Self.substitute(pattern, rendered)
    }

    /// Replaces `%@`, `%lld`, `%d`, `%ld` and their positional forms (`%2$@`) with `args`; `%%` → `%`.
    static func substitute(_ pattern: String, _ args: [String]) -> String {
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
            while scan < pattern.endIndex, pattern[scan].isNumber {
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
                result += args.indices.contains(argIndex) ? args[argIndex] : "?"
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
