# Phase 4U (UX overhaul) — manual on-device checklist

Device: iPhone 16 Pro Max (iOS 26.x). Same format as `PHASE4_DEVICE.md`: **Steps → Expected**, plus an Observed column
and ✔ / ✘ / ? (unclear). Each Phase 4U stage adds its own self-contained `##` section (several agents edit this file;
keep sections independent). Text sizes: default, an intermediate size (xxxLarge) and the largest accessibility size
(AX-XXXL = Settings → Accessibility → Display & Text Size → Larger Text, slider at the end).

iOS version: ________ · Build: xtool / TestFlight · Tester: ________ · Date: ________

---

## U6

**Onboarding in 4 steps (UX_OVERHAUL_PLAN D8 / Opus R5 / Astra F01, F06–F13).** School type → How do you want to start?
→ Your week → Lesson times. Back is the standard navigation chevron; every step has one full-width primary button at
the bottom. Fields to show and reminders are no longer asked (profile defaults). "Just look around" creates sample data
with a "This is sample data · Remove" banner. Nothing here can be previewed locally: everything is device-only.

Setup: delete the app (or Developer screen → reset data) to get a first launch. For U6.14–U6.16 keep a build with your own
data. Screenshot routes (DEBUG, `-TabulaScreen`): `onboarding`, `onboarding.school-type`, `onboarding.start`,
`onboarding.week`, `onboarding.week-days`, `onboarding.times`, `onboarding.times-individual` (seed `empty`),
`onboarding.sample-banner` (seed `secondary`).

| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| U6.1 | First launch | Title "Choose your school type", the line "Your classes, tasks, and exams in one place.", four cards (Elementary school, Secondary / high school, University / college, Other), a compact row "App language: English" + "Change"; navigation title "Step 1 of 4"; no back button; **Continue** disabled until a card is chosen | | |
| U6.2 | Tap Secondary, then University | Only one card is selected (outline + filled check circle; unselected cards show an empty circle); VoiceOver reads "Selected" on the chosen card | | |
| U6.3 | Tap **Change** in the language row; in iOS Settings → Tabula → Language pick Slovak; return to Tabula | iOS relaunches the app; onboarding opens in Slovak with the school type from U6.2 still selected ("Vyberte typ školy"). Repeat without changing the language: returning keeps the step and selection | | |
| U6.4 | Continue → step 2 | "How do you want to start?" with **Set up my timetable** selected by default and **Just look around**; no photo / QR import rows; primary button "Continue"; standard back chevron (no "Back" text, no previous title) top left; swipe from the left edge goes back with the selection kept | | |
| U6.5 | Select Just look around | Primary button changes to **Open Example**. Select Set up my timetable again: back to "Continue" | | |
| U6.6 | Continue → step 3 "Your week" | Weekday chips start with the locale's first weekday (Monday in sk/de; Sunday with Settings → General → Language & Region → First Day of Week = Sunday); Mon–Fri selected (filled), Sat/Sun not. Turning every chip off shows "Choose at least one school day." and disables Continue. VoiceOver reads full weekday names and "Selected" | | |
| U6.7 | Repeat options (Secondary) | Same every week · Alternating weeks (A/B) · Alternating days (A/B) · Custom cycle. Elementary shows only the first three | | |
| U6.8 | Choose Alternating weeks | Card "Which week is this week?" with Week A / Week B segments and "Follow calendar odd/even weeks" off; footnote "From this week on, Week A and Week B take turns every week." Toggle on: footnote names the parity and this week's calendar week number (e.g. "Week A is in even calendar weeks. This is calendar week 44."). Switching A/B flips odd/even in the footnote | | |
| U6.9 | Finish with Alternating weeks, Week B, toggle off; open Timetable | This week is shown as Week B, next week as Week A. Repeat with the toggle on: the same, and the timetable settings show the calendar (odd/even) counting | | |
| U6.10 | Alternating days | "Which day is today?" on a school day, "Which day is Mon, Nov 2?" (next school day) at the weekend; Day A / Day B; footnote about school days and holidays. After finishing, today (or that day) shows the chosen day | | |
| U6.11 | Custom cycle | "Weeks in the cycle" stepper 3–6 and "Which week is this week?" menu Week 1…N; shortening the cycle never leaves an impossible week selected | | |
| U6.12 | Term dates toggle (every pattern) | Off by default (on for University); on shows Starts / Ends date pickers; end before start shows the error and disables Continue; turning the toggle off clears it | | |
| U6.13 | Continue → step 4 "Lesson times" (Secondary) | Fixed lesson periods (selected, "Use the same lesson times each day") / Individual start and end times; first lesson time picker; Lesson length, Short break, Break after lesson 2 each with a number field + "min" + stepper; Lessons per day stepper; live preview updates immediately. Type 90 into Lesson length → keyboard **Done** → preview shows 90-minute lessons; type 500 → clamped to 120 | | |
| U6.14 | Primary button reads **Start Using Tabula** (never "Get started"). Tap it | The app opens on Today with your (empty) timetable; no sample banner; Settings → Reminders shows Homework and Exams on (Elementary also "Pack your bag", University also Assignments); no notification permission prompt until a reminder has something to deliver | | |
| U6.15 | Fresh install, step 4, tap **I'll Do This Later** | Finishes with the profile's suggested times (Secondary 8 × 45 min from 8:00) even if the fields were edited | | |
| U6.16 | Fresh install, step 2 Just look around → Open Example | The app opens with the sample timetable; banner "This is sample data" with **Remove** and a close (X) button above the tabs; no notification prompt | | |
| U6.17 | Banner → Remove → confirmation | Title "Remove sample data?", message names what is removed and that your own items stay; Cancel keeps everything. Remove: sample timetable, its subjects / lessons, the sample task and exam disappear; with no other timetable the app returns to step 1 of onboarding; finishing it adds a new timetable | | |
| U6.18 | Look around again, then add your own task linked to a sample subject and a lesson inside the sample timetable; then Remove | The confirmation adds "This also removes 1 entry you added…" and "1 of your own tasks or exams stays but loses its link…"; after removing, your task is still in Tasks (no subject); reminder settings unchanged | | |
| U6.19 | (Existing users cannot reach onboarding on device: the last timetable cannot be deleted.) Check that Remove with another timetable present is covered by `SampleContentTests.removalNeverTouchesUserCreatedEntities` in the validate log | Test listed as passed; nothing to do on device | | |
| U6.20 | Banner → close (X) | Banner disappears and stays gone after relaunch; the sample data stays as normal data | | |
| U6.21 | Every step at **AX-XXXL** (English, then Slovak) | Cards show the icon above the text, icons stay small; titles and buttons wrap between words only (no "Elemen-tary", no "Get / start- / ed"); the bottom button grows in height; the last card / the "I'll Do This Later" link scrolls fully above the button; minute fields stack under their label; the whole flow is completable | | |
| U6.22 | Intermediate size (xxxLarge) and default, light and dark, Increase Contrast, Reduce Transparency | White cards on the grouped background (dark: dark grey cards), outline + check for the selection, readable footnotes; the bottom bar keeps its material / opaque background with Reduce Transparency | | |
| U6.23 | German and Japanese / Chinese UI | German long strings ("Individuelle Start- und Endzeiten", "Ungeraden/geraden Kalenderwochen folgen") wrap without truncation; CJK text renders and wraps correctly | | |
| U6.24 | VoiceOver through the whole flow | Order: navigation title "Step n of 4", large title, introduction, cards (title + detail, "Selected"), controls, primary button; the language row reads "App language: English" with the hint "Opens Settings…"; the minute fields read their value with "min"; the banner's X reads "Dismiss" with the hint "…keeps the sample data" | | |
| U6.25 | Every interactive element | Hit area ≥ 44 pt (cards, chips, language row, steppers, number fields, Remove, X) | | |
