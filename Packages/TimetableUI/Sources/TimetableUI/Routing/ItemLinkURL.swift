// URL form of `ItemLink` (the app's deep-link value) for widget taps (`widgetURL` / `Link`), later Live Activities
// and App Shortcuts: the system activates the app and passes the URL to SwiftUI's `onOpenURL` (WidgetKit article
// "Linking to specific app scenes from your widget or Live Activity", checked 2026-10-16), where
// `AppNavigation.open(_:)` handles it like a notification tap (no new routing).
//
//   tabula://open/today                      → Today tab
//   tabula://open/lesson/<OccurrenceID>      → the lesson's tab (as a notification tap)
//   tabula://open/task/<UUID>                → Tasks tab + task detail
//   tabula://open/exam/<UUID>                → Exams tab + exam detail
//   tabula://open/pack/<yyyy-MM-dd>          → Today tab ("pack tonight")
//
// Parsing is strict (scheme, host, component count, UUID / date / occurrence-ID shape, length): any URL can be sent
// to the app by other apps or web pages, so a malformed one is ignored. Opening a link only navigates; it never
// changes data. Pure, Linux-tested.
import Foundation
import TimetableCore

public enum ItemLinkURL {
    /// URL scheme.
    public static let scheme = "tabula"
    /// Host of navigation links.
    public static let host = "open"
    /// Longest accepted URL (characters).
    static let maxLength = 200

    /// The URL of `link`.
    public static func url(for link: ItemLink) -> URL {
        let path: String
        switch link {
        case .today: path = "today"
        case .lesson(let id): path = "lesson/" + id.rawValue
        case .task(let id): path = "task/" + id.uuidString
        case .exam(let id): path = "exam/" + id.uuidString
        case .packTonight(let date): path = "pack/" + date.isoString
        }
        // Every component is [A-Za-z0-9:-] (validated shapes), so no percent-encoding is needed.
        return URL(string: "\(scheme)://\(host)/\(path)")!
    }

    /// The link a URL names, or `nil` for anything that is not a well-formed Tabula navigation link.
    public static func link(from url: URL) -> ItemLink? {
        let text = url.absoluteString
        guard text.count <= maxLength, url.scheme?.lowercased() == scheme, url.host?.lowercased() == host,
              url.query == nil, url.fragment == nil else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
        switch parts.count {
        case 1 where parts[0] == "today":
            return .today
        case 2:
            let value = parts[1]
            switch parts[0] {
            case "lesson": return isOccurrenceID(value) ? .lesson(OccurrenceID(rawValue: value)) : nil
            case "task": return UUID(uuidString: value).map { .task(TaskItem.ID($0)) }
            case "exam": return UUID(uuidString: value).map { .exam(Exam.ID($0)) }
            case "pack": return LocalDate(value).flatMap { $0.isoString == value ? .packTonight($0) : nil }
            default: return nil
            }
        default:
            return nil
        }
    }

    /// `lesson:<UUID>:<yyyy-MM-dd>` or `override:<UUID>` (the `OccurrenceID` formats).
    static func isOccurrenceID(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        switch parts.first {
        case "lesson":
            return parts.count == 3 && UUID(uuidString: parts[1]) != nil
                && LocalDate(parts[2]).map { $0.isoString == parts[2] } == true
        case "override":
            return parts.count == 2 && UUID(uuidString: parts[1]) != nil
        default:
            return false
        }
    }
}
