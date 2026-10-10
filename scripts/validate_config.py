#!/usr/bin/env python3
"""Static consistency checks between the two build paths (called by scripts/validate.sh).

Usage: validate_config.py <repo_root> <dump_default.json> <dump_macro.json> <dump_core.json> <dump_ui.json>
  dump_*.json = `swift package dump-package` output for: root (TABULA_MACRO_PROBES unset), root
  (TABULA_MACRO_PROBES=1), Packages/TimetableCore, Packages/TimetableUI.
Prints OK/FAIL/WARN lines; exit code = number of FAILs (capped at 1).
"""
import json
import pathlib
import plistlib
import re
import sys

import yaml

ROOT = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(ROOT / "scripts"))
sys.dont_write_bytecode = True   # no scripts/__pycache__ in the working tree
import identity  # noqa: E402  (scripts/identity.py: Config/AppIdentity.xcconfig reader)

FAILS = 0


def ok(msg):
    print(f"OK   {msg}")


def fail(msg):
    global FAILS
    FAILS += 1
    print(f"FAIL {msg}")


def warn(msg):
    print(f"WARN {msg}")


def check(cond, msg_ok, msg_fail):
    ok(msg_ok) if cond else fail(msg_fail)


def load_dump(path):
    raw = pathlib.Path(path).read_text()
    return json.loads(raw[raw.index("{"):])


def defines(dump, target):
    t = next(t for t in dump["targets"] if t["name"] == target)
    return [s["kind"]["define"]["_0"] for s in t.get("settings", []) if "define" in s.get("kind", {})]


def platform(dump, name):
    return next((p["version"] for p in dump.get("platforms", []) if p["platformName"] == name), None)


dump_default, dump_macro, dump_core, dump_ui = (load_dump(p) for p in sys.argv[2:6])
xt = yaml.safe_load((ROOT / "xtool.yml").read_text())
pj = yaml.safe_load((ROOT / "project.yml").read_text())
tgt = pj["targets"]
base = lambda t: tgt[t].get("settings", {}).get("base", {})  # noqa: E731

# Identity values as Xcode resolves them from Config/AppIdentity.xcconfig (switch as committed, i.e. off).
ID_RAW = identity.parse(ROOT / "Config/AppIdentity.xcconfig")
ID = identity.resolve(ID_RAW)
ID_PAID = identity.resolve(ID_RAW, {"TABULA_PAID_ACCOUNT": "1"})


def xs(value, values=ID):
    """Resolve $(VAR) references in a project.yml setting the way Xcode would (identity values only)."""
    return identity.resolve({**values, "__v": str(value)})["__v"]

# --- xtool.yml schema (xtool 1.20.1 PackSchema) --------------------------------------------------------
allowed = {"version", "orgID", "bundleID", "product", "infoPath", "entitlementsPath", "iconPath",
           "resources", "extensions", "skipLSP"}
ext_allowed = {"product", "bundleID", "infoPath", "resources", "entitlementsPath"}
check(not set(xt) - allowed, "xtool.yml keys match PackSchema", f"xtool.yml unknown keys {set(xt) - allowed}")
for e in xt.get("extensions", []):
    check(not set(e) - ext_allowed, f"xtool.yml extension {e['product']} keys", f"bad keys {set(e) - ext_allowed}")
for key in ("infoPath", "entitlementsPath", "iconPath"):
    check((ROOT / xt[key]).exists(), f"xtool.yml {key} exists", f"xtool.yml {key} missing {xt[key]}")
ext = next(e for e in xt["extensions"] if e["product"] == "TabulaWidgets")

# --- same sources -----------------------------------------------------------------------------------------
srcs = {t: [s["path"] if isinstance(s, dict) else s for s in v.get("sources", [])] for t, v in tgt.items()}
for t, need in {"TabulaApp": "App/Sources", "TabulaWidgets": "WidgetExtension/Sources",
                "TabulaWatch": "WatchApp/Sources"}.items():
    check(need in srcs.get(t, []), f"project.yml {t} compiles {need}", f"project.yml {t} must compile {need}")

# --- bundle IDs -------------------------------------------------------------------------------------------
app_id = xt["bundleID"]
widget_id_xtool = ext.get("bundleID") or f"{app_id}.{ext['product']}"   # Planner: orgID(app.bundleID).product
check(xs(base("TabulaApp").get("PRODUCT_BUNDLE_IDENTIFIER")) == app_id,
      f"app bundle ID identical on both paths ({app_id})", "app bundle ID differs between xtool.yml and project.yml")
check(xs(base("TabulaWidgets").get("PRODUCT_BUNDLE_IDENTIFIER")) == widget_id_xtool,
      f"widget bundle ID identical on both paths ({widget_id_xtool})", "widget bundle ID differs")
watch_id = xs(base("TabulaWatch").get("PRODUCT_BUNDLE_IDENTIFIER", ""))
check(watch_id.startswith(app_id + "."), f"watch bundle ID {watch_id} is prefixed by the app ID",
      f"watch bundle ID {watch_id} must start with {app_id}.")
watch_plist = plistlib.load(open(ROOT / base("TabulaWatch")["INFOPLIST_FILE"], "rb"))
check(watch_plist.get("WKCompanionAppBundleIdentifier") == app_id,
      "WKCompanionAppBundleIdentifier = app bundle ID", "WKCompanionAppBundleIdentifier mismatch")

