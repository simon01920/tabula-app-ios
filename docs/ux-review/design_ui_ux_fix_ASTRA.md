# Tabula — UI/UX fixes

Review date: 23 October 2026  
Platform: native Swift / SwiftUI, iOS 26+  
Basis: all 40 supplied project files — the README and 39 screenshots  
Status: review and implementation specification; no app source code or running build was supplied.

## 1. What should change first

Tabula has a useful foundation: recognizable navigation, clear subject names, consistent subject identity, visible selection checkmarks, and separate current/next lesson information. The main problem is the amount and arrangement of information. Setup asks for too many decisions before showing value, large text exposes layouts that need to reflow, and some visual treatments make status, navigation, and actions difficult to distinguish.

Prioritize these changes:

1. **Rebuild the large-text layouts.** Keep Dynamic Type. Give text more width, shorten explanations, and move secondary details out of the primary reading path. Fix the three-line “Get start-ed” button first.
2. **Remove nonfunctional editor actions.** The owner reports placeholder and redundant buttons in subject/assignment submenus. Inventory and reproduce these before naming individual controls as broken; the editor screenshots are not among the attached files.
3. **Fix contrast and everyday readability.** Several sampled light-mode text combinations fall below a 4.5:1 normal-text target. Timetable times are visually too small for a central student task.
4. **Get students to a useful timetable sooner.** Use profile defaults, defer display preferences and reminder explanations, and remove unavailable import choices from the start flow.
5. **Make Today answer three questions quickly:** What class am I in? Where do I go next? What needs doing?

These changes should preserve native controls, the five existing tabs, translations, VoiceOver, and user-selected subject colours. A new visual identity or custom navigation system is unnecessary.

## 2. Scope, evidence, and priorities

The owner confirmed that elementary, secondary, and university students should receive equal consideration. The owner also reported that some subject/assignment submenu buttons are placeholders or redundant, and authorized studying the published design Markdown when repository access failed.

The README indexes **185 screenshots in 65 screen/seed/language combinations**. The actual attachment set contains **39 screenshots in 13 combinations**, covering seven onboarding steps, Today, and the timetable day view. All supplied screenshots were visually inspected in side-by-side groups; important text and control failures were also inspected in larger crops. The README was read in full.

No source code, accessibility tree, video, interactive app, subject editor, assignment editor, other timetable views, standalone Tasks/Exams/Settings screens, or widget gallery images were present. Their README descriptions inform proposed behavior and test coverage, not claims about their visible implementation. The remaining 146 indexed screenshots were not inspected.

Evidence labels used below:

| Label | Meaning |
|---|---|
| **Visible** | Directly observable in an attached image. |
| **Measured** | Sampled from original PNG pixels; subject to the measurement limits below. |
| **Reported** | Described by the owner; not independently reproduced. |
| **Verify** | A plausible interaction or implementation concern requiring the app or code. |
| **Proposal** | A design recommendation, not a claim that existing behavior is broken. |

Priorities: **P1** = address before the next usability acceptance pass; **P2** = improve in the next design iteration; **P3** = polish. No P0 failure is established by these materials. Priority reflects user impact, not proof of a code defect.

Screenshots are 1320 × 2868 pixels. Their dimensions do not establish actual touch target bounds, font declarations, or hit testing. Measurements below are colour measurements, not inferred point-size compliance. A control being below the captured viewport does not prove that it cannot be reached by scrolling.

The README explicitly identifies Slovak subject names in English screenshots as sample data. They are **not** translation defects. Its fixed app time is 13 October 2026, 10:20 in Europe/Bratislava; the status bar's 9:41 is treated as screenshot presentation, not a production clock bug.

## 3. Prioritized findings

### F01 — P1 · Onboarding needs a different composition at accessibility sizes

**Evidence:** Visible. `05-onboarding.profile_empty-ax-xxxl-text.png`, `08-onboarding.profile_empty_sk-ax-xxxl-text.png`, `14-onboarding.rotation_empty-ax-xxxl-text.png`, `17-onboarding.start_empty-ax-xxxl-text.png`, `20-onboarding.time_empty-ax-xxxl-text.png`; also the other onboarding AX captures.

**Problem:** The explanatory paragraphs can consume most of the viewport before a choice appears. Horizontal option layouts reserve excessive width for icons and selection marks: “Elementary” and “schedule” break inside words. On the final step, the primary button reads “Get / start- / ed” and becomes much taller than Back. This obscures the task and reduces usable space.

**Change:** Shorten each introduction to one useful sentence. At accessibility sizes, place option text across the available width, with an optional small icon above or beside the title only when it fits. Put selected-state information where it does not squeeze the label. Use a full-width primary action, with Back in the navigation bar or on a separate row. Allow natural height and scrolling. Do not cap Dynamic Type or shrink text to force the old horizontal layout.

**Accept when:** All seven steps can be completed at AX-XXXL in English and Slovak. Button words do not split internally. Every option and its selected state can be read and reached. The last option scrolls fully above the action area.

### F02 — P1 · Today gives the current lesson too much space at large text

**Evidence:** Visible. `26`, `29`, `32`, and `35` Today AX screenshots, mapped in the inventory below.

**Problem:** The current lesson card consumes approximately the first viewport. Long names, teacher details, large metadata icons, and the countdown push the next lesson below view. This is particularly costly when a student opens the app while moving between rooms.

**Change:** Use this reading order: current subject → room/building → end time or minutes remaining → next lesson and location. Move teacher titles and less urgent metadata into lesson detail. At AX sizes, move decorative subject icons out of the text column and use full-width stacked text. Replace the prominent seconds display with concise minutes for the overview; retain exact timing in detail if useful.

**Accept when:** At ordinary text sizes, current and next lesson locations are visible together. At AX-XXXL, full names remain readable, the next-lesson summary follows immediately after essential current-lesson information, and teacher metadata no longer intervenes. Scrolling remains acceptable; squeezing everything into one screen is not a requirement.

