// Small shared pieces of the Settings screens (Phase 4U U5a).
//
//   SettingsIconTile / SettingsRowLabel  Apple-Settings-style row icon: a white SF Symbol on a rounded coloured square
//                                        (HIG lists-and-tables, labels: an icon next to the title, the title stays text).
//   SettingsPushedEditor                 hosts an editor written for a sheet (it brings its own NavigationStack and its
//                                        own Cancel / Save or Done bar) as a PUSHED Settings destination.
//   HealthStatusIcon                     one status symbol + colour + accessible word for every reminder-check surface.
//   AppLinks                             PLACEHOLDER contact / privacy / review targets (see the type).
//
// "Adopt U1": the tile colours, symbols and the status colours are local stand-ins; replace them with the U1 tokens
// (`DesignTokens`) and `AppSymbol` once those land. Every use is a one-line change inside these types.
import SwiftUI
import TimetableCore
import TimetableUI

// MARK: - Row icons

/// The decorative icon of a Settings row. Hidden from VoiceOver: the row title carries the meaning.
struct SettingsIconTile: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// `Label` with a `SettingsIconTile`. Use for every row of the Settings root.
struct SettingsRowLabel: View {
    let title: Text
    let symbol: String
    let color: Color

    init(_ key: LocalizedStringKey, symbol: String, color: Color) {
        self.title = Text(key)
        self.symbol = symbol
        self.color = color
    }

    init(verbatim text: String, symbol: String, color: Color) {
        self.title = Text(verbatim: text)
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        Label { title } icon: { SettingsIconTile(symbol: symbol, color: color) }
    }
}

// MARK: - Pushed editors

/// Shows a sheet-style editor as a pushed destination of the Settings `NavigationStack`.
///
/// The editors of `App/Sources/Editors` (stage U5b owns them) wrap themselves in their own `NavigationStack` and put
/// Cancel / Save (or Done) in it, because they were written for sheets. Pushed as they are, the outer bar would stack on
/// the inner one, so the OUTER bar is hidden here and the editor's own bar is the only one. Its Cancel / Save / Done call
/// `dismiss()`, which in a pushed destination pops back to Settings. Nothing inside the editor is edited or changed.
///
/// UNVERIFIED without a device (nested stacks, the edge-swipe back gesture with a hidden outer bar, and `dismiss()` popping
/// from the inner stack). The clean fix is for U5b to offer an "embedded" mode (no own stack, no Cancel/Save): then
/// this wrapper becomes `content()`.
struct SettingsPushedEditor<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Reminder check status

/// Status symbol of a reminder check row. Shape differs per status and the accessible label is the status word, so colour
/// is never the only carrier and no status word has to be printed next to the icon (M28). Warnings are always orange.
struct HealthStatusIcon: View {
    let status: ReminderHealthStatus

    static func color(_ status: ReminderHealthStatus) -> Color {
        switch status {
        case .ok: return .green
        case .info: return .secondary
        case .warning: return .orange
        case .problem: return .red
        }
    }

    var body: some View {
        Image(systemName: ReminderHealthPresentation.symbol(status))
            .foregroundStyle(Self.color(status))
            .accessibilityLabel(Text(LocalizedStringKey(ReminderHealthPresentation.statusKey(status))))
    }
}

// MARK: - Links (placeholders)

/// Targets of the About & Feedback rows.
///
/// PLACEHOLDERS (L4): there is no support mailbox, privacy page or App Store listing yet (paid account deferred,
/// docs/RISKS.md). Replace the three constants before TestFlight. The Rate row is absent while `reviewURL` is `nil`
/// (field rule: a row with nothing to show is not shown); set it to
/// `https://apps.apple.com/app/id<APP_ID>?action=write-review` once the app has an App Store ID.
enum AppLinks {
    /// PLACEHOLDER mailbox (the reserved `.invalid` top-level domain never resolves).
    static let feedbackEmail = "feedback@tabula-app.invalid"
    /// PLACEHOLDER privacy policy page.
    static let privacyPolicyURL = URL(string: "https://tabula-app.invalid/privacy")
    /// PLACEHOLDER until the App Store listing exists.
    static let reviewURL: URL? = nil

    /// `mailto:` link for the feedback row; the subject names the app version.
    static func feedbackURL(version: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        if let version { components.queryItems = [URLQueryItem(name: "subject", value: "Tabula \(version)")] }
        return components.url
    }
}