# --- deployment targets & Swift language mode ---------------------------------------------------------------
dt = pj["options"]["deploymentTarget"]
check(platform(dump_default, "ios") == dt["iOS"] == "26.0", "iOS deployment target 26.0 (Package.swift = project.yml)",
      f"iOS deployment target mismatch: Package.swift {platform(dump_default, 'ios')} vs project.yml {dt['iOS']}")
for name, dump in (("TimetableCore", dump_core), ("TimetableUI", dump_ui)):
    check(platform(dump, "ios") == dt["iOS"] and platform(dump, "watchos") == dt["watchOS"] == "26.0",
          f"{name} platforms iOS {dt['iOS']} / watchOS {dt['watchOS']} match project.yml",
          f"{name} platforms {dump.get('platforms')} vs project.yml {dt}")
for name, dump in (("root", dump_default), ("TimetableCore", dump_core), ("TimetableUI", dump_ui)):
    modes = dump.get("swiftLanguageModes") or dump.get("swiftLanguageVersions")
    check(modes == ["6"], f"{name} package: Swift 6 language mode", f"{name} package language modes {modes}")
check(str(pj["settings"]["base"].get("SWIFT_VERSION")) == "6.0" and
      pj["settings"]["base"].get("SWIFT_STRICT_CONCURRENCY") == "complete",
      "project.yml SWIFT_VERSION 6.0 + strict concurrency complete", "project.yml Swift settings differ")

# --- plists & entitlements are the same files on both paths --------------------------------------------------
for t, plist, ents in (("TabulaApp", xt["infoPath"], xt["entitlementsPath"]),
                       ("TabulaWidgets", ext["infoPath"], ext["entitlementsPath"])):
    check(base(t).get("INFOPLIST_FILE") == plist, f"{t}: same Info.plist on both paths ({plist})", f"{t} plist differs")
    check(xs(base(t).get("CODE_SIGN_ENTITLEMENTS")) == ents,
          f"{t}: same entitlements on both paths with the paid switch off ({ents})",
          f"{t} entitlements differ: project.yml resolves to {xs(base(t).get('CODE_SIGN_ENTITLEMENTS'))!r}, xtool.yml {ents!r}")
canonical_group = re.search(r'canonicalIdentifier = "([^"]+)"',
                            (ROOT / "Packages/TimetableCore/Sources/TimetableCore/AppGroup.swift").read_text()).group(1)
for ents in (xt["entitlementsPath"], ext["entitlementsPath"]):
    groups = plistlib.load(open(ROOT / ents, "rb")).get("com.apple.security.application-groups", [])
    check(groups == [canonical_group], f"{ents}: App Group = TimetableCore.AppGroup.canonicalIdentifier",
          f"{ents}: groups {groups} != {canonical_group}")

# --- macro isolation (CLAUDE.md rule 5) --------------------------------------------------------------------
check("TABULA_MACRO_PROBES" not in defines(dump_default, "TabulaApp"),
      "Package.swift: TabulaApp has no TABULA_MACRO_PROBES by default", "TABULA_MACRO_PROBES defined by default")
check(defines(dump_macro, "TabulaApp") == ["TABULA_MACRO_PROBES"],
      "Package.swift: TABULA_MACRO_PROBES=1 defines TABULA_MACRO_PROBES for TabulaApp",
      f"env var wiring broken: {defines(dump_macro, 'TabulaApp')}")
check(not defines(dump_macro, "TabulaWidgets"), "widget target never gets the macro define",
      "TabulaWidgets must not get TABULA_MACRO_PROBES")
check("TABULA_MACRO_PROBES" in str(base("TabulaApp").get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "")),
      "project.yml: CI builds the macro variant (SWIFT_ACTIVE_COMPILATION_CONDITIONS)",
      "project.yml TabulaApp must define TABULA_MACRO_PROBES")

# Macro policy (PHASE2_PLAN §0.1, 2026-10-09). @Observable/@State/@Entry/@Environment are allowed in real app code
# (App/Sources outside Debug, WidgetExtension, WatchApp): VERIFIED to compile on both paths in Phase 0.
# Still guarded (macro outside `#if TABULA_MACRO_PROBES` = FAIL):
#   - App/Sources/Debug/**: the Phase 0 probes keep their base/macro variants (one unsupported macro must not
#     break the debug screen); new debug UI uses property wrappers (@StateObject/@Published) instead.
#   - Packages/TimetableCore, Packages/TimetableUI: Linux `swift test` and scripts/watch-typecheck.sh (plain swiftc,
#     no SwiftUI macro plugins) must keep compiling them.
# Banned everywhere (SwiftData macros FAILED under xtool, ENVIRONMENT §4): `import SwiftData`, @Model, @Query,
# @Attribute, @Relationship, @Transient, @ModelActor.
# `@State` counts as a macro: it is a SwiftUI macro in the Xcode 27 SDK (OpenAppleMacros README).
MACRO = re.compile(r"^\s*(@(Observable|ObservationTracked|ObservationIgnored|Entry|State|Animatable|AnimatableIgnored|"
                   r"Generable|Guide|SessionPropertyEntry|Model|Query|Attribute|Relationship|Transient|ModelActor|"
                   r"Previewable|AppIntent|AppEntity|AppEnum|AssistantIntent|AssistantEntity|AssistantEnum)\b|#Preview\b)")