### F03 — P1 · The accessible timetable fallback still constrains the lesson title

**Evidence:** Visible. `38-timetable.day_secondary-ax-xxxl-text.png`.

**Problem:** The view appears to switch from a proportional timeline to large tiles, which is a sensible adaptation. However, the date header becomes very tall, and the first tile divides “Matematika” across three lines while an icon and two badges occupy the same horizontal band. Most of one screen is used by the header and one lesson.

**Change:** Keep the accessible list/agenda approach. Give the subject name a full-width row; put time and room beneath it. Move supplementary counts/statuses to a following line. Offer a compact date heading with Previous day / Next day actions and a date picker at accessibility sizes instead of expanding all five weekday columns. Preserve access to the week cycle.

**Accept when:** The sample “Matematika” title no longer suffers the shown internal word breaks. Date selection, cycle information, and all lesson details remain available. Long translated names wrap naturally without competing with badges.

### F04 — P1 · Several active text treatments need stronger contrast

**Evidence:** Measured. Original PNG samples, with examples in the table below. Dark-mode counterparts were checked where listed.

**Problem:** Secondary information is frequently grey on grey. Small white labels on the bright blue primary action also have limited contrast. The overdue label is red on pale red. These are useful text, not decoration.

| Sample | Foreground / background | Approximate ratio | Assessment against a 4.5:1 normal-text target |
|---|---|---:|---|
| Profile option description, light (`07`) | `#7C7C81` / `#DDDDDE` | 3.06:1 | Below target |
| Same description, dark (`06`) | `#9C9CA2` / `#252526` | 5.61:1 | Meets target in this sample |
| Today lesson time, light (`31`) | `#848489` / `#F1F1F1` | 3.30:1 | Below target |
| Same lesson time, dark (`30`) | `#94949A` / `#111112` | 6.26:1 | Meets target in this sample |
| Onboarding Next label, light (`04`) | `#FFFFFF` / `#0088FF` | 3.52:1 | Below target for the small label |
| Overdue label, light (`31`) | `#FF383C` / `#FFDBDC` | 2.79:1 | Below even a 3:1 large-text target |
| Ethics lesson white text on grey tile (`40`) | `#FFFFFF` / `#757575` | 4.61:1 | Meets target in this sample |

**Change:** Strengthen important metadata and action-label colours. Use semantic foreground/background roles, then validate the rendered pair; semantic naming alone does not ensure contrast on a custom surface. Use a darker accessible red for overdue text and a stronger action foreground/background pairing. Keep the existing ability to choose light or dark text for subject tiles and test all allowed custom colours.

**Accept when:** Rendered normal text reaches at least 4.5:1, qualifying large text at least 3:1, and custom meaningful graphical indicators at least 3:1 against adjacent colours. Check both appearances and Increase Contrast. Disabled coming-soon rows are not being counted as active-text failures. These are design targets informed by [S3–S5], not a claim of a complete WCAG certification.

**Measurement limits:** The PNGs contain no embedded ICC profile. Values were treated as sRGB; dominant flat foreground/background pixels were sampled away from antialiased edges. Confirm with actual resolved colours in the app, especially for translucent materials. Do not round a below-threshold result up to a pass.

### F05 — P1 · Remove placeholder and redundant controls from editors

**Evidence:** Reported by the owner: some submenus used while adding a subject or assignment contain placeholders or redundant buttons. The README identifies relevant subject, lesson, and task editors, but their screenshots and code are unavailable.

**Problem:** A visible action that does nothing teaches students that the interface cannot be trusted. Several controls performing the same save/dismiss action can also make it unclear which one is required.

**Change:** Audit every visible control in the listed editors. Record its label, destination or state change, prerequisite, and feedback. Remove actions for unimplemented features from normal creation flows. Consolidate controls only when they have the same purpose and scope. Keep Cancel and Save distinct; keep separate parent/child saves only when each commits a clearly named object. An existing subject chosen for an assignment and “Create subject” are different operations and both may be useful.

**Accept when:** Every enabled control has a reproducible result. Creating one subject or task produces one saved object, without an extra confirmation step. Cancel leaves no unintended object. A temporary disabled action explains what enables it. The editor action matrix in section 5 is completed against the real app.

### F06 — P1 · A display preference should not make editing capabilities disappear

**Evidence:** Visible copy in `03` and `04`: hidden details disappear everywhere, including the editor. Actual hiding behavior is Verify.

**Problem:** “What do you want to see?” sounds like a display preference, but its explanation promises to remove fields from editing. A student who hides teacher/building/notes may later be unable to discover how to enter or correct that information. This is especially confusing across different school profiles.

**Change:** Separate **information shown on summaries** from **information stored and editable**. Keep optional fields under a clearly labelled “More details” section in the editor. Show only populated, relevant fields in summaries. Changing visibility must not delete stored values. Move summary-display preferences out of mandatory onboarding.

**Accept when:** Hide Room in summaries, edit a lesson, update its room, then show Room again: the new value appears. Every optional field remains discoverable from the editor. Copy accurately explains the scope of the preference.

### F07 — P2 · Rotation setup mixes independent concepts

**Evidence:** Visible. `15-onboarding.rotation_empty-dark.png`, `16-onboarding.rotation_empty-light.png`; README rotation and term descriptions.

**Problem:** The same choice list includes “Odd / even weeks,” “Cycle of several weeks,” and “Different per semester.” Semester boundaries and a repeating week pattern can coexist. The UI also shows Week B elsewhere, without showing how A/B maps to odd/even weeks. A/B weeks should not be inferred to mean calendar parity for every school.

