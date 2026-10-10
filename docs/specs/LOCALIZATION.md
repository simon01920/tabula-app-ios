# LOCALIZATION

## Languages at launch (12)
English (en), Slovak (sk), Czech (cs), Polish (pl), Hungarian (hu), Romanian (ro), German (de), French (fr), Ukrainian (uk), Serbian (sr — provide **Latin and Cyrillic**), Japanese (ja), Chinese (zh — default **Simplified**; Traditional is an open question for the human).

## Rules
- String Catalogs (`.xcstrings`) for app, widgets, Watch, App Intents, Info.plist usage strings (camera, AlarmKit, notifications), and App Store metadata drafts.
- Context comment for every string. No concatenated fragments. Plural variations per language (Slavic languages have multiple plural categories). Use `Locale`-aware formatters for dates, times, durations; week start from locale with user override.
- Subject abbreviations in tight grid cells: user-defined short name, otherwise smart truncation per script.
- Layout stress: German/Hungarian long strings, CJK line breaking, Dynamic Type XXL, Cyrillic fonts, no clipped text in widgets/Watch. Use pseudo-locales and a long-string test mode.
- Machine translation is acceptable for the first pass but every language is logged in `docs/localization/REVIEW.md` as "needs native review" with a checklist (terminology: lesson/class/lecture, homework/assignment, exam vs test, bell schedule). Never claim native quality.
- Onboarding terminology adapts by profile and language; day names, month names and time formats come from the system.
- OCR import must be tested per language (diacritics: š č ž ľ ť ď ň ä ô ř ě ő ű ă î ș ț ł ą ę ć ś ź ż є ї і ґ, and kana/kanji/hanzi).

## Identifiers and wiring (Phase 2 C1)
- Catalog / `.lproj` / `CFBundleLocalizations` / XcodeGen `knownRegions` ids: `en sk cs pl hu ro de fr uk sr sr-Latn ja zh-Hans`. `sr` = Serbian Cyrillic, `sr-Latn` = Serbian Latin, `zh-Hans` = Simplified Chinese. One list, checked for equality by `scripts/validate_config.py` (catalog languages, `xtool.yml` `.build-l10n/<id>.lproj` for app and widget, `project.yml` `options.knownRegions`, `Config/App-Info.plist` and `Config/Widgets-Info.plist` `CFBundleLocalizations`). Single source for the scripts: `scripts/lib/l10n_common.py`.
- **Completeness is a validation FAIL.** iOS does not fall back to English per key (CI, `-AppleLanguages (sk)`: raw keys such as `shell.tab.today` appeared), so a shipped language must have every key, with the same format specifiers as English and the CLDR plural categories of that language (sk/cs/pl/uk: one, few, many, other; sr/sr-Latn/ro: one, few, other; hu/de/fr: one, other; ja/zh-Hans: other). Serbian has no `many` in CLDR.
- All non-English units are `needs_review` (machine translation); log them in `docs/localization/REVIEW.md`.
- **Adding strings:** `scripts/l10n-add.py` (English) -> `python3 scripts/l10n-translate-missing.py status|list --out missing.json` -> a translator fills `template` (translate `sr` only, `sr-Latn` is transliterated on merge) -> `python3 scripts/l10n-translate-missing.py merge filled.json` -> `bash scripts/validate.sh`.
- Xcode path: Xcode compiles the catalog. xtool path: `scripts/l10n-compile.py` writes `<id>.lproj/Localizable.strings(dict)`; the plural variable takes the type of argument 1 even when a translation re-orders positional arguments.
