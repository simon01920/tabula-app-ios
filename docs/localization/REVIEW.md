# Localization review log

Status of every shipped language. **All 12 launch languages are machine translations (Claude, Phase 2 stage C1). None has had a native-speaker review. Do not describe any of them as native quality.** Every non-English unit in `Resources/Localizable.xcstrings` carries `"state": "needs_review"`; a reviewer changes it to `translated` only after checking it (the completeness check accepts both states).

Source of truth: `Resources/Localizable.xcstrings` (797 keys after the follow-up pass: 420 from C1 plus the editor.*, timetable.* and today.* keys; the unused placeholder.* keys were deleted). Drafts/inputs of the first translation pass: `docs/localization/translations/<lang>.json` (the catalog is canonical; these files are the authored input and a record, `sr-Latn` has none because it is generated from `sr`).

## Language table

| Catalog id | Language | Status | Plural categories | Notes |
|---|---|---|---|---|
| `en` | English | source | one, other | development language |
| `sk` | Slovak | machine translation, needs native review | one, few, many, other | 8 Phase 0 probe strings were already `needs_review` |
| `cs` | Czech | machine translation, needs native review | one, few, many, other | |
| `pl` | Polish | machine translation, needs native review | one, few, many, other | integers use `many` for 0 and 5+; `other` (fractions) is filled with a genitive form |
| `hu` | Hungarian | machine translation, needs native review | one, other | counted nouns stay singular, so `one` and `other` text are identical except where the sentence differs |
| `ro` | Romanian | machine translation, needs native review | one, few, other | `other` (20+) uses the "de" form (`20 de ore`) |
| `de` | German | machine translation, needs native review | one, other | informal "du" throughout |
| `fr` | French | machine translation, needs native review | one, other | `one` covers 0 and 1 (CLDR); NBSP / narrow NBSP before `: ; ? !` |
| `uk` | Ukrainian | machine translation, needs native review | one, few, many, other | integers use `many` for 0 and 5+ |
| `sr` | Serbian, **Cyrillic** | machine translation, needs native review | one, few, other | CLDR has no `many` for Serbian |
| `sr-Latn` | Serbian, **Latin** | **generated** by 1:1 transliteration of `sr` (`scripts/lib/l10n_common.py: sr_to_latin`), needs native review | one, few, other | review `sr` and re-run the derivation; never edit `sr-Latn` by hand without editing `sr` |
| `ja` | Japanese | machine translation, needs native review | other | polite (です・ます) style |
| `zh-Hans` | Chinese, Simplified | machine translation, needs native review | other | Traditional Chinese is an open decision for the human (D10); not shipped |

### Identifier choice (verified 2026-10-10)
`sr` is Cyrillic and `sr-Latn` is Latin (Apple tables treat bare `sr` as Cyrillic; CLDR likely-subtags `sr` -> `sr-Cyrl-RS`; a Latin catalog entry is declared `sr-Latn`). `zh-Hans` for Simplified Chinese. The same identifiers are used as String Catalog keys, `<id>.lproj` folder names on the xtool path and `CFBundleLocalizations` (XcodeGen cannot set `knownRegions`; Xcode compiles all catalog languages regardless). **Not yet verified on a device:** that an iPhone set to "Srpski" (Latin) resolves to `sr-Latn` and one set to "Српски" resolves to `sr`. That is on the device checklist (see "Manual on-device checks"). If Apple resolves a Serbian device language to a different id, only the catalog keys and the lists in `xtool.yml` and `Config/*-Info.plist` need renaming (`validate_config.py` keeps them in sync).