**Change:** Ask **“How does your timetable repeat?”** with separate options for Every week, Alternating weeks, Alternating school days, and Custom cycle. Configure the cycle anchor explicitly: for example, which week starts on a selected Monday. Offer calendar odd/even as an explicit rule where appropriate. Put term start/end dates in a separate optional section, available for every pattern. Explain whether holidays advance a day-based cycle.

**Accept when:** A university user can combine semester dates with alternating weeks. A secondary-school user can anchor Week A without assuming ISO parity. The next two weeks preview correctly, including the agreed holiday behavior.

### F08 — P2 · Seven onboarding steps delay the first useful action

**Evidence:** Visible across `02–25`; seven-step structure confirmed by the README. No visible skip action appears in the captures.

**Problem:** Students must consider profile, rotation, time structure, field visibility, reminders, and starting data before seeing their timetable. Some are preferences they cannot evaluate meaningfully before using the app.

**Change:** Offer a short default path: choose a school profile → check essential schedule defaults → create the first lesson. Make additional setup optional. Move field visibility into Settings and explain reminders when the student first enables a real reminder. Preserve the full configuration path for students who need it. Apple recommends brief, contextual onboarding [S1].

**Accept when:** Each profile can reach a usable empty timetable and add its first lesson without configuring display fields or reading notification delivery documentation. Back preserves entered values. Advanced schedule setup remains reachable.

### F09 — P2 · Unavailable imports occupy valuable onboarding space

**Evidence:** Visible and README-confirmed. `18-onboarding.start_empty-dark.png`, `19-onboarding.start_empty-light.png` show disabled photo and QR/share-code imports marked coming soon.

**Problem:** Half the listed start methods cannot help the user. These are visibly unavailable features, not independently discovered broken taps, but they add decision noise and advertise a benefit the current flow cannot provide.

**Change:** Remove both entries from this screen until they work. If product communication requires mentioning them, use a brief noninteractive roadmap note outside the main creation path. When released, restore real actions with clear permission, progress, failure, and retry states.

**Accept when:** Every displayed start action is usable. No release creation flow contains an enabled no-op or a selectable coming-soon option.

### F10 — P2 · Make a real timetable the obvious start, and keep examples reversible

**Evidence:** Visible. `18` and `19` show “Use sample data” selected. Whether production preselects it or the capture fixture selected it is Verify.

**Problem:** Students may finish onboarding with someone else's timetable without understanding the consequence. “Get started” does not identify whether it creates a personal timetable or loads an example.

**Change:** Present “Create my timetable” as the main path and “Explore an example” as a secondary action. If examples are retained, label the example clearly and provide a way to remove example data without deleting the student's own entries. Do not assume the sample preselection is a production bug until checked.

**Accept when:** A clean production launch never inserts example content without an intentional choice. The example's removal scope is clear and preserves user-created content.

### F11 — P2 · Lesson-time language and controls need more concrete meaning

**Evidence:** Visible. `21-onboarding.time_empty-dark.png`, `22-onboarding.time_empty-light.png`.

**Problem:** “Free times” can mean free periods, whereas it means independently entered start/end times. “Bell schedule” lacks an equivalent explanatory line. Steppers show values in subordinate text and may require many taps for substantial adjustments; their increment behavior cannot be tested here.

**Change:** Use “Fixed lesson periods” with “Use the same lesson times each day,” and “Individual start and end times.” Keep the generated preview. Give editable numbers and units clear emphasis, and allow a direct value entry/picker for large changes alongside native steppers where appropriate. Make the long-break position configurable when the model supports it.

**Accept when:** A student can predict both timing modes without a guide. Each value has a visible unit where needed. The preview updates immediately and never creates overlapping periods through invalid input.

### F12 — P2 · Reminder explanations overwhelm the actual preference

**Evidence:** Visible. `11–13` show reminder switches followed by substantial Standard / Time Sensitive explanation cards.

**Problem:** Students choosing what to be reminded about are also asked to absorb delivery mechanics. At AX-XXXL, the opening explanation alone fills most of the screen. Explanatory cards resemble other selectable cards despite having no visible selection state.

**Change:** Keep the contextual permission request described in the copy. Defer delivery-tier explanations to reminder settings or an optional “How reminders work” disclosure. If cards are informational, style and expose them as information. If they select a delivery mode, give them a clear selected state and actual setting effect. Once permission is denied, distinguish saved reminder preferences from the inability to deliver notifications.

**Accept when:** Students can choose reminder categories without reading operating-system documentation. The app requests permission only after a relevant action, and denial does not block timetable use. No copy guarantees delivery through Focus or silent settings without the corresponding supported behavior.

### F13 — P3 · Welcome emphasizes language settings more than the product benefit

**Evidence:** Visible. `23–25` show Welcome, setup copy, a large calendar icon, and a prominent language-settings block.

**Problem:** The first screen does not name Tabula in its main heading or show the practical benefit. For someone already using the correct language, the largest interactive content block is a detour into Settings.

**Change:** Use a short product introduction, for example “Your classes, tasks, and exams in one place.” Make “Language: English” a compact secondary row and label an external jump clearly. Keep a language-change route available for users who need it, and preserve onboarding state across that trip.

**Accept when:** A first-time user can identify the app's purpose and primary action at a glance. Returning from language settings preserves progress and refreshes translated copy.

### F14 — P2 · Today repeats detail instead of emphasizing the remaining day

**Evidence:** Visible. `36` and `37` show the current university lesson in both the large Now card and the first full day tile, including teacher/building details. `27` and `28` show an already-ended 08:00 lesson near the top of the daily list at the fixed 10:20 app time.

**Problem:** Repeating the same information and starting the list with earlier lessons spends space on context that is less useful than the next room or unfinished work.

**Change:** Keep the current/next summary, then show due work and remaining lessons. Group earlier lessons under a modest “Earlier today” disclosure, while retaining the complete schedule in Timetable. Repetition is acceptable when it adds context; avoid repeating the entire current-lesson detail card in adjacent sections. Allow profile defaults to emphasize bring-list items, homework, or buildings as appropriate.