SWIFTDATA = re.compile(r"^\s*(import\s+SwiftData\b|@(Model|Query|Attribute|Relationship|Transient|ModelActor)\b)")
GUARDED = ("App/Sources/Debug", "Packages/TimetableUI/Sources", "Packages/TimetableCore/Sources")
macro_fails_before = FAILS
ALL_APP_CODE = ("App/Sources", "WidgetExtension/Sources", "WatchApp/Sources", "Packages/TimetableUI/Sources",
                "Packages/TimetableCore/Sources")
for folder in ALL_APP_CODE:
    for f in sorted((ROOT / folder).rglob("*.swift")):
        rel = f.relative_to(ROOT).as_posix()
        guarded = rel.startswith(GUARDED)
        stack, hits, swiftdata = [], [], []
        for no, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            s = line.strip()
            if SWIFTDATA.match(line):
                swiftdata.append(f"{no}: {s[:60]}")
            if s.startswith("#if"):
                stack.append("TABULA_MACRO_PROBES" in s and "!" not in s)
            elif s.startswith("#elseif") or s.startswith("#else"):
                if stack:
                    stack[-1] = False
            elif s.startswith("#endif"):
                if stack:
                    stack.pop()
            elif guarded and MACRO.match(line) and not any(stack):
                hits.append(f"{no}: {s[:60]}")
        if swiftdata:
            fail(f"{rel}: SwiftData is banned (macros fail under xtool) -> {swiftdata}")
        if hits:
            fail(f"{rel}: macro outside #if TABULA_MACRO_PROBES in a guarded folder -> {hits}")
if FAILS == macro_fails_before:
    ok("macro policy: no SwiftData anywhere; Debug/, TimetableUI, TimetableCore macro-free outside TABULA_MACRO_PROBES")

# Debug gating (PHASE2_PLAN §0.2): every file in App/Sources/Debug compiles only in DEBUG builds.
ungated = []
for f in sorted((ROOT / "App/Sources/Debug").rglob("*.swift")):
    code = [ln.strip() for ln in f.read_text(encoding="utf-8").splitlines() if ln.strip() and not ln.strip().startswith("//")]
    if not code or code[0] != "#if DEBUG" or not code[-1].startswith("#endif"):
        ungated.append(f.relative_to(ROOT).as_posix())
check(not ungated, "App/Sources/Debug/**: every file is wrapped in #if DEBUG … #endif",
      f"debug files not wrapped in #if DEBUG … #endif: {ungated}")

