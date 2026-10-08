import Foundation
import TimetableCore

/// `EngineDemo <output.html> [Localizable.xcstrings]` — builds the sample scenario with TimetableCore, writes the
/// HTML report and prints a short text summary (the evidence line for CI logs and agent reports).
@main
struct EngineDemo {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("\(DemoError.usage)\n".utf8))
            exit(2)
        }
        do {
            let scenario = try Scenario.build()
            let catalog = args.count >= 3 ? StringCatalog(path: args[2]) : .empty
            let html = Report(s: scenario, catalog: catalog).render()
            try Data(html.utf8).write(to: URL(fileURLWithPath: args[1]))
            for line in summary(scenario, catalog: catalog, bytes: html.utf8.count, path: args[1]) { print(line) }
        } catch {
            FileHandle.standardError.write(Data("EngineDemo failed: \(error)\n".utf8))
            exit(1)
        }
    }

    static func summary(_ s: Scenario, catalog: StringCatalog, bytes: Int, path: String) -> [String] {
        let nn = s.nowNext
        func name(_ lesson: ResolvedLesson?) -> String {
            guard let lesson else { return "none" }
            return "\(lesson.subject.shortName ?? lesson.subject.name) \(lesson.date) \(lesson.startTime)-\(lesson.endTime)"
        }
        let thursday = s.resolutions[s.overrideDate]?.schedule.entries ?? []
        let statuses = Dictionary(grouping: thursday, by: \.status).map { "\($0.key.rawValue)=\($0.value.count)" }.sorted()
        return [
            "wrote \(path) (\(bytes) bytes); catalog keys loaded: \(catalog.count)",
            "week \(s.thisWeek.weekStart.map(\.description) ?? "?"): label \(s.thisWeek.cycleLabel ?? "nil") (cycle week \(s.thisWeek.cycleWeek ?? 0)); "
                + "week \(s.nextWeek.weekStart.map(\.description) ?? "?"): label \(s.nextWeek.cycleLabel ?? "nil") (cycle week \(s.nextWeek.cycleWeek ?? 0))",
            "now/next: current \(name(nn.current)), remaining \(Int((nn.remaining ?? 0) / 60)) min; next \(name(nn.next)), in \(Int((nn.untilNext ?? 0) / 60)) min",
            "overrides \(s.overrideDate): \(statuses.joined(separator: ", "))",
            "reminders: \(s.plan.notifications.count) notifications, \(s.plan.alarms.count) alarms, \(s.plan.dropped.count) dropped, saturated \(s.plan.isSaturated)",
            "share: json \(s.shareEnvelope.jsonByteCount) B, compressed \(s.shareEnvelope.compressedByteCount) B, route \(s.shareEnvelope.route.rawValue), "
                + "inline link \(s.inlineLink.utf8.count) chars, sample code \(s.sampleCode.formatted)",
            "validation: \(s.issues.count) issues; schema v\(s.db.schemaVersion); db json \(s.jsonBytes) B; round-trip equal \(s.roundTripEqual)",
        ]
    }
}