**Accept when:** Today opens with current and upcoming information in all three profiles. Earlier lessons remain accessible. A university student's next building remains prominent; elementary students can still reach preparation information.

### F15 — P2 · Task status needs clearer labels and distinct actions

**Evidence:** Visible plus Verify. `30`, `31`, `33`, `34` show a completion circle, a “2/5” subtask marker, a repeat icon, and an overdue badge alongside Due today.

**Problem:** Compact markers require interpretation, and the overdue item is not visible in the shown due-today list. The image does not establish whether the badge opens the overdue filter or whether task-row taps conflict with completion taps.

**Change:** Make the overdue count a deliberate route to overdue tasks, with an understandable label such as “1 overdue task.” In task detail, expose subtask progress as “2 of 5 subtasks complete” and show the actual repeat rule. Provide equivalent accessible names on compact rows. The completion control changes completion; the title/row opens detail. Do not nest competing buttons.

**Accept when:** Completing a task does not accidentally open it; opening it does not complete it. Overdue navigation shows the expected item. Recurring-task completion has an explicit, verified effect on the next occurrence. Provide undo for accidental completion.

### F16 — P2 · The exam countdown outranks the exam itself

**Evidence:** Visible. `27`, `28`, `30`, `31`, `33`, `34` display “in 7 days” or “in 9 days” more prominently than the exam title.

**Problem:** A student scans a large countdown before learning which assessment it describes. On an everyday dashboard, subject, assessment, and actual date are more useful together than a standalone relative number.

**Change:** Lead with the assessment/subject, then show a concise date and relative time. Increase emphasis when an exam is genuinely imminent. Use the exam's own type rather than relabelling every school assessment as an examination. Keep terminology natural for each locale and profile.

**Accept when:** A quick scan answers what the exam is and when it happens. Today, tomorrow, later, and past states format correctly without ambiguous zero/negative countdowns. Large text does not turn the countdown into the largest information block.

### F17 — P2 · Define a consistent distinction between information and actions

**Evidence:** Visible styling; interaction is Verify. Rounded cards, outlined Now/Week B pills, selectable onboarding options, and reminder explanation cards share similar visual emphasis. Today lesson/exam cards have no explicit text describing a tap destination in the screenshots.

**Problem:** Shape alone does not tell a student what can be tapped. Some elements may look actionable while only communicating status. Conversely, useful detail navigation may not be obvious.

**Change:** Use one consistent disclosure treatment for rows that navigate; use actual buttons for actions, selection marks for choices, and quieter text for status. Keep Now as status unless it has a meaningful action. Do not add chevrons to every block or manufacture actions for decoration. Audit the accessible role and label of each interactive element.

**Accept when:** A new student can identify the actions in a short usability check. VoiceOver announces buttons, links, selections, and static text accurately. Every disclosed destination opens; static badges do not masquerade as buttons.

### F18 — P1 · Day-view text is too small relative to its available width

**Evidence:** Visible. `39-timetable.day_secondary-dark.png`, `40-timetable.day_secondary-light.png`.

**Problem:** Seven lessons fit into the proportional timeline, but time ranges are especially small and text is concentrated on the left of otherwise wide blocks. This sacrifices quick reading of the most important schedule information. Exact font point sizes are not established by the image.

**Change:** Increase subject/time/room readability and reduce the number of metadata lines inside proportional blocks. Put teacher names into detail when space is tight. Prefer a subject line and a time/location line. Maintain accurate time positioning in the timeline; if minimum readable height conflicts with duration, offer an agenda/list view rather than visually falsifying duration. Short or overlapping lessons need an explicit compact treatment and a route to complete detail.

**Accept when:** Students can read subject, start time, and room at ordinary device viewing distance. Long names and short lessons remain usable. AX text receives a content-sized agenda layout rather than tiny proportional text.

### F19 — P2 · The current-time marker disappears against a red subject

**Evidence:** Visible. `40` shows the current-time red dot/line at the red Slovak lesson. Much of the line blends into or is hidden by the lesson block; only small exposed portions are apparent.

**Problem:** The student must infer the current moment from a marker competing with a similar subject colour. The app intentionally allows arbitrary subject colours, so a single fixed line colour is fragile.

**Change:** Put a readable current-time label in the gutter, and use a contrasting outline/backplate or another appearance-aware treatment for the marker. Keep it above the content without crossing and obscuring lesson text. Preserve subject identity separately.

**Accept when:** The current-time marker is understandable on red, blue, grey, light, and dark subject colours, and without colour perception. It is shown only where temporally appropriate and updates when the app resumes.

### F20 — P2 · Timetable navigation contains unexplained controls and markers

**Evidence:** Visible plus Verify. `38–40`: an icon-only top-right control, week arrows, Week B, a red date circle, a blue selection background, and an orange dot under Thursday. The captures do not reveal the menu or the dot's meaning.

**Problem:** The top-right icon could mean agenda view, a list of timetables, or settings. The orange dot provides no visible explanation. Today and selected-day styling cannot be distinguished confidently from a capture where they coincide.

**Change:** Give the toolbar control a role-specific label after confirming its function: “View: Day,” “Timetables,” or the actual destination. Expose it to VoiceOver by purpose. If the dot means an exam/task/change, surface that meaning in the selected day's content and accessibility label. Distinguish today from selected date consistently. Show “Today” as a return action when viewing another date, if no equivalent visible action already exists.

**Accept when:** A student can navigate to another week, select a day, identify its events, and return to today without guessing. Current-day and selected-day indicators remain distinct. Weekend access follows the actual timetable configuration, not a hard-coded five-day assumption.

### F21 — P2 · Full-strength subject fills compete with the content and glass navigation

