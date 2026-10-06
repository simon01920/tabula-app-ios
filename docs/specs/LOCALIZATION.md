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
