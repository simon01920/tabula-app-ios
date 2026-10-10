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

## How a reviewer works
1. Pick a language, open the catalog in Xcode (String Catalog editor, filter "Needs Review") or review `docs/localization/translations/<lang>.json`.
2. Read each string with its **comment** (context, arguments, where it appears).
3. Fix wording; keep format specifiers (`%@`, `%lld`, `%1$lld`, ...) identical in type and count; keep plural categories complete.
4. Mark reviewed units `translated`, record the reviewer and date in the table below.
5. `bash scripts/validate.sh` must stay green (completeness is a FAIL, not a warning).

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
- **Info.plist usage strings** (camera, photo library, AlarmKit) and the app display name are **not localized yet** (they fall back to English); they need `InfoPlist.xcstrings` in a later stage.

## Machine-translation provenance
Pass 3 (2026-10-10, Phase 2 QA fix pass): 5 keys (`editor.warnings.*`, `editor.warning.periodInFreeForm`, `editor.subject.emojiName`), model-authored, reviewer: check the free-form/bell-schedule wording against the terms used by `editor.time.bell` / `editor.time.free`. Pass 2 (2026-10-10, follow-up): the 383 editor / timetable / today keys, same terminology table; the six unused `*.placeholder.*` keys were removed. Pass 1 (Phase 2 stage C1, 2026-10-10): model-authored for all 11 target languages from the English strings and translator comments. No external translation service, no glossary import. `sk` probe strings (8) pre-existed from Phase 0.

## Manual on-device checks (language)
- Settings > Tabula > Language: all 12 languages offered (incl. Srpski/Српски). Cold start in each: no raw keys (`shell.tab.today`, `a11y.lesson.room`) anywhere; plural strings (conflicts, share warnings, reminder bodies) read correctly for 1, 2, 5, 21.
- Device language "Srpski (latinica)" picks Latin, "Српски" picks Cyrillic; if not, see "Identifier choice".
- Dynamic Type XXL + de/hu/fr + ja/zh on the Today and Timetable tabs, widget gallery names.