**Evidence:** Visible. Bright elementary/university Today tiles in `27`, `28`, `36`, `37`; coloured day blocks in `39`, `40`. Purple/orange content visibly colours the floating tab bar in several captures.

**Problem:** Large saturated surfaces make every lesson equally loud. The transition from neutral summaries to strong colour blocks is abrupt, and colour behind the native tab bar can compete with the selected-tab tint.

**Change:** Keep subject colour as a recognition aid. For the default style, try a coloured leading marker/icon or restrained tint on a semantic surface. Preserve a stronger-colour option if it helps students recognize subjects. Use consistent surface roles and native Liquid Glass for navigation; avoid adding glass to content cards. Validate tab readability over the actual scrolled backgrounds before changing native styling [S6].

**Accept when:** Subject identity remains clear without relying on colour alone. Current location, overdue work, and the primary action have a stronger hierarchy than ordinary lessons. The selected tab stays recognizable over every allowed subject colour and with Reduce Transparency.

### F22 — P2 · Make time-format behavior consistent and verify the creation entry point

**Evidence:** Visible cross-screen difference and Verify. `22` uses “8:00 AM” while `31` and `40` use 24-hour times. This may reflect distinct seeded settings, not a bug. No labelled Add action is visible in the supplied Today or day-view captures, although the README describes quick-add functionality.

**Problem:** Inconsistent time formatting can undermine confidence if it occurs within the same user's settings. A creation function hidden behind an unexplained icon, long press, or menu makes first use harder.

**Change:** First test the screens under the same locale and time-format preference. Apply that preference consistently across onboarding, Today, Timetable, and editors. Verify the existing quick-add route; expose a labelled “Add lesson” on an empty timetable and an understandable toolbar action in a populated timetable if necessary. Use contextual “Add task” in Tasks and “Add exam” in Exams. Avoid placing multiple equivalent Add controls on one screen.

**Accept when:** A novice can add the first lesson without instruction or a hidden gesture. Changing the time-format setting has a consistent result. This finding must not be closed by adding duplicate controls without inspecting the existing menu.

## 4. Proposed screen behavior and sizing

These are starting specifications for native implementation, not pixel measurements of the screenshots or mandatory Apple dimensions beyond the cited interaction guidance.

| Element | Recommended treatment | What to make larger or smaller |
|---|---|---|
| Onboarding primary action | One prominent native action; approximately 50–56 pt minimum visual height at default text, natural growth thereafter | Smaller default container than the current oversized footer; stronger label hierarchy |
| Back | Standard leading navigation action, or a separate secondary row when required | Less visual weight than Next; preserve its usable hit area |
| Interactive targets | Prefer at least 44 × 44 pt hit regions for this app; increase where children/dexterity needs benefit [S2] | Enlarge hit areas without enlarging every symbol |
| Essential form labels | Semantic body text; native form grouping | Larger/stronger than faint secondary descriptions |
| Today subject | Semantic headline/title appropriate to available width | Keep important; give more width at AX rather than forcing fixed line counts |
| Room and next location | Essential, high-contrast text near the subject | More emphasis than teacher titles and decorative icons |
| Lesson countdown | Compact “25 min left” in the overview; exact timer optional in detail | Smaller visual footprint; stop competing with the next lesson |
| Timetable time ranges | Readable semantic text; approximately 15–17 pt is a useful prototype starting range where space allows | Larger than the current visually tiny time line |
| Teacher, notes, type | Show when useful; put secondary details in lesson detail or expandable metadata | Less space in glanceable summaries |
| Subject icon | Small recognition aid; no fixed large text-column reservation | Smaller at AX relative to the width it consumes |
| Counts and badges | Short meaningful labels, or accessible equivalents for compact symbols | Reduce decorative pill treatment; keep important status readable |
| Content surfaces | Semantic grouped backgrounds and consistent padding | Reduce broad saturated fills and heavy grey blocks |
| Spacing | Start from an 8 pt rhythm, roughly 16–20 pt horizontal page margins and 12–16 pt content padding; adapt to native containers | Consistent instead of adding empty space everywhere |

Keep the five tabs. Their labels are understandable, and the available evidence does not justify merging Tasks and Exams or moving Settings. Native tab labels need their system accessibility behavior checked; their compact appearance alone is not a reason to build a custom oversized tab bar.

### A shorter first-run flow

| Stage | Main content | Optional content | Outcome |
|---|---|---|---|
| Profile | School type, short explanation of presets | Language selection | Appropriate defaults |
| Schedule basics | Repeating pattern and timing mode, with a small preview | Cycle anchor, term dates, detailed bell times as relevant | A valid timetable structure |
| First useful action | “Add your first lesson” | “Explore an example” / finish setup later | The student sees their own timetable |
| In context | Ask about a reminder when one is enabled | Delivery explanation in reminder settings | An understood permission choice |

These stages may be merged or expanded where a real schedule requires it. The target is fewer unnecessary decisions, not an arbitrary three-screen limit. Profile selection must not permanently remove capabilities.

### Today content order

1. Current lesson, end/remaining time, and location; or the appropriate break/before-school/finished state.
2. Next lesson, start time, and destination.
3. Due/overdue work, with a clear route to the full list.
4. Remaining lessons and the next relevant assessment, ordered by urgency.
5. Earlier lessons, available but visually subordinate.

Default emphasis can vary: bring-list/preparation for elementary, homework and cycle context for secondary, room/building and irregular starts for university. Students must be able to change presentation preferences.

### Suggested copy changes

| Current | Proposed English | Proposed Slovak |
|---|---|---|
| Who are you? / Kto ste? | Choose your school type | Vyberte typ školy |
| Free times | Individual start and end times | Vlastné časy hodín |
| Bell schedule | Fixed lesson periods | Pevné časy hodín |
| What do you want to see? | Details shown on lesson cards | Údaje na kartách hodín |
| Start blank | Create my timetable | Vytvoriť môj rozvrh |
| Use sample data | Explore an example | Prezrieť ukážku |
| Get started | Use the actual outcome: Create timetable / Open example | Vytvoriť rozvrh / Otvoriť ukážku |
| Time left · 25:00 | 25 min left | Zostáva 25 min |
| 1 overdue | 1 overdue task | 1 úloha po termíne |

