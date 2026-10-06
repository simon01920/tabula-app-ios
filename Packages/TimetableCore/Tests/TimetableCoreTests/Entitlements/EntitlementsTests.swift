import Foundation
import Testing
@testable import TimetableCore

@Suite("Entitlements (Free/Pro split)")
struct EntitlementsTests {
    /// PRODUCT.md "Pro:" items → the `ProFeature`s they map to.
    private let proLineMapping: [String: [ProFeature]] = [
        "unlimited timetables": [.unlimitedTimetables],
        "all widget sizes + Lock Screen + Live Activity": [.largeWidgets, .lockScreenWidgets, .liveActivity],
        "Watch app": [.watchApp],
        "loud alarm reminders": [.loudAlarms],
        "AI import": [.aiImport],
        "exports (image/PDF/CSV/XLSX/ICS)": [.exports],
        "wallpapers/theme packs": [.themePacks],
        "extra attachment capacity": [.extraAttachmentCapacity],
        "statistics": [.statistics],
    ]

    private func line(startingWith prefix: String, in text: String) -> [String]? {
        guard let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix(prefix) }) else { return nil }
        var body = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasSuffix(".") { body.removeLast() }
        // Split on ", " outside parentheses.
        var items: [String] = [], current = "", depth = 0
        for character in body {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            if character == ",", depth == 0 {
                items.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        items.append(current.trimmingCharacters(in: .whitespaces))
        return items
    }

    @Test func proFeaturesMatchProductMdExactly() throws {
        let product = try RepositoryFile.text("docs/specs/PRODUCT.md")
        guard let proItems = line(startingWith: "Pro:", in: product) else {
            Issue.record("PRODUCT.md has no 'Pro:' line")
            return
        }
        #expect(Set(proItems) == Set(proLineMapping.keys), "PRODUCT.md Pro list changed: \(proItems)")
        let mapped = Set(proItems.flatMap { proLineMapping[$0] ?? [] })
        #expect(mapped == Set(ProFeature.allCases))
        #expect(FeaturePolicy.standard.proFeatures == mapped)
    }

    @Test func freeTierMatchesProductMd() throws {
        let product = try RepositoryFile.text("docs/specs/PRODUCT.md")
        guard let freeItems = line(startingWith: "Free:", in: product) else {
            Issue.record("PRODUCT.md has no 'Free:' line")
            return
        }
        #expect(freeItems == ["1 timetable", "grid/day/tile views", "tasks (subtasks, priorities)", "exams",
                              "standard + Time Sensitive reminders", "small/medium widgets", "iCloud sync",
                              "QR/code share and import"], "PRODUCT.md Free list changed: \(freeItems)")
        let free = PolicyEntitlements(tier: .free)
        #expect(free.limit(.maxTimetables) == 1)
        // Nothing in the Free list may be gated.
        #expect(!free.isAllowed(.largeWidgets) && !free.isAllowed(.lockScreenWidgets))
        #expect(ProFeature.allCases.allSatisfy { !free.isAllowed($0) })
    }

    @Test func tiersAndProviders() {
        let free = PolicyEntitlements(tier: .free)
        let pro = PolicyEntitlements(tier: .pro)
        #expect(free.tier == .free && pro.tier == .pro)
        #expect(ProFeature.allCases.allSatisfy { pro.isAllowed($0) })
        #expect(pro.limit(.maxTimetables) == nil)
        #expect(free.limit(.attachmentQuotaMB) == 100 && pro.limit(.attachmentQuotaMB) == 2_000)
        let all = AllAccessEntitlements()
        #expect(all.tier == .pro && ProFeature.allCases.allSatisfy { all.isAllowed($0) })
        #expect(Limit.allCases.allSatisfy { all.limit($0) == nil })
        let providers: [any EntitlementsProvider] = [free, pro, all]
        #expect(providers.map(\.tier) == [.free, .pro, .pro])
    }

    @Test func customPolicyChangesTheSplitWithoutCodeChanges() {
        let generous = FeaturePolicy(proFeatures: [.aiImport], limits: [.free: [.maxTimetables: 3]])
        let free = PolicyEntitlements(tier: .free, policy: generous)
        #expect(free.isAllowed(.watchApp) && !free.isAllowed(.aiImport))
        #expect(free.limit(.maxTimetables) == 3 && free.limit(.attachmentQuotaMB) == nil)
    }
}
