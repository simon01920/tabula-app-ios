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
check(base("TabulaApp").get("PRODUCT_BUNDLE_IDENTIFIER") == app_id,
      f"app bundle ID identical on both paths ({app_id})", "app bundle ID differs between xtool.yml and project.yml")
check(base("TabulaWidgets").get("PRODUCT_BUNDLE_IDENTIFIER") == widget_id_xtool,
      f"widget bundle ID identical on both paths ({widget_id_xtool})", "widget bundle ID differs")
watch_id = base("TabulaWatch").get("PRODUCT_BUNDLE_IDENTIFIER", "")
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
    check(base(t).get("CODE_SIGN_ENTITLEMENTS") == ents, f"{t}: same entitlements on both paths ({ents})",
          f"{t} entitlements differ")
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

# Macros used anywhere outside `#if TABULA_MACRO_PROBES` in code linked into the apps.
# `@State` counts: it is a SwiftUI macro in the Xcode 27 SDK (OpenAppleMacros README, "SwiftUI: @State ✅").
MACRO = re.compile(r"^\s*(@(Observable|ObservationTracked|ObservationIgnored|Entry|State|Animatable|AnimatableIgnored|"
                   r"Generable|Guide|SessionPropertyEntry|Model|Query|Attribute|Relationship|Transient|ModelActor|"
                   r"Previewable|AppIntent|AppEntity|AppEnum|AssistantIntent|AssistantEntity|AssistantEnum)\b|#Preview\b)")
# Files owned by other agents that still use a macro in the base variant. Reported as WARN, not FAIL,
# until their owner fixes them; remove entries as they get fixed.
KNOWN: dict[str, str] = {}
for folder in ("App/Sources", "WidgetExtension/Sources", "WatchApp/Sources", "Packages/TimetableUI/Sources",
               "Packages/TimetableCore/Sources"):
    for f in sorted((ROOT / folder).rglob("*.swift")):
        rel = f.relative_to(ROOT).as_posix()
        stack, hits = [], []
        for no, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            s = line.strip()
            if s.startswith("#if"):
                stack.append("TABULA_MACRO_PROBES" in s and "!" not in s)
            elif s.startswith("#elseif") or s.startswith("#else"):
                if stack:
                    stack[-1] = False
            elif s.startswith("#endif"):
                if stack:
                    stack.pop()
            elif MACRO.match(line) and not any(stack):
                hits.append(f"{no}: {s[:60]}")
        if hits and rel in KNOWN:
            warn(f"{rel}: {len(hits)} macro use(s) in the base variant: {KNOWN[rel]} (first: {hits[0]})")
        elif hits:
            fail(f"{rel}: macro outside #if TABULA_MACRO_PROBES -> {hits}")
ok("macro scan finished (App, Widget, Watch, TimetableUI, TimetableCore sources)")

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

sys.exit(1 if FAILS else 0)