Treat this as copy direction, with in-context language review. Use localized full phrases and plural variants, not concatenated fragments. Avoid imposing English title capitalization on Slovak. Keep user-entered subject names intact.

## 5. Editor cleanup specification for the reported submenu issue

This section is deliberately concrete without inventing observed buttons. The entries describe what to check and the intended behavior. Existing controls cannot be individually confirmed as redundant until their actual label and action are inspected.

| Area from README | Keep as the core interaction | Show progressively | Remove or consolidate if found | Verification |
| `editor.subject` | Subject name; one deliberate save; colour/icon selection with defaults | Default teacher and room | Empty feature buttons, duplicate saves at the same scope, preview decorations exposed as controls | Save once; reopen; values persist |
| `editor.subjects` | Select a subject; Add subject; explicit Reorder mode | Bulk actions only if implemented | Reorder affordances outside a working reorder flow; duplicate Add entry points without a clear reason | Reordering works and persists; cancelling preserves order |
| `editor.lesson-new` / `editor.lesson` | Subject, day/date context, time/period, applicable week cycle | Room override, teacher override, notes, lesson type | Unavailable actions; duplicated property editors; Delete on an unsaved new item | No accidental duplicate; subject defaults and lesson overrides remain distinct |
| `tasks.editor-new` / `tasks.editor` | Task title, subject if applicable, due date or next lesson, one save | Reminder, repeat, subtasks, priority, notes, attachments | Placeholder attachments; empty repeat/reminder actions; same-scope Save and Done duplicates | Save task; reopen; verify due rule and every enabled extra |
| Nested subject creation from a task | Name the child operation clearly: Create subject | Optional subject details | Ambiguous back/close/save combinations that imply the whole task was saved | Create/select subject; return to preserved task draft; Cancel child leaves parent draft intact |
| Attachment action, if implemented | Choose/import item with supported formats | Attachment management after an item exists | Tap targets for an unimplemented picker | Cancel safely; success visible; failure recoverable |
| Reminder submenu | Choose a supported reminder time/rule | Permission and delivery details when relevant | Buttons that only appear to enable delivery without a state change | Denied permission and accepted permission have clear distinct states |

Classify each control into one of four categories:

- **Working action:** retain, with a meaningful label and feedback.
- **Temporarily unavailable:** disable with a nearby reason and a clear way to meet the prerequisite.
- **Unimplemented:** remove from release creation/editing flows.
- **Informational:** render as text/status; do not expose it as an enabled button.

An audit record needs: screen → control label → intended result → observed result → decision → passing test. Complete this for every nested menu, not just the first editor page. Do not count an enabled tap as successful merely because the screen animates; verify the resulting data or destination.

## 6. SwiftUI implementation guidance

These are proposed implementation directions, not statements about the unavailable source.

| Concern | Native implementation direction |
|---|---|
| Reflow at large text | Read the Dynamic Type environment; use an accessibility-specific arrangement where needed. `ViewThatFits` or explicit layout alternatives can help, but should not hide essential content. |
| Text sizing | Use semantic font styles. Avoid global font-size caps, arbitrary scaling-down, and fixed-height containers around multiline text. |
| Selection rows | Keep text and selected-state semantics together. Use native selection controls or accessible custom rows with one coherent activation target. |
| Action footer | Use safe-area-aware layout such as `safeAreaInset`; ensure scrollable content can move fully above the footer and keyboard. The captures do not prove whether this is already correct. |
| Editor structure | Prefer native `Form`/`Section`, `TextField`, `Picker`, `DatePicker`, `Toggle`, and `Stepper` where they match the operation. |
| Interaction semantics | Use `Button`, `NavigationLink`, and `Menu` for their actual purposes. Avoid gesture-only substitutes and nested buttons. |
| Appearance | Resolve semantic surfaces and foregrounds for light/dark and accessibility settings. Test custom subject foreground contrast after colour selection. |
| Time and locale | Format dates, times, counts, and plurals from locale and app preference. Use localized resources; preserve input and selection when language changes. |
| VoiceOver | Name icon-only actions by purpose. Include subject, time, location, and state in a sensible reading order. Hide decorative symbols from separate traversal. |
| Countdown updates | Avoid announcing a changing seconds counter continuously. Expose meaningful remaining time and transitions without stealing focus. |
| Native glass | Preserve system navigation materials. Test Increase Contrast, Reduce Transparency, Reduce Motion, and coloured content beneath navigation. |

For a native app, use Xcode Accessibility Inspector and XCTest/XCUITest plus hands-on assistive-technology testing. Browser emulation through Playwright cannot validate native SwiftUI hit testing, VoiceOver order, permission dialogs, or editor persistence.

## 7. Implementation order

| Pass | Work | Completion evidence |
|---|---|---|
| 1 — Trust and access | F01–F06, F18: adaptive layouts, measured contrast, reported dead controls, recoverable fields | Updated snapshots, control audit, persistence and assistive-technology checks |
| 2 — Setup clarity | F07–F13: repeat/term model, shorter onboarding, unavailable imports, explicit start action, timing and reminder copy | First-run task walkthroughs for all three profiles |
| 3 — Daily use | F14–F17, F19–F22: information priority, task actions, exam emphasis, markers, navigation, colour, format/add discoverability | Current/next/task flows tested under representative data |

Do not mix a broad restyle with schedule-data changes in one unreviewable change. Implement shared row/card/footer fixes first, then screen-specific composition. For rotation and visibility changes, verify existing user data survives and retains its intended meaning.