# Launch-route ids (App/Sources/Routing/RouteRegistry.swift): unique and well-formed across all feature providers.
ROUTE_ID = re.compile(r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$")
route_ids = []
for f in sorted((ROOT / "App/Sources").rglob("*Routes.swift")):
    code = "\n".join(ln for ln in f.read_text(encoding="utf-8").splitlines() if not ln.strip().startswith("//"))
    for rid in re.findall(r'AppRoute\(\s*"([^"]*)"', code):
        route_ids.append((rid, f.relative_to(ROOT).as_posix()))
debug_screen = (ROOT / "App/Sources/Debug/DebugScreen.swift").read_text(encoding="utf-8")
area_block = re.search(r"enum DebugArea[^{]*\{(.*?)\n\}", debug_screen, re.S)
for rid in re.findall(r'case \w+ = "([^"]+)"', area_block.group(1) if area_block else ""):
    route_ids.append((rid, "App/Sources/Debug/DebugScreen.swift"))
bad_ids = [r for r in route_ids if not ROUTE_ID.match(r[0])]
seen, dup_ids = {}, []
for rid, where in route_ids:
    if rid in seen:
        dup_ids.append(f"{rid} ({seen[rid]}, {where})")
    seen.setdefault(rid, where)
check(route_ids and not bad_ids and not dup_ids,
      f"route ids: {len(route_ids)} unique, well-formed ({', '.join(sorted(seen))})",
      f"route ids: malformed {bad_ids} / duplicates {dup_ids}")

# Strings: every literal catalog key used in UI code exists in the String Catalog, and no hard-coded user-facing
# literal text (CLAUDE.md "All user-facing strings in String Catalogs"). Debug/ is developer-only (verbatim allowed).
catalog = json.loads((ROOT / "Resources/Localizable.xcstrings").read_text(encoding="utf-8"))["strings"]
incomplete = [k for k, v in catalog.items()
              if not str(v.get("comment", "")).strip() or "en" not in v.get("localizations", {})]
check(not incomplete, f"String Catalog: all {len(catalog)} keys have an English value and a context comment",
      f"String Catalog keys without English value or comment: {incomplete}")
# 12-language completeness (CI finding: with -AppleLanguages (sk) an untranslated key shows as the RAW KEY, iOS does
# not fall back to English per key). Every shipped language must therefore be 100 % complete, every placeholder must
# match English, every plural must carry the CLDR categories of its language. Gaps are a FAIL.
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
import l10n_common as L10N  # noqa: E402

l10n_gaps = L10N.all_problems({"strings": catalog})
check(not l10n_gaps,
      f"String Catalog: {len(catalog)} keys complete in all {len(L10N.TARGETS)} translations ({', '.join(L10N.TARGETS)}; "
      "Serbian counts twice: sr = Cyrillic, sr-Latn = Latin), format specifiers match English, plural categories per CLDR",
      f"String Catalog: {len(l10n_gaps)} translation problem(s) (python3 scripts/l10n-translate-missing.py status|list):"
      + "".join(f"\n       {g}" for g in l10n_gaps[:25]) + ("\n       ..." if len(l10n_gaps) > 25 else ""))
catalog_langs = {lang for v in catalog.values() for lang in v.get("localizations", {})}
check(catalog_langs <= set(L10N.LANGS),
      f"String Catalog uses only the shipped languages ({len(catalog_langs)})",
      f"String Catalog has languages outside the shipped 12 (they would show raw keys): {sorted(catalog_langs - set(L10N.LANGS))}")
# Every language must reach the bundle on BOTH build paths and be declared to iOS.
xt_lprojs = {name: {pathlib.PurePosixPath(r).name for r in res if str(r).startswith(".build-l10n/")}
             for name, res in (("app", xt.get("resources", [])), ("widget", ext.get("resources", [])))}
want_lprojs = {f"{lang}.lproj" for lang in L10N.LANGS}
check(all(v == want_lprojs for v in xt_lprojs.values()),
      f"xtool.yml: app + widget resources list the .lproj of all {len(L10N.LANGS)} language ids (scripts/l10n-compile.py output)",
      "xtool.yml .lproj resources differ from the shipped languages: "
      + str({k: sorted(want_lprojs ^ v) for k, v in xt_lprojs.items() if v != want_lprojs}))
check(pj.get("options", {}).get("developmentLanguage") == "en" and "knownRegions" not in pj.get("options", {}),
      "project.yml: developmentLanguage en (XcodeGen has no knownRegions option; languages come from the catalog + CFBundleLocalizations)",
      "project.yml: developmentLanguage must be en, and options.knownRegions is ignored by XcodeGen (remove it)")
for plist_name in ("Config/App-Info.plist", "Config/Widgets-Info.plist"):
    declared = plistlib.load(open(ROOT / plist_name, "rb")).get("CFBundleLocalizations")
    check(declared is not None and set(declared) == set(L10N.LANGS) and len(declared) == len(L10N.LANGS),
          f"{plist_name}: CFBundleLocalizations lists the shipped languages ({len(L10N.LANGS)} ids)",
          f"{plist_name}: CFBundleLocalizations {declared} != {list(L10N.LANGS)}")
KEY_USE = re.compile(r'(?:(?<![A-Za-z_.])(?:Text|Label|Button|Toggle|Picker|Section|Tab|navigationTitle|LocalizedStringKey|'
                     r'LocalizedStringResource)\(\s*|String\(localized:\s*|(?:forKey|key):\s*)"((?:[^"\\]|\\.)*)"')
VERBATIM_LITERAL = re.compile(r'Text\(\s*verbatim:\s*"')
unknown_keys, verbatim = [], []
for folder in ("App/Sources", "Packages/TimetableUI/Sources", "WidgetExtension/Sources"):
    for f in sorted((ROOT / folder).rglob("*.swift")):
        rel = f.relative_to(ROOT).as_posix()
        if rel.startswith("App/Sources/Debug/"):
            continue
        for no, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            if line.strip().startswith("//"):
                continue
            for key in KEY_USE.findall(line):
                if "\\(" in key:
                    continue   # interpolated keys ("probe.lessons %lld") are checked by Xcode's extraction
                if key not in catalog:
                    unknown_keys.append(f"{rel}:{no} \"{key}\"")
            if rel.startswith("App/Sources/") and VERBATIM_LITERAL.search(line):
                verbatim.append(f"{rel}:{no}")
check(not unknown_keys, "UI code: every literal localisation key exists in Resources/Localizable.xcstrings",
      f"keys missing from the String Catalog (add with scripts/l10n-add.py): {unknown_keys}")
check(not verbatim, "App code: no Text(verbatim: \"literal\") outside App/Sources/Debug (hard-coded text)",
      f"hard-coded verbatim text (use a catalog key): {verbatim}")

# --- privacy manifests + export compliance --------------------------------------------------------------------
VALID_UD_REASONS = {"CA92.1", "1C8F.1", "C56D.1", "AC6B.1"}   # NSPrivacyAccessedAPITypeReasons doc (2026-10-04)
for label, path, xt_res, pj_target in (
        ("app", "Config/Privacy/App/PrivacyInfo.xcprivacy", xt.get("resources", []), "TabulaApp"),
        ("widget", "Config/Privacy/Widgets/PrivacyInfo.xcprivacy", ext.get("resources", []), "TabulaWidgets")):
    p = plistlib.load(open(ROOT / path, "rb"))
    apis = {a["NSPrivacyAccessedAPIType"]: set(a["NSPrivacyAccessedAPITypeReasons"]) for a in p.get("NSPrivacyAccessedAPITypes", [])}
    good = (p.get("NSPrivacyTracking") is False and p.get("NSPrivacyTrackingDomains") == []
            and p.get("NSPrivacyCollectedDataTypes") == []
            and apis.get("NSPrivacyAccessedAPICategoryUserDefaults", set()) >= {"CA92.1", "1C8F.1"}
            and apis["NSPrivacyAccessedAPICategoryUserDefaults"] <= VALID_UD_REASONS)
    check(good, f"{label} privacy manifest: no tracking, no collected data, UserDefaults CA92.1 + 1C8F.1",
          f"{label} privacy manifest content wrong: {p}")
    check(path in xt_res, f"{label} privacy manifest wired into xtool.yml resources", f"{path} missing from xtool.yml")
    check(path in srcs[pj_target], f"{label} privacy manifest wired into project.yml {pj_target}",
          f"{path} missing from project.yml {pj_target}")
info = plistlib.load(open(ROOT / xt["infoPath"], "rb"))
check(info.get("ITSAppUsesNonExemptEncryption") is False, "App-Info.plist ITSAppUsesNonExemptEncryption = false",
      "ITSAppUsesNonExemptEncryption must be false")

# --- identity single source + paid-account placeholders (docs/PAID_ACCOUNT_SWITCHOVER.md) ------------------
REQUIRED_ID = ("TABULA_DEVELOPMENT_TEAM", "TABULA_PAID_ACCOUNT", "TABULA_BUNDLE_ID_PREFIX", "TABULA_BUNDLE_ID",
               "TABULA_APP_GROUP", "TABULA_ICLOUD_CONTAINER", "TABULA_SHARE_DOMAIN",
               "TABULA_APP_ENTITLEMENTS", "TABULA_WIDGET_ENTITLEMENTS")
missing_id = [k for k in REQUIRED_ID if k not in ID_RAW]
check(not missing_id, f"AppIdentity.xcconfig defines {len(REQUIRED_ID)} required values", f"AppIdentity.xcconfig lacks {missing_id}")
check(ID_RAW.get("TABULA_PAID_ACCOUNT") == "0", "paid-account switch is OFF in git (TABULA_PAID_ACCOUNT = 0)",
      f"TABULA_PAID_ACCOUNT must be 0 in the committed xcconfig (CI sets 1), got {ID_RAW.get('TABULA_PAID_ACCOUNT')!r}")
team = ID.get("TABULA_DEVELOPMENT_TEAM", "")
check(team == "" or re.fullmatch(r"[A-Z0-9]{10}", team),
      f"TABULA_DEVELOPMENT_TEAM {'= placeholder (empty)' if not team else 'is a 10-char Team ID'}",
      f"TABULA_DEVELOPMENT_TEAM must be empty or a 10-character Team ID, got {team!r}")
bid = ID.get("TABULA_BUNDLE_ID", "")
for label, ok_cond in (
        ("bundle ID starts with TABULA_BUNDLE_ID_PREFIX", bid.startswith(ID.get("TABULA_BUNDLE_ID_PREFIX", "?") + ".")),
        ("project.yml options.bundleIdPrefix = TABULA_BUNDLE_ID_PREFIX",
         pj["options"].get("bundleIdPrefix") == ID.get("TABULA_BUNDLE_ID_PREFIX")),
        ("xtool.yml bundleID = TABULA_BUNDLE_ID", xt["bundleID"] == bid),
        ("TABULA_APP_GROUP = group.<bundle ID>", ID.get("TABULA_APP_GROUP") == f"group.{bid}"),
        ("TABULA_ICLOUD_CONTAINER = iCloud.<bundle ID>", ID.get("TABULA_ICLOUD_CONTAINER") == f"iCloud.{bid}"),
        ("TimetableCore AppGroup.canonicalIdentifier = TABULA_APP_GROUP", canonical_group == ID.get("TABULA_APP_GROUP")),
        ("Watch-Info.plist WKCompanionAppBundleIdentifier = TABULA_BUNDLE_ID",
         watch_plist.get("WKCompanionAppBundleIdentifier") == bid),
        ("TABULA_SHARE_DOMAIN is a bare host name", re.fullmatch(r"[a-z0-9.-]+\.[a-z]{2,}", ID.get("TABULA_SHARE_DOMAIN", "")))):
    check(ok_cond, f"identity: {label}", f"identity mismatch: {label}")
check(pj.get("configFiles") == {"Debug": "Config/AppIdentity.xcconfig", "Release": "Config/AppIdentity.xcconfig"},
      "project.yml: Config/AppIdentity.xcconfig is the base configuration (Debug + Release)",
      f"project.yml configFiles must point both configs at Config/AppIdentity.xcconfig: {pj.get('configFiles')}")
shadowed = [f"{scope}:{k}" for scope, s in [("project", pj.get("settings", {}).get("base", {}))]
            + [(t, base(t)) for t in tgt] for k in s if k.startswith("TABULA_")]
check(not shadowed, "project.yml never redefines TABULA_* (the xcconfig stays authoritative)",
      f"project.yml redefines {shadowed}: buildSettings override the xcconfig")
check(pj["settings"]["base"].get("DEVELOPMENT_TEAM") == "$(TABULA_DEVELOPMENT_TEAM)",
      "project.yml DEVELOPMENT_TEAM = $(TABULA_DEVELOPMENT_TEAM) (build setting, no generate-time env needed)",
      f"project.yml DEVELOPMENT_TEAM is {pj['settings']['base'].get('DEVELOPMENT_TEAM')!r}")
for t, var in (("TabulaApp", "TABULA_APP_ENTITLEMENTS"), ("TabulaWidgets", "TABULA_WIDGET_ENTITLEMENTS")):
    check(base(t).get("CODE_SIGN_ENTITLEMENTS") == f"$({var})", f"project.yml {t} entitlements come from $({var})",
          f"project.yml {t} CODE_SIGN_ENTITLEMENTS must be $({var})")

PAID_KEYS = {"com.apple.developer.icloud-container-identifiers", "com.apple.developer.icloud-services",
             "com.apple.developer.icloud-container-environment", "com.apple.developer.ubiquity-container-identifiers",
             "com.apple.developer.ubiquity-kvstore-identifier", "aps-environment",
             "com.apple.developer.usernotifications.time-sensitive", "com.apple.developer.kernel.increased-memory-limit",
             "com.apple.developer.associated-domains", "com.apple.developer.in-app-payments"}
PAID_DIR = "Config/Entitlements/PaidAccount/"
# Switch OFF: every build input (xtool.yml entitlements, project.yml as resolved with PAID=0, any plist or
# entitlements file outside the PaidAccount folder) must be free of paid-only keys.
off_inputs = {xt["entitlementsPath"], ext["entitlementsPath"], xs("$(TABULA_APP_ENTITLEMENTS)"),
              xs("$(TABULA_WIDGET_ENTITLEMENTS)")}
for f in sorted(ROOT.joinpath("Config").rglob("*")):
    rel = f.relative_to(ROOT).as_posix()
    if f.suffix in (".entitlements", ".plist", ".xcprivacy") and not rel.startswith(PAID_DIR):
        off_inputs.add(rel)
leaks = {p: sorted(set(plistlib.load(open(ROOT / p, "rb"))) & PAID_KEYS) for p in sorted(off_inputs)}
leaks = {p: k for p, k in leaks.items() if k}
check(not any(p.startswith(PAID_DIR) for p in off_inputs) and not leaks,
      f"switch OFF: no paid-only entitlement in any build input ({len(off_inputs)} files incl. xtool.yml + resolved project.yml)",
      f"switch OFF leaks paid entitlements: {leaks or [p for p in off_inputs if p.startswith(PAID_DIR)]}")
check(not xt["entitlementsPath"].startswith(PAID_DIR) and not ext["entitlementsPath"].startswith(PAID_DIR),
      "xtool.yml never uses the PaidAccount entitlements", "xtool.yml must not reference Config/Entitlements/PaidAccount")
# Switch ON: the selection resolves to the PaidAccount files, and they carry exactly what docs/specs need.
app_paid, widget_paid = ID_PAID["TABULA_APP_ENTITLEMENTS"], ID_PAID["TABULA_WIDGET_ENTITLEMENTS"]
check(app_paid.startswith(PAID_DIR) and widget_paid.startswith(PAID_DIR)
      and (ROOT / app_paid).is_file() and (ROOT / widget_paid).is_file(),
      f"switch ON (TABULA_PAID_ACCOUNT=1) selects {app_paid} + {widget_paid.rsplit('/', 1)[-1]}",
      f"switch ON resolves to {app_paid!r} / {widget_paid!r} (missing or outside {PAID_DIR})")
for path in sorted(ROOT.joinpath(PAID_DIR).glob("*.entitlements")):
    rel = path.relative_to(ROOT).as_posix()
    ents = plistlib.load(open(path, "rb"))
    refs = set(re.findall(r"\$\(([A-Za-z0-9_]+)\)", json.dumps(ents, default=str)))   # values only, not comments
    check(refs <= set(ID_RAW), f"{rel}: every $(VAR) is defined in AppIdentity.xcconfig ({', '.join(sorted(refs))})",
          f"{rel}: undefined references {sorted(refs - set(ID_RAW))}")
    resolved = json.loads(xs(json.dumps(ents, default=str), ID_PAID))
    check(resolved.get("com.apple.security.application-groups") == [ID["TABULA_APP_GROUP"]],
          f"{rel}: App Group resolves to {ID['TABULA_APP_GROUP']}", f"{rel}: App Group wrong: {resolved}")
    if path.name == "Tabula.entitlements":
        expected = {
            "com.apple.developer.icloud-container-identifiers": [ID["TABULA_ICLOUD_CONTAINER"]],
            "com.apple.developer.icloud-services": ["CloudKit"],
            "aps-environment": "development",
            "com.apple.developer.usernotifications.time-sensitive": True,
            "com.apple.developer.kernel.increased-memory-limit": True,
            "com.apple.developer.associated-domains": [f"applinks:{ID['TABULA_SHARE_DOMAIN']}"],
        }
        wrong = {k: resolved.get(k) for k, v in expected.items() if resolved.get(k) != v}
        check(not wrong, f"{rel}: CloudKit, push, Time Sensitive, increased memory, associated domains resolve correctly",
              f"{rel}: unexpected values {wrong}")

# xtool cannot compile String Catalogs: a .xcstrings SwiftPM resource makes `xtool dev build` FAIL
# (VERIFIED 2026-10-06, Probes/XCStringsSwiftPM: "xtool/.xtool-tmp/xcstringstool … is not an executable file").
xc_res = [f"{d['name']}/{t['name']}: {r.get('path')}" for d in (dump_default, dump_core, dump_ui)
          for t in d["targets"] for r in t.get("resources", []) if str(r.get("path", "")).endswith(".xcstrings")]
check(not xc_res, "no Package.swift target declares a .xcstrings resource (would break the xtool build)",
      f".xcstrings declared as SwiftPM resource (breaks xtool): {xc_res}")

# .env.example documents every variable the scripts/CI read (names only, never values).
ENV_NAMES = ("TABULA_PAID_ACCOUNT", "TABULA_DEVELOPMENT_TEAM", "APPLE_TEAM_ID", "ASC_KEY_ID", "ASC_ISSUER_ID",
             "ASC_KEY_P8_BASE64", "TABULA_MACRO_PROBES", "TABULA_WORKDIR", "TABULA_SCRATCH", "TABULA_SWIFTLY_ENV",
             "TABULA_DARWIN_SDK", "TABULA_WATCH_TARGET", "XCODEGEN")
env_example = ROOT / ".env.example"
if env_example.is_file():
    lines = [ln.strip() for ln in env_example.read_text().splitlines() if ln.strip() and not ln.lstrip().startswith("#")]
    declared = {ln.split("=", 1)[0] for ln in lines}
    valued = [ln for ln in lines if "=" in ln and ln.split("=", 1)[1].strip()]
    check(set(ENV_NAMES) <= declared, f".env.example lists all {len(ENV_NAMES)} variables",
          f".env.example misses {sorted(set(ENV_NAMES) - declared)}")
    check(not valued, ".env.example contains names only (no values)", f".env.example has values: {valued}")
else:
    fail(".env.example missing")

# --- workflow ---------------------------------------------------------------------------------------------
wf = yaml.safe_load((ROOT / ".github/workflows/ios.yml").read_text())
ok("ios.yml parses; jobs: " + ", ".join(wf["jobs"]))
check("workflow_dispatch" in str(wf["concurrency"]["cancel-in-progress"]),
      "ios.yml: pushes cannot cancel a manual release run", "ios.yml concurrency would cancel releases")
job_env = wf["jobs"]["release-testflight"].get("env", {})
check(not any("secrets." in str(v) for v in job_env.values()), "ios.yml: release secrets are step-scoped",
      "ios.yml: secrets mapped at job level")
xcg = json.dumps(wf["jobs"]["ios-xcodegen"])
check("arm64_32" in xcg and "lipo -archs" in xcg, "ios.yml asserts arm64_32 in the watch binary", "watch arch check missing")
check("TABULA_PAID_ACCOUNT=1" in xcg and "-showBuildSettings" in xcg,
      "ios.yml resolves the paid switch with xcodebuild -showBuildSettings (both states)", "paid switch CI assertion missing")
rel = json.dumps(wf["jobs"]["release-testflight"])
check("vars.TABULA_PAID_ACCOUNT" in rel and 'TABULA_PAID_ACCOUNT=\\"$TABULA_PAID_ACCOUNT\\"' in rel
      and 'TABULA_DEVELOPMENT_TEAM=\\"$APPLE_TEAM_ID\\"' in rel,
      "release job passes vars.APPLE_TEAM_ID + vars.TABULA_PAID_ACCOUNT to xcodebuild", "release job identity wiring missing")
xtj = wf["jobs"]["ios-xtool-path"]
xt_step = next(s for s in xtj["steps"] if "xtool dev build" in str(s.get("run", "")))
check(xt_step.get("timeout-minutes", 99) <= 10 and "</dev/null" in xt_step["run"] and "alarm" in xt_step["run"],
      "ios.yml xtool step: step timeout <= 10 min, outer perl alarm, stdin </dev/null (hang guard)",
      "ios.yml xtool step lacks the hang guard")
# Run 37449454629 root cause: Contents/MacOS/xtool without XTL_CLI=1 starts the GUI and hangs forever.
xtj_lines = [ln for s in xtj["steps"] for ln in str(s.get("run", "")).splitlines()]
path_lines = [ln for ln in xtj_lines if "GITHUB_PATH" in ln or "ln -s" in ln]
check(any("Contents/Resources/bin" in ln for ln in path_lines)
      and not any("Contents/MacOS" in ln for ln in path_lines)
      and any(s.get("id") == "smoke" for s in xtj["steps"]),
      "ios.yml uses the xtool CLI wrapper (Contents/Resources/bin, XTL_CLI=1) + a 60 s smoke test",
      "ios.yml must put xtool.app/Contents/Resources/bin on PATH (Contents/MacOS/xtool is the GUI app)")
for jname, job in wf["jobs"].items():
    if "xcode" in str(job.get("runs-on", "")) or "macos" in str(job.get("runs-on", "")):
        cap = 30 if jname == "release-testflight" else 15
        check(job.get("timeout-minutes", 999) <= cap, f"ios.yml {jname}: macOS job timeout <= {cap} min",
              f"ios.yml {jname}: timeout-minutes {job.get('timeout-minutes')} > {cap} (billed macOS minutes)")
check("__swift5_entry" in json.dumps(xtj), "ios.yml checks the widget appex keeps __text/__swift5_entry",
      "appex code regression guard missing")

# Screenshot workflow (iOS Simulator) — cost guards.
ui = yaml.safe_load((ROOT / ".github/workflows/ui-screenshots.yml").read_text())
ui_on = ui.get("on", ui.get(True))   # PyYAML parses the bare key `on` as True
uj = ui["jobs"]["ios-simulator-screenshots"]
UI_PATHS = {"App/**", "WidgetExtension/**", "Packages/TimetableUI/Sources/**", "Packages/TimetableUI/Package.swift",
            "Resources/**", "Config/App-Info.plist", ".github/workflows/ui-screenshots.yml"}
check(set(ui_on) == {"push", "workflow_dispatch"} and ui_on["push"].get("branches") == ["main"]
      and set(ui_on["push"].get("paths", [])) == UI_PATHS,
      "ui-screenshots.yml: manual + push to main only for on-screen paths (no PRs, no TimetableCore, no Config/**)",
      f"ui-screenshots.yml triggers differ from the cost decision: {ui_on}")
check(ui["concurrency"].get("cancel-in-progress") is True and uj.get("timeout-minutes", 99) <= 15,
      "ui-screenshots.yml: cancel-in-progress + timeout <= 15 min", "ui-screenshots.yml lacks cost guards")
ui_txt = (ROOT / ".github/workflows/ui-screenshots.yml").read_text()
check("secrets." not in ui_txt and "CODE_SIGNING_ALLOWED=NO" in ui_txt,
      "ui-screenshots.yml uses no secrets and builds unsigned", "ui-screenshots.yml must not need secrets/signing")
for step_kw in ("-TabulaScreen", "appearance dark", "content_size", "simctl io", "list devicetypes",
                "scripts/sim_pick.py", "--platform iOS", "--platform watchOS"):
    check(step_kw in ui_txt, f"ui-screenshots.yml: {step_kw}", f"ui-screenshots.yml missing {step_kw}")
# qa-reviewer 2026-10-06: `simctl list -j runtimes devicetypes` treats "devicetypes" as a search term → no runtimes.
bad_list = [ln.strip() for ln in ui_txt.splitlines()
            if not ln.strip().startswith("#") and re.search(r"simctl list -j\s+[A-Za-z]", ln)]
check(not bad_list, "ui-screenshots.yml: `xcrun simctl list -j` is always called without a section/search term",
      f"ui-screenshots.yml: partial simctl JSON (search-term bug): {bad_list}")

# ios.yml cost gating (orchestrator decision 2026-10-06, private repo).
ios_on = wf.get("on", wf.get(True))
check(ios_on["pull_request"].get("branches") == ["main"], "ios.yml: pull_request limited to branches [main]",
      f"ios.yml pull_request trigger too broad: {ios_on['pull_request']}")
check(ios_on["workflow_dispatch"]["inputs"]["upload"].get("default") is False, "ios.yml: upload input defaults to false",
      "ios.yml: workflow_dispatch input upload must default to false")
chg = wf["jobs"].get("changes", {})
chg_txt = json.dumps(chg)
check(chg.get("runs-on") == "ubuntu-latest" and "scripts/ci_paths.py" in chg_txt and "git diff --name-only" in chg_txt
      and chg.get("outputs", {}).get("app")
      and all(not s.get("uses") or str(s["uses"]).startswith("actions/checkout@") for s in chg.get("steps", [])),
      "ios.yml: Linux `changes` job (git diff + scripts/ci_paths.py, no third-party action) exposes outputs.app",
      "ios.yml: changes job missing or wrong")
for jname in ("ios-xcodegen", "ios-xtool-path"):
    j = wf["jobs"][jname]
    check("changes" in (j.get("needs") if isinstance(j.get("needs"), list) else [j.get("needs")])
          and str(j.get("if", "")).replace(" ", "") == "needs.changes.outputs.app=='true'",
          f"ios.yml {jname}: runs only when needs.changes.outputs.app == 'true'",
          f"ios.yml {jname}: not gated by the changes job")
check(str(wf["jobs"]["release-testflight"].get("if", "")).replace(" ", "")
      == "github.event_name=='workflow_dispatch'&&inputs.upload",
      "ios.yml release-testflight: job-level if (manual + upload only)", "release job gate missing")
check("TABULA_PAID_ACCOUNT must be 0 or 1" in rel, "ios.yml release: TABULA_PAID_ACCOUNT validated to {0,1}",
      "ios.yml release: TABULA_PAID_ACCOUNT not validated")

# All workflows: actions pinned to commit SHAs; nobody hard-codes the paid switch ON.
for wf_file in sorted((ROOT / ".github/workflows").glob("*.yml")):
    txt = wf_file.read_text()
    unpinned = [u for u in re.findall(r"uses:\s*([^\s#]+)", txt) if not re.search(r"@[0-9a-f]{40}$", u)]
    check(not unpinned, f"{wf_file.name}: all actions pinned to commit SHAs", f"{wf_file.name}: unpinned actions {unpinned}")
    # Allowed only inside the read-only `$(setting … TABULA_PAID_ACCOUNT=1)` -showBuildSettings probe.
    check("TABULA_PAID_ACCOUNT=1" not in re.sub(r"\$\(setting [^)]*TABULA_PAID_ACCOUNT=1\)", "", txt),
          f"{wf_file.name}: never hard-codes TABULA_PAID_ACCOUNT=1 for a build",
          f"{wf_file.name}: hard-codes the paid switch ON")

sys.exit(1 if FAILS else 0)
