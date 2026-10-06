import Foundation

/// The ISO-week → cycle-week mapping behind `WeekCycleAnchor.isoWeekParity`, isolated in one place so the
/// domain decision can be reviewed or rewritten without touching the resolver (PHASE1_PLAN §10).
///
/// Background: Slovak and Czech schools call A/B weeks "odd/even weeks" (nepárny/párny týždeň, lichý/sudý
/// týden). Some schools read the parity off the ISO week number printed in every calendar; others alternate
/// strictly from the start of the school year. Both readings agree until an ISO year with **53 weeks**
/// (2020, 2026, 2032, 2037): there, week 53 and the following week 1 are both odd.
///
/// - `.strict` follows the printed week number: W53 → W01 repeats a cycle week, so from January to the
///   summer the cycle is "swapped" compared with a school that alternates strictly.
/// - `.continuous` alternates strictly inside a school year: the week containing 1 September takes its
///   ISO parity, and every following week flips, until the next 1 September re-anchors (the re-anchoring may
///   repeat or skip a week, but always inside the summer holidays).
public enum WeekParity {
    /// Policy for newly created odd/even-week timetables. **Human review point** (PHASE1_PLAN §10).
    ///
    /// Returns `.strict` for everyone because:
    /// 1. it is what "odd/even week" means literally — any calendar or student diary shows the ISO number,
    ///    so a user can verify it at a glance ("week 41 is odd, so this is week A");
    /// 2. it needs no notion of a school-year start, which differs between countries and universities;
    /// 3. it is the same as `.continuous` in 52-week years, and the 53-week years are rare (next: 2026, 2032);
    ///    a school that alternates strictly fixes January with one switch (policy) instead of shifting `offset`
    ///    twice a year.
    /// The parameters are here so the selection can become region- or profile-specific (e.g. `.continuous`
    /// for `"SK"`/`"CZ"` secondary schools) without changing callers.
    public static func defaultPolicy(for profile: UserProfile, regionCode: String?) -> ISOWeekParityPolicy {
        .strict
    }

    /// The 1-based cycle week (1…`length`) of ISO week `week`.
    ///
    /// - `.strict`: index = ISO week number − 1. With `length == 2`, odd weeks are cycle week 1 and even weeks
    ///   cycle week 2; W53 and the next W01 are both cycle week 1. With other lengths the sequence restarts at
    ///   every W01 as well (a literal reading of the week number).
    /// - `.continuous`: the week containing the school-year start (`schoolYearStartWeek(for:)`) takes its
    ///   strict index; from there the index grows by exactly one per week. No week repeats inside a school
    ///   year; at the next school-year start the index re-anchors to the ISO number.
    /// - `offset` shifts the result: with `length == 2`, offset 1 swaps A and B.
    ///
    /// `length < 1` is treated as 1 (validation reports bad lengths; the resolver must not trap).
    public static func cycleWeek(for week: ISOWeek, policy: ISOWeekParityPolicy, offset: Int, length: Int = 2) -> Int {
        let cycleLength = max(1, length)
        let index: Int
        switch policy {
        case .strict:
            index = week.week - 1
        case .continuous:
            if let start = schoolYearStartWeek(for: week) {
                index = (start.week - 1) + start.monday.days(to: week.monday) / 7
            } else {
                index = week.week - 1 // before year 1 has no previous school year: fall back to strict
            }
        }
        return LocalDate.floorMod(index + offset, cycleLength) + 1
    }

    /// The ISO week containing the school-year start (1 September) of the school year that `week` belongs to.
    ///
    /// A week belongs to the school year whose start week is the latest one not after it, so the whole week
    /// containing 1 September (including any August days in it) is the first week of the new school year —
    /// a week never straddles two school years. `nil` only for weeks before 0001-09-01.
    public static func schoolYearStartWeek(for week: ISOWeek) -> ISOWeek? {
        let year = week.monday.year
        if let start = LocalDate(year: year, month: 9, day: 1)?.isoWeek, start <= week { return start }
        return LocalDate(year: year - 1, month: 9, day: 1)?.isoWeek
    }

    /// The ISO week that represents the user's week containing `date`: the ISO week of the week's middle day
    /// (`startOfWeek + 3`).
    ///
    /// With weeks starting on Monday this is simply `date.isoWeek`. With weeks starting on Sunday or Saturday
    /// (Sun–Thu or Sat–Wed school weeks) the ISO week would split the user's week; the middle day belongs to
    /// the ISO week that holds most of it, so every day of a displayed week gets the same cycle week.
    public static func representativeISOWeek(containing date: LocalDate, firstWeekday: Weekday) -> ISOWeek {
        let offsetInWeek = LocalDate.floorMod(date.weekday.rawValue - firstWeekday.rawValue, 7)
        return date.adding(days: 3 - offsetInWeek).isoWeek
    }
}