### Store listing
**Serbian is not an App Store Connect metadata language** (Phase 0, RISKS #25, gate decision D10). The in-app Serbian (Cyrillic and Latin) is fine; the store page needs a fallback language (default proposal: English). Human decides.

## How a reviewer works (review document, Phase 4 C2, decision P3-3)
Everything a reviewer needs is generated into `docs/localization/review/` (see its `README.md`); nobody edits the catalog by hand.
1. Open `docs/localization/review/index.html` (self-contained, offline, phone and desktop, light/dark): one row per string and plural form with key, "where it is used" (the catalog comment), English and the 12 languages. A language picker shows e.g. only English + Slovak; search; filter all / needs_review / translated / changed since last review. Placeholders (`%@`, `%lld`, `%1$@`) are highlighted. A short "How to review" is at the top in English and Slovak.
2. Fill the **`corrected`** (and optionally `note`) column in the language's CSV (`<lang>.csv`: key, plural_form, context, english, current, corrected, note; UTF-8 with BOM). Empty = skip, `[ok]` = current text is right, any other text = the correction. Keep format specifiers identical in type and count; translate every plural form on its own row. Excel with `;` separators and files without BOM are fine.
3. The maintainer runs `python3 scripts/l10n-review-import.py --dry-run <lang>.csv`, then without `--dry-run`. Accepted rows become `translated` (reviewed); rows whose placeholders differ from English, or whose key/plural form does not exist, are rejected and listed. Corrected `sr` rows re-derive `sr-Latn`. The catalog stays in canonical form.
4. `python3 scripts/l10n-review-export.py` regenerates the folder (also run it whenever strings change); commit catalogs and folder together. Record reviewer, date and scope in the table below.
5. `bash scripts/validate.sh` must stay green (completeness is a FAIL, not a warning). It runs the round-trip test (`scripts/l10n-review-test.py`) and **warns** (does not fail) when the review folder is stale. Staleness is a **hash** check (`docs/localization/review/SOURCE_HASH` = sha256 of both catalogs + `baseline.json`), not a file-time comparison, because git checkouts reset times.
6. `baseline.json` records what a reviewer last signed off (written only by the import); the "changed since last review" filter compares against it. Without an entry a row counts as changed until it is `translated`.

Row counts (2026-10-16): 1,205 keys (1,200 `Localizable` + 5 `InfoPlist`), 1,391 rows in the HTML; CSV rows per language: sk, cs, pl, uk 1,391; ro 1,329; sr, sr-Latn 1,329; hu, de, fr 1,267; ja, zh-Hans 1,205. All still machine translations until reviewed.

| Language | Reviewer | Date | Scope | Result |
|---|---|---|---|---|
| (none yet) | | | | |

## Terminology to check (per language)
Columns: lesson (school) / class-lecture (university term in `terminology.*`) / period label / bell schedule / subject / homework / exam vs test / term / odd-even weeks. These are the choices made in the machine pass, to be confirmed or changed by the reviewer.

| Lang | lesson | class (univ.) | period | bell schedule | subject | homework | exam / test (sample) | term | odd / even weeks |
|---|---|---|---|---|---|---|---|---|---|
| sk | hodina | prednáška | hodina (`%lld. hodina`) | rozvrh zvonenia | predmet | domáca úloha | skúška / písomka | semester, obdobie | nepárne / párne týždne |
| cs | hodina | přednáška | hodina | rozvrh zvonění | předmět | domácí úkol | zkouška / písemka | semestr, období | liché / sudé týdny |
| pl | lekcja | zajęcia | lekcja | plan dzwonków | przedmiot | praca domowa | egzamin / sprawdzian | semestr, okres | tygodnie nieparzyste / parzyste |
| hu | tanóra | óra | óra (`%lld. óra`) | csengetési rend | tantárgy | házi feladat | vizsga / témazáró dolgozat | félév, időszak | páratlan / páros hetek |
| ro | oră | curs | oră | program de sonerie | materie | temă | examen / test | semestru, perioadă | săptămâni impare / pare |
| de | Stunde | Veranstaltung | Stunde | Klingelplan | Fach | Hausaufgabe | Prüfung / Klassenarbeit | Semester, Zeitraum | ungerade / gerade Wochen |
| fr | cours | séance | heure | horaires de sonnerie | matière | devoirs | examen / contrôle | semestre, période | semaines impaires / paires |
| uk | урок | пара | урок | розклад дзвінків | предмет | домашнє завдання | іспит / контрольна | семестр, період | непарні / парні тижні |
| sr (Cyrl/Latn) | час / čas | предавање / predavanje | час / čas | распоред звона / raspored zvona | предмет / predmet | домаћи задатак / domaći zadatak | испит / контролни | семестар, период | непарне / парне седмице |
| ja | 授業 | 講義 | 時限 (`%lld限`) | 時限表 | 科目 | 宿題 | 試験 / 単元テスト | 学期 | 奇数週 / 偶数週 |
| zh-Hans | 课 | 课程 | 节 (`第%lld节`) | 作息时间表 | 科目 | 作业 | 考试 / 单元测验 | 学期 | 单周 / 双周 |

Questions for reviewers, all languages: (a) is the "class" word for the university profile natural, or should `terminology.classLecture` be "lecture"? (b) bell schedule: the app means the table of period start/end times that repeats every day. (c) Apple terms for Time Sensitive, Focus, silent switch and Settings must match the user's iOS wording (ja "即時通知", zh "时效性", fr "Concentration", de "Fokus", ...). (d) formal vs informal address. Machine pass: informal in de (du), hu, pl, ro and zh-Hans; formal in sk, cs, uk, sr (vykanie) and fr (vous); ja polite style. The product should pick one policy per language (a younger audience suggests informal where natural).

## Known risky strings
- **Long languages (German, Hungarian, French, Romanian, Polish, Ukrainian):** tight cells (tab bar, badges, steppers, `schedule.change.*` badges, `lesson.status.*`, `onboarding.time.*` labels). Longest short UI strings vs English at C1: de `Zeiten der Veranstaltungen`, `Erste Veranstaltung beginnt`, `Dauer einer Veranstaltung`; hu `Hogyan érkeznek az emlékeztetők`, `Módosult a csomagolási lista`, `Időszak dátumainak megadása`; ro `Lista de lucruri de adus s-a schimbat`; pl `Przełącznik wyciszenia i tryb skupienia`; fr `Université / enseignement supérieur`. Report overflow to the UI engineer after the pseudo-locale / long-string pass.
- **CJK (ja, zh-Hans):** no spaces, so line breaking happens inside sentences; check `lineLimit`, truncation and `minimumScaleFactor` on tiles and widgets; full-width punctuation (`、。：？（）`) is intentional. `a11y.separator` is `、` (ja) and `，` (zh-Hans).
- **Serbian script choice:** both scripts ship; `sr-Latn` is mechanically transliterated, so Latin wording follows the Cyrillic review. Latin brand names (`Tabula`, `iPhone`, `Pro`, `iOS`, `App Store`) stay Latin inside Cyrillic text. A/B day labels keep Latin letters to match the data model.
- **Strings saved as user data** (`onboarding.default.*`, `sample.*`): translated once at creation time in the language active then; they do not follow later language changes. Names should be short and natural.
- **`sample.subject.foreignLanguage` / `nativeLanguage`:** English is the first foreign language in the 11 translated locales; the native-language subject is the language itself (Slovenčina is NOT used for sk: "Slovenský jazyk"). Reviewer: check against local school conventions.
- **Plural wording with a second argument** (`reminder.exam.inDays*`, `reminder.packTonight.*`, `reminder.task.dueInDays*`): the date argument is formatted by the app and put in parentheses to avoid case/preposition agreement with an unknown string. Hungarian and Slavic reviewers may prefer different phrasing.
- **`share.error.tooMany.*`:** worded as "Maximum when sharing: N noun" so the noun can agree with the number in every language without a case ending.
- **Apple terms:** "Time Sensitive", "Focus", silent switch, App Group, iCloud, App Store. Check against the iOS release the reviewer uses.
- **Grammatical gender/number of user text** inserted into sentences (`%@` = room, teacher, subject names): sentences were kept free of agreement with the inserted text.
- **Info.plist strings** (`Resources/InfoPlist.xcstrings`, Phase 3 C2): `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSAlarmKitUsageDescription` in all 12 languages, all `needs_review` (machine-translated; `sr-Latn` is derived from `sr`). `CFBundleDisplayName` stays "Tabula" in every language. Reviewer: these are short permission prompts, check that the reason is clear and polite; address form is informal in de, pl, hu, ro, zh-Hans and formal/plural in sk, cs, fr, uk, sr; reconcile with the rest of the catalog. The widget extension's own display name ("Tabula Widgets") and the watch app are not localised (not shown to users). Add any new `NS*UsageDescription` to the plist AND the catalog; `validate_config.py` fails otherwise.

## Machine-translation provenance
Pass 3 (2026-10-10, Phase 2 QA fix pass): 5 keys (`editor.warnings.*`, `editor.warning.periodInFreeForm`, `editor.subject.emojiName`), model-authored, reviewer: check the free-form/bell-schedule wording against the terms used by `editor.time.bell` / `editor.time.free`. Pass 2 (2026-10-10, follow-up): the 383 editor / timetable / today keys, same terminology table; the six unused `*.placeholder.*` keys were removed. Pass 1 (Phase 2 stage C1, 2026-10-10): model-authored for all 11 target languages from the English strings and translator comments. No external translation service, no glossary import. `sk` probe strings (8) pre-existed from Phase 0.

## Manual on-device checks (language)
- Settings > Tabula > Language: all 12 languages offered (incl. Srpski/Српски). Cold start in each: no raw keys (`shell.tab.today`, `a11y.lesson.room`) anywhere; plural strings (conflicts, share warnings, reminder bodies) read correctly for 1, 2, 5, 21.
- Device language "Srpski (latinica)" picks Latin, "Српски" picks Cyrillic; if not, see "Identifier choice".
- Dynamic Type XXL + de/hu/fr + ja/zh on the Today and Timetable tabs, widget gallery names.

### Phase 3 Stage A additions (2026-10-10, notifications-engineer)
56 new keys (`shell.tab.tasks/exams`, `tasks.*`, `exams.*`, `attachments.*`, `reminders.override.*`, `alarm.*`,
`reminder.test.*`, `health.*`), English + machine translations for all 11 authored languages (`sr-Latn` derived),
all `needs_review`. Terminology follows the existing `settings.reminders.*` strings (e.g. sk "Časovo citlivé",
de "Zeitkritisch", ja "即時通知"). French uses NBSP before ":"; Serbian keeps the app name "Tabula" in Latin script, as
the existing strings do. Apple UI terms (Focus, Low Power Mode, Background App Refresh, Action button, Control Center)
should be checked against each language's iOS wording during review. Recorded in `translations/<lang>.json`.

### Phase 3 stage B3 additions (2026-10-14, sync-storage-engineer)
49 new `attachments.*` keys (add menu, row titles/hints, rename/delete/link dialogs, quota and error messages, voice
recorder), English + model-authored translations for the 11 authored languages (`sr-Latn` derived), all
`needs_review`. Terms: "Voice note" follows the iOS app name where natural (de "Sprachnotiz", fr "Mémo vocal",
ja "ボイスメモ", zh "语音备忘"); keep `https://example.com` literal. `attachments.usage.*` / `attachments.error.quota`
insert locale-formatted byte sizes ("12,3 MB"). The Stage A key `attachments.placeholder` is no longer used by code
(left in place; remove in a cleanup pass). `NSMicrophoneUsageDescription` is English-only like the other usage strings.
### Phase 3 Stage B2 additions (2026-10-10, swiftui-engineer-sonnet)
72 new keys (`exams.segment.*`, `exams.week.*`, `exams.period.*`, `exams.when.*`, `exams.kind.*`, `exams.detail.*`,
`exams.editor.*`, `exams.a11y.*`, `exams.subtitle`, `exams.action.*`, `exams.empty.*`), model-authored for 11 languages
(`sr-Latn` derived), all `needs_review`. Reviewer: exam-type terms (sk "Polsemestrálna skúška", pl "Kolokwium" for
midterm, ja 中間試験/期末試験), plural forms of `exams.when.inDays/daysAgo` and `exams.period.count` (sk/cs/pl/uk/ro/sr
categories), and "Exam period" (sk "Skúškové obdobie", de "Prüfungszeitraum").
### Phase 3 Stage B4 additions (2026-10-10, localization-engineer-sonnet)
91 new keys (`reminders.*`, `health.*`, `settings.reminder-health.*`, `settings.reminders.*`: reminder rule editor, follow-up, reminder times, override section, permission sheet, quiet hours, health check and test results), machine-translated (model-authored) for all 11 authored languages, `sr-Latn` derived, all `needs_review`. Not native quality. 8 plural keys (hours/minutes/days/reminder counts, Time Sensitive lead) use the full CLDR categories for sk/cs/pl/uk/sr/ro; reviewers please check Slavic genitive/accusative forms ("minúty" vs "minút", "hodinu pred") and Hungarian wording without a case suffix after the time argument. Terminology reuses existing strings (Time Sensitive, Loud alarm, Standard, Focus, Quiet hours = sk "Pokojné hodiny", cs "Tiché hodiny", de "Ruhezeiten"). Quiet hours wording is new and worth a native check.

### Phase 3 Stage C1 additions (2026-10-14, swiftui-engineer)
9 new keys (`lesson.badge.tasks/exam`, `a11y.lesson.tasks/exam`, `today.section.dueToday`, `today.tasks.overdue(.hint)`,
`timetable.detail.tasks/addHomework`), model-authored for 11 languages (`sr-Latn` derived), all `needs_review`.
Reviewer: `lesson.badge.tasks` must stay very short (it sits on lesson tiles next to an icon); the VoiceOver phrases
`a11y.lesson.tasks/exam` are appended to the comma-separated lesson sentence (lowercase mid-sentence); the overdue chip
`today.tasks.overdue` agrees with an implied "tasks" (sk/cs "po termíne", pl/uk/sr/ro gender/number forms). Terminology
reuses Task = sk "Úloha", cs "Úkol", de "Aufgabe"; Exam = sk "Skúška", de "Prüfung"; homework = sk "domáca úloha",
de "Hausaufgabe", fr "devoir", ja 宿題, zh 作业.

## Screenshot fixes (Phase 3)

New keys `tasks.quickAdd.due.tomorrow`, `tasks.quickAdd.due.nextLesson` (replace `tasks.quickAdd.dueTomorrow` / `dueNextLesson`) and `settings.reminders.kind.edit.a11y` are machine-translated into all 12 languages (needs_review). The date comes first in the next-lesson value; check the middle dot reads naturally in ja/zh.
### Phase 3 final QA fixes (2026-10-15, Opus fix agent)
1 new key (`attachments.unavailable`, neutral text when the attachments section is shown without its editor host) and
1 changed English text (`health.notifications.notDetermined`: Tabula now asks once, after the first save of a task or
exam that has a reminder; old translations dropped, re-authored). Model-authored for 11 languages (`sr-Latn` derived),
all `needs_review`. Reviewer: "asks once" must not read as a promise to ask again; ro uses "reamintire" as elsewhere.

### Phase 4 Stage C1 additions (2026-10-16, core-domain-engineer)
2 new keys (`editor.subjects.moveUp`, `editor.subjects.moveDown`: VoiceOver actions on a subjects-list row) and 1 changed
English text (`editor.subjects.footer`: the list is no longer alphabetical; it now says how to reorder — old translations
dropped, re-authored). Model-authored for 11 languages (`sr-Latn` derived), all `needs_review`. Reviewer: the footer
names the system Edit button, so it must match the iOS label in each language (sk "Upraviť", cs "Upravit", pl "Edytuj",
hu "Szerkesztés", ro "Editează", de "Bearbeiten", fr "Modifier", uk "Редагувати", sr "Уреди", ja 編集, zh 编辑); the move
actions are short imperative labels read by VoiceOver.

### Phase 4 Stage C1 QA fixes (2026-10-16, core-domain-engineer)
4 new keys (`editor.subjects.reorder` toolbar button, `editor.subjects.reorder.done` its VoiceOver label in reorder mode,
`editor.subjects.footer.single`, `editor.subjects.moved` VoiceOver announcement with two numbers) and `editor.subjects.footer`
re-authored again (it now names the Reorder button, not Edit). Model-authored for 11 languages (`sr-Latn` derived), all
`needs_review`. Reviewer: the footer must use exactly the wording of `editor.subjects.reorder`; `editor.subjects.moved` is
phrased without a counted noun after the numbers ("position 3 of 8" / sk "na pozíciu 3 z 8") so no plural forms are needed —
check that this holds in each language (hu uses "Új pozíció: 3, összesen 8").
### Phase 4 Stage A additions (2026-10-16, widgets-watch-engineer)
13 new keys (`widget.nowNext.*`, `widget.open.*`, `widget.pro.*`), model-authored for 11 languages (`sr-Latn` derived),
all `needs_review`. The widget otherwise reuses the Today header keys (`today.header.*`, `a11y.lesson.*`). Reviewer: the
widget name `widget.nowNext.name` appears in the iOS widget gallery (sk "Teraz a ďalej", de "Jetzt & Als Nächstes");
`widget.nowNext.nextShort` is one line on the Lock Screen and must stay short; `widget.pro.short` ≤ about 4 characters;
the brand stays undeclined ("aplikácia Tabula", "aplikace Tabula", "aplikacja Tabula"); `widget.nowNext.inline.current
%@ %@` is only a separator format (`%1$@ · %2$@`, ja `・`).
### Phase 4 Stage B2 additions (2026-10-22, widgets-watch-engineer)
12 new keys (`liveActivity.exam.*`, `liveActivity.alert.at`, `settings.liveActivities.*`), model-authored for 11 languages
(`sr-Latn` derived), all `needs_review`. The Live Activities otherwise reuse the Today header / widget keys. Reviewer: use
Apple's official names for "Live Activities", "Lock Screen" and "Dynamic Island" in each language (de "Live-Aktivitäten",
fr "Activités en direct", sk/cs "Živé aktivity", ja "ライブアクティビティ", zh-Hans "实时活动" / "灵动岛");
`liveActivity.exam.*` are one-line captions on the Lock Screen and must stay short; `liveActivity.alert.at` is the body of
the alert iOS shows when a scheduled activity starts ("Mathematics at 8:00"; hu "%1$@ – kezdés: %2$@" avoids the time
suffix, ja/zh put "start" after the time); the brand stays undeclined ("aplikácia Tabula").
### Phase 4 Stage B3 additions (2026-10-23, notifications-engineer)
19 new keys in Localizable.xcstrings (`intent.*`, `widget.homework.markDone`, `alarm.button.done`) and a new catalog,
`Resources/AppShortcuts.xcstrings`, with the 4 App Shortcut phrases; all model-authored for 11 languages (`sr-Latn`
derived), all `needs_review`. Reviewer: intent titles appear in the Shortcuts app and in Siri / Spotlight, so use the
platform's imperative style ("Označiť úlohu ako hotovú", "Aufgabe als erledigt markieren"); `alarm.button.done` is the
button on the full-screen alarm and must stay one short word; `widget.homework.markDone` is a VoiceOver label
(language-specific quotation marks around the task title). The App Shortcut phrases are what people SAY to Siri: every
translation must keep `${applicationName}` exactly once (validate_config.py checks it) and read naturally with the app
name inserted (hu uses "a(z) ${applicationName}" because the article depends on the name; ja/zh put the name first).
The AppShortcuts catalog is not part of the review export (the export covers Localizable + InfoPlist); review its 4 keys
in the file itself. The brand stays undeclined ("aplikácia Tabula", "Отвара Tabula"). Final QA: + `intent.param.alarm`
(an internal parameter title, rarely visible); `probe.intent.shortTitle` removed (the probe's App Shortcut is gone).
### Phase 4U U1 additions (2026-10-26, swiftui-engineer)
6 new keys (5 after QA: `editor.validation.announcement` was removed again), model-authored for 11 languages (`sr-Latn` derived), all `needs_review`: `now.marker` (the highlighter
"NOW" marker on the current lesson; the app shows it in capitals, VoiceOver reads it as written, so keep one short word:
"Teraz", "Jetzt", 今), `editor.validation.announcement` (VoiceOver only, after Save on an incomplete form), and the
title-field hints `exams.editor.name.prompt`, `tasks.field.title.prompt`, `editor.subject.name.prompt`,
`editor.timetable.name.prompt` (grey text inside the empty field, also its VoiceOver label; the exam word follows each
language's existing `exams.*` wording, e.g. sk "skúška", cs "zkouška"). Removed as unused (the screens now use the standard × close button and the new prompts):
`timetable.action.done`, `editor.common.close`, `exams.editor.name`, `tasks.field.title`, `editor.subject.name`,
`editor.timetable.name`.
### Phase 4U Stage U5b additions (2026-10-26, swiftui-engineer)
44 new keys (`editor.bell.*` for the restructured bell schedule editor, `editor.lesson.weeks.*`, `editor.lesson.moreDetails*`,
`editor.timetables.reorder*` / `*.action`, `editor.common.edit`, `editor.timetable.days`, `editor.subject.icon`,
`editor.subject.palette.locked*`, `editor.dayChange.move`) and 21 rewritten keys (translations dropped and re-authored),
model-authored for 11 languages (`sr-Latn` derived), all `needs_review`; 29 unused editor keys removed. Meaning changes
to check: **Breaks → Holidays** in the terms editor (`editor.breaks.*`, `editor.terms.title/open`, `editor.impact.breaks`,
`editor.rotation.day.skipsBreaks`): "holidays" are days off school, never the gap between lessons (sk "voľné dni", de
"Ferien", fr "vacances"); the day-change kinds "Use another day's timetable" / "Shortened lessons";
`timetable.detail.changeDay` "Cancel, Move or Substitute…" (a button, keep it short); `editor.fields.*` and
`onboarding.fields.subtitle` now say that the detail switches only affect lesson cards (UX decision D10).
`editor.lesson.weeks.named` is "Week %@" for a one- or two-letter week name ("Week A"); longer names are shown alone.
`editor.lesson.weeks.every.segment` is one segment of a three-part segmented control and must stay short.
### Phase 4U Stage U5a additions (2026-10-23, swiftui-engineer-sonnet)
34 new keys (`settings.section.*`, `settings.bell.*`, `settings.terms.row`, `settings.timetables.add`, `settings.value.*`,
`settings.reminders.summary.on`, `settings.reminders.delivery.*`, `settings.schooltype.title`, `settings.datetime.*`,
`settings.colors.*`, `settings.aboutfeedback.title`, `settings.about.{feedback,privacyPolicy,rate,acknowledgements.body2}`,
`reminders.tier.timeSensitive.unavailable`, `health.{checks,technical}.title`), model-authored for 11 languages (`sr-Latn`
derived), all `needs_review`. 31 keys of the old Appearance / Calendar / Reminders / About screens were removed. Reviewer:
count phrases (`settings.reminders.summary.on`, `settings.colors.applied`, `settings.colors.apply.confirm.message`) are
written as "label: N" in the Slavic languages to avoid noun declension, check they read naturally; `settings.colors.undo`
should differ from Cancel where the language allows (ro "Anulează modificarea"; fr uses Apple's "Annuler"); the Time Sensitive
tier names reuse the existing `settings.reminders.timesensitive.title` wording per language.
### Phase 4U Stage U4 additions (2026-10-26, swiftui-engineer)
31 new keys (`timetable.cycle.oddWeek/evenWeek`, `timetable.quickAdd.every.*`, `.slot.period`, `.scope.*`,
`.cycleWeekOnlyFooter`, `timetable.subtitle.withCycle`, `timetable.now`, `timetable.legend.*`, `timetable.day.*`,
`timetable.a11y.todayHint.*`, `timetable.options.editTimetable/addLesson`, `timetable.empty.noLessons.*`,
`timetable.detail.timeChanged.a11y`), model-authored for 11 languages (`sr-Latn` derived), all `needs_review`; and
`timetable.detail.changes` changed to sentence case ("Changes on this day"; translations kept, `needs_review`).
Reviewer: "Odd week" / "Even week" are what Slovak and Czech schools say (sk "Nepárny/Párny týždeň", cs "Lichý/Sudý
týden"); `timetable.quickAdd.every.*` are complete phrases with the weekday in the right case and gender (sk "Každú
stredu", cs "Každou středu", pl "W każdą środę", uk "Щосереди") joined to the week and period only by the
`%1$@ · %2$@` formats; `timetable.now` is a one-word tag shown in capitals. Now unused (for U8 to remove):
`timetable.quickAdd.period`, `timetable.quickAdd.cycleWeekFooter`.
Integration (2026-10-26): `timetable.now` removed again; the timetable shows U1's `now.marker` (same word in all
13 languages, checked before removal).