## 8. Acceptance and regression checklist

The following checks are proposed work, not tests already executed.

### Layout and accessibility

- [ ] Capture every changed screen at default, an intermediate large size, and AX-XXXL, in light and dark modes.
- [ ] Cover the smallest supported iPhone layout and the supplied Pro Max-sized layout; include supported orientations.
- [ ] Test long subject names, multi-part teacher names, long rooms/buildings, and empty optional fields.
- [ ] Reach the bottom of every form with the footer and keyboard visible. Focused inputs and Save remain reachable.
- [ ] Measure real interactive hit regions; use 44 × 44 pt as Tabula's default minimum target.
- [ ] Check rendered text/indicator contrast, including custom subject colours and glass over moving content.
- [ ] Test VoiceOver reading order, selected states, toggles, task completion, date navigation, and modal return focus.
- [ ] Verify Reduce Motion, Reduce Transparency, Increase Contrast, and Bold Text without losing meaning or controls.

### Onboarding and schedules

- [ ] Complete the short path separately as elementary, secondary, and university, without example data.
- [ ] Change profile/defaults and go Back without losing user-entered values unexpectedly.
- [ ] Select an example intentionally; remove only example content later.
- [ ] Test every-week, alternating-week, odd/even, day-cycle, and custom-cycle behavior actually supported.
- [ ] Test term boundaries, holidays, cycle anchors, weekend classes, and daylight-saving/time-zone changes.
- [ ] Test before school, during a lesson, during a break, after school, no lessons, a holiday, cancellation, and an overlapping lesson.
- [ ] Verify the same 12/24-hour preference in onboarding, Today, Timetable, and all editors.

### Editor actions and persistence

- [ ] Audit every subject/task editor button and nested-menu action; no enabled no-ops remain.
- [ ] Save, cancel, back out, reopen, and relaunch after creating/editing an item.
- [ ] Reject invalid fields inline without discarding the draft; show an actionable recovery.
- [ ] Preserve the parent task draft after cancelling nested subject creation.
- [ ] Hide and restore each summary field without data loss or losing editor access.
- [ ] Verify task-row navigation, completion, undo, subtasks, and recurring-task behavior separately.
- [ ] Give unavailable-in-context controls an understandable reason; hide unimplemented features.

### Localization and permissions

- [ ] Check English and Slovak visually against the supplied cases, then exercise every supported locale listed in the README.
- [ ] Cover long translations, diacritics, Cyrillic, Japanese, and Simplified Chinese; avoid hard-coded English widths.
- [ ] Check singular/plural task counts and relative dates around midnight.
- [ ] Request notification permission from a relevant action; handle granted, denied, and later-changed states.
- [ ] Do not treat “reminder preference enabled” as proof a notification will be delivered.

### Small usability check

Test with representatives of each school group using tasks rather than instructions: create a first lesson; identify the next room; add homework due at the next lesson; complete and undo a task; find an overdue item; change one lesson's room; return to today after browsing another week. Record hesitation, mistaken taps, requests for explanation, and recovery. These observations should decide whether controls are intuitive; a cleaner screenshot alone cannot establish that.

## 9. Complete supplied-file coverage

Every filename below was inspected. AX means the supplied largest-accessibility-text capture. This table is the evidence index for the numeric references above; files reside in the supplied `project_sources` directory.

| Screen / seed / language | AX file | Dark file | Light file | Principal findings |
|---|---|---|---|---|
| Fields / empty / en | `02-onboarding.fields_empty-ax-xxxl-text.png` | `03-onboarding.fields_empty-dark.png` | `04-onboarding.fields_empty-light.png` | F01, F04, F06, F08 |
| Profile / empty / en | `05-onboarding.profile_empty-ax-xxxl-text.png` | `06-onboarding.profile_empty-dark.png` | `07-onboarding.profile_empty-light.png` | F01, F04, F08 |
| Profile / empty / sk | `08-onboarding.profile_empty_sk-ax-xxxl-text.png` | `09-onboarding.profile_empty_sk-dark.png` | `10-onboarding.profile_empty_sk-light.png` | F01, F08; localized wrapping |
| Reminders / empty / en | `11-onboarding.reminders_empty-ax-xxxl-text.png` | `12-onboarding.reminders_empty-dark.png` | `13-onboarding.reminders_empty-light.png` | F01, F08, F12, F17 |
| Rotation / empty / en | `14-onboarding.rotation_empty-ax-xxxl-text.png` | `15-onboarding.rotation_empty-dark.png` | `16-onboarding.rotation_empty-light.png` | F01, F07, F08 |
| Start / empty / en | `17-onboarding.start_empty-ax-xxxl-text.png` | `18-onboarding.start_empty-dark.png` | `19-onboarding.start_empty-light.png` | F01, F09, F10 |
| Time / empty / en | `20-onboarding.time_empty-ax-xxxl-text.png` | `21-onboarding.time_empty-dark.png` | `22-onboarding.time_empty-light.png` | F01, F11, F22 |
| Welcome / empty / en | `23-onboarding_empty-ax-xxxl-text.png` | `24-onboarding_empty-dark.png` | `25-onboarding_empty-light.png` | F01, F08, F13 |
| Today / elementary / en | `26-today_elementary-ax-xxxl-text.png` | `27-today_elementary-dark.png` | `28-today_elementary-light.png` | F02, F14, F16, F21 |
| Today / secondary / en | `29-today_secondary-ax-xxxl-text.png` | `30-today_secondary-dark.png` | `31-today_secondary-light.png` | F02, F04, F15–F17, F22 |
| Today / secondary / sk | `32-today_secondary_sk-ax-xxxl-text.png` | `33-today_secondary_sk-dark.png` | `34-today_secondary_sk-light.png` | F02, F15–F17; localized labels |
| Today / university / en | `35-today_university-ax-xxxl-text.png` | `36-today_university-dark.png` | `37-today_university-light.png` | F02, F14, F21 |
| Timetable day / secondary / en | `38-timetable.day_secondary-ax-xxxl-text.png` | `39-timetable.day_secondary-dark.png` | `40-timetable.day_secondary-light.png` | F03, F18–F22 |

