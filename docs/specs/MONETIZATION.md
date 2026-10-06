# MONETIZATION

## Offer (human's decision)
- Monthly €1.99 · Yearly €11.99 · Lifetime €24.99 (one-time, non-consumable).
- One subscription group with two durations + one non-consumable. Consider a short free trial on yearly (decide at gate). Show `Product.displayPrice`; never hardcode prices. Verify that these EUR price points exist in App Store Connect and how they convert for other storefronts.

## Free vs Pro
See PRODUCT.md proposal. All gating goes through `Entitlements` (feature enum → allowed?), so the split can change without refactoring. Core promise stays free: a usable timetable, tasks, exams, reminders, iCloud sync and share/import.

## Implementation
StoreKit 2: `Product.products(for:)`, `Transaction.currentEntitlements`, `Transaction.updates`, restore, Family Sharing decision (lifetime yes/no — decide at gate), offline grace using cached entitlement with expiry, no server receipt validation. Paywall: honest, localised, shows what is included, no dark patterns, clear renewal/cancel text (App Review requires this).

## Process notes
- No Xcode StoreKit testing locally → plan sandbox testing through TestFlight builds. Provide the human a precise App Store Connect checklist (agreements/tax/banking, subscription group, product IDs, localisations, review screenshot).
- A paid Apple Developer account is required for IAP, CloudKit, App Groups, TestFlight. Individual vs organisation enrolment is the human's decision (organisation requires a D-U-N-S number and takes longer; apps can be transferred later).
- Consider the Small Business Program (reduced commission) — human to check eligibility.
