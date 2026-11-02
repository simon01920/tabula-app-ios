// Whether the import may use Apple Intelligence (AI_IMPORT Tier A, PHASE9_PLAN decision 1): the on-device
// `SystemLanguageModel` must be available AND support the current locale. Shown in Settings › Import and on the
// import screen ("Uses Apple Intelligence on this iPhone" only when `.available`).
// API names checked in iPhoneOS27.0.sdk FoundationModels.swiftinterface (2026-11-02): SystemLanguageModel.default,
//   .availability (.available / .unavailable(.deviceNotEligible | .appleIntelligenceNotEnabled | .modelNotReady)),
//   supportsLocale(_:) (default Locale.current). All iOS 26.0.
import FoundationModels

enum AppleIntelligenceStatus: Equatable, Sendable {
    case available
    case notEnabled
    case languageNotSupported
    case deviceNotEligible
    case notReady

    static var current: AppleIntelligenceStatus {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available: return model.supportsLocale() ? .available : .languageNotSupported
        case .unavailable(.deviceNotEligible): return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): return .notEnabled
        case .unavailable: return .notReady   // .modelNotReady and reasons added later
        }
    }

    /// Catalog key of the short status ("Available", "Not turned on", …).
    var valueKey: String {
        switch self {
        case .available: return "import.ai.status.available"
        case .notEnabled: return "import.ai.status.notEnabled"
        case .languageNotSupported: return "import.ai.status.language"
        case .deviceNotEligible: return "import.ai.status.device"
        case .notReady: return "import.ai.status.notReady"
        }
    }

    /// Catalog key of the one-sentence explanation under the status.
    var footerKey: String {
        switch self {
        case .available: return "import.ai.footer.available"
        case .notEnabled: return "import.ai.footer.notEnabled"
        case .languageNotSupported: return "import.ai.footer.language"
        case .deviceNotEligible: return "import.ai.footer.device"
        case .notReady: return "import.ai.footer.notReady"
        }
    }
}