`01-README.md` supplies the app purpose, constraints, capture conditions, profile/locale descriptions, and broader screen inventory. No linked-but-unattached screenshot is represented as reviewed.

## 10. Retained design-reference notes

These notes preserve the applicable lessons from the requested resources for future Tabula work. They are a reusable written record, not a claim that these repositories were installed or that persistent assistant memory was updated.

All four distinct original repository clone attempts failed with an environment GitHub access denial. The user then authorized the Markdown fallback. Image to Code's original direct link returned 404; an indexed original Markdown view remained readable, and the current Taste README points to `Leonxlnx/imagegen-skills`. Some companion documents were not retrievable. No repository scripts, generated-design workflow, or browser test suite was executed.

| Requested resource | What was available/studied | Rule retained for Tabula | Scope limit |
|---|---|---|---|
| [Taste skill](https://github.com/leonxlnx/taste-skill) · [Markdown](https://raw.githubusercontent.com/Leonxlnx/taste-skill/main/skills/taste-skill/SKILL.md) | Main skill's published review, hierarchy, screenshot inspection, and existing-project guidance | Inspect the actual interface, preserve the stack/content that work, identify the most consequential changes, and never claim unrun checks | Its app-screen companion could not be retrieved. Marketing-page bans on glass/emoji and fixed heading-line limits are not applied to this native accessible student app |
| [Web Design Guidelines skill](https://github.com/vercel-labs/agent-skills/blob/main/skills/web-design-guidelines/SKILL.md) · [current rules](https://raw.githubusercontent.com/vercel-labs/web-interface-guidelines/main/command.md) | Skill and live rule document | Meaningful control labels, semantic interactions, readable content, clear errors, localization, safe-area/focus visibility, and gesture alternatives | Translate principles to SwiftUI; HTML, CSS, browser routing, and hydration checks do not apply here |
| [Image to Code original Markdown view](https://github.com/leonxlnx/taste-skill/blob/main/skills/image-to-code-skill/SKILL.md?plain=1) · [current repository](https://github.com/Leonxlnx/imagegen-skills) | Indexed original instructions, particularly detailed visual analysis; current move confirmed in Taste README | Inspect readable source images closely; identify type, spacing, button hierarchy, layout, and unresolved details before implementation | A website generation workflow does not authorize replacing supplied evidence with invented screens. No image-to-code implementation was requested or performed |
| [Awesome Design](https://github.com/VoltAgent/awesome-design-md/) · [README](https://raw.githubusercontent.com/VoltAgent/awesome-design-md/main/README.md) | Published collection README and its design-system structure | Record colour roles, typography, component states, spacing, and adaptive behavior as reusable decisions | This is a reference collection, not a single native iOS skill. No individual brand DESIGN.md was successfully fetched or adopted |
| [Playwright CLI](https://github.com/microsoft/playwright-cli) · [skill Markdown](https://raw.githubusercontent.com/microsoft/playwright-cli/main/skills/playwright-cli/SKILL.md) | Published installation, interaction/snapshot, inspection, and test workflow guidance | Verify behavior with before/after state, readable evidence, and actual interaction results | Browser automation cannot exercise a native SwiftUI app. CLI was not installed or run; use native tooling for Tabula |

Working rules to carry forward: prioritize the student's next decision; remove actions without outcomes; preserve native behavior; show fewer secondary details until needed; reflow instead of shrinking accessible text; maintain consistent colour meanings; validate every supported state; distinguish what is observed from what is assumed.

## 11. Standards and primary references

Consulted for this review on 23 October 2026. The recommendations above are an adaptation to Tabula, not verbatim prescriptions from web-design resources.

- **[S1] Apple, Onboarding:** [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/onboarding) — brief, contextual introduction to a usable experience.
- **[S2] Apple, Buttons:** [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/buttons) — recognizable controls, appropriate hierarchy, press feedback, and general 44 × 44 pt hit-region guidance.
- **[S3] Apple, Accessibility:** [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/accessibility) — assistive-technology support, readable interfaces, and meaning beyond colour.
- **[S4] W3C, Contrast (Minimum):** [WCAG 2.2 understanding document](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html) — normal/large text ratios, inactive-control exceptions, and measurement caveats.
- **[S5] W3C, Non-text Contrast:** [WCAG 2.2 understanding document](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html) — contrast for meaningful custom graphical/control indicators, with exceptions for inactive/unmodified user-agent controls.
- **[S6] Apple, Materials and Liquid Glass:** [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) · [Liquid Glass overview](https://developer.apple.com/documentation/technologyoverviews/liquid-glass) — native navigation/control materials and a distinct content layer.
- **[S7] Apple, Color:** [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/color) — semantic colour, appearance adaptation, and consistent meaning.
- **[S8] Apple, SwiftUI Button:** [Developer documentation](https://developer.apple.com/documentation/swiftui/button) — native action semantics and context-appropriate appearance.

## 12. What is complete, and what remains unverified

**Completed:** all 40 supplied files reviewed; all 39 images visually inspected; representative problem areas examined at larger scale; selected original-pixel colour pairs measured; requested accessible design resources studied and recorded; 22 prioritized findings, proposed flows, editor cleanup rules, implementation directions, and acceptance checks prepared.

**Unverified:** which exact editor controls are placeholders, tap destinations, actual hit areas, full scroll reachability, VoiceOver output, notification behavior, runtime schedule calculations, saved-data behavior, and source-level causes. The report provides actionable specifications for those areas without claiming they were reproduced or fixed.
