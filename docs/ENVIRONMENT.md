# ENVIRONMENT — verified facts, failures and human steps

Owner: env-ci-engineer · Phase 0 spike · Last updated: 2026-10-04 (rev. 2: qa-reviewer fixes)
Status legend: **VERIFIED** (I ran it here, output quoted) · **FAILED** (I *executed* it here and it did not work) ·
**BLOCKED** (needs the Darwin SDK, a device, an Apple account or a CI run; the unblock step is given) ·
**RESEARCH-ONLY** (taken from official docs or source code, not executed; "expected fail" = a source-based prediction, not a run).
All Apple-platform Swift in this repo is **UNCOMPILED** until the Darwin SDK is installed or CI runs.

## 0. Verdict summary

| Area | Verdict | One line |
|---|---|---|
| WSL toolchain (Swift 6.4, Linux tests) | VERIFIED | `swift test` on TimetableCore: 9/9 pass, repo path with a space works |
| xtool 1.20.1 install | VERIFIED | AppImage runs under FUSE, SHA-256 matches the release digest |
| xtool build / install on iPhone | BLOCKED | needs Xcode 27 `.xip` + `xtool setup` (human), then USB passthrough |
| XcodeGen spec | VERIFIED | XcodeGen 2.46.0 built from source on Linux; `xcodegen generate` succeeds; widget and watch embedding present |
| Both build paths use the same sources | VERIFIED (static) | `scripts/validate.sh` (75 OK checks) compares sources, plists, entitlements, bundle IDs, deployment targets, Swift mode, privacy manifests; compilation itself is BLOCKED |
| Macro isolation (CLAUDE.md rule 5) | VERIFIED (static) | default app build has no macros in env-ci files; macro probes compile only with `TABULA_MACRO_PROBES` (`scripts/xtool-dev.sh --macro-probes`; always on in CI). **Exception:** `ImportProbes.swift` (import-ml) uses `@State`, a macro in the Xcode 27 SDK → WARN in validate.sh |
| Macros under xtool | RESEARCH-ONLY (partial) | SwiftUI (`@Entry`, `@State`, `@Animatable`) + FoundationModels macros are shipped by xtool via OpenAppleMacros (tracks exactly Xcode 27.0.0 27A266a); `@Observable` is an OSS-toolchain macro; SwiftData and App Intents macros are NOT provided |
| App Intents under xtool | RESEARCH-ONLY | compiles in principle; Shortcuts metadata needs Apple's macOS-only processor (xtool PR #217 closed unmerged) |
| String Catalogs under xtool | FAILED (Linux host, executed) / iOS cross-build RESEARCH-ONLY / mitigated | SwiftPM copies `.xcstrings` raw on Linux; for iOS, SwiftBuild would call the macOS-only `xcstringstool`; own `scripts/l10n-compile.py` produces `.lproj` tables (VERIFIED on Linux for `.strings`, self-test 6/6) |
| Widgets under xtool | RESEARCH-ONLY | supported as Foundation NSExtension (`PlugIns/`); ExtensionKit not supported |
| watchOS under xtool | RESEARCH-ONLY (expected fail) | xtool's SDK has no watchOS triples and its packer only makes iPhoneOS bundles (source) → watch app is CI-only |
| Watch architecture (Series 7 = arm64_32) | RESEARCH-ONLY | swift-build `watchOSDevice.xcspec`: `ARCHS_STANDARD = (arm64, arm64_32)`, arm64_32 `DeploymentTargetRange = ("0", "27")` → built for watchOS 26.0; CI asserts `lipo -archs` contains arm64_32 |
| TestFlight readiness (static) | VERIFIED (static) | `ITSAppUsesNonExemptEncryption = false`; `PrivacyInfo.xcprivacy` for app and widget on both paths (UserDefaults CA92.1 + 1C8F.1) |
| CI workflow | BLOCKED | written + YAML-validated; needs a GitHub repo to run |
| TestFlight upload | BLOCKED | needs paid Apple Developer Program + App Store Connect API key (Admin role) in GitHub secrets |

## 1. Toolchain (WSL2)

| Item | Status | Evidence | Next step / unblock |
|---|---|---|---|
| WSL distro | VERIFIED | `Ubuntu 26.04 LTS`, kernel `6.18.33.2-microsoft-standard-WSL2`, 16 cores, 15 GB RAM, 950 GB free on `/`; `systemctl is-system-running` → `running` | — |
| Swift | VERIFIED | `swift --version` → `Swift version 6.4 (swift-6.4-RELEASE)` / `Target: x86_64-unknown-linux-gnu` (swiftly, `/root/.local/share/swiftly/bin/swift`) | — |
| Core tests on Linux | VERIFIED | `bash scripts/core-test.sh` → `✔ Test run with 6 tests in 2 suites passed`; cold build+test 10.8 s wall | — |
| Repo path with a space | VERIFIED | all scripts run from `/mnt/c/Users/simon/Documents/Claude Code/school_timetable` | keep quoting `"$REPO_ROOT"` in scripts |
| Build on ext4, not 9P | VERIFIED (practice) | scripts use `--scratch-path ~/.cache/tabula/...`; `xtool-dev.sh` rsyncs the repo to `~/.cache/tabula/work` because xtool writes `./xtool/` in the CWD (xtool `Packer.swift`) | — |
| SwiftBuild is the default build system in 6.4 | VERIFIED | `swift build --build-system native` prints `'--build-system native' has been deprecated` | — |
| Linux validation script | VERIFIED | `bash scripts/validate.sh` → `ALL CHECKS PASSED` (core tests, TimetableUI Linux build, root manifest, plists via plistlib **and** swift-corelibs Foundation, YAML schemas, path sync, l10n compile, PNG, `xcodegen generate`). Log: `/root/phase0_validate.log` | run before every commit |
| Extra package installed | VERIFIED | `apt-get install poppler-utils` (to read the Xcode SDK agreement PDF) | — |

## 2. xtool

| Item | Status | Evidence | Next step / unblock |
|---|---|---|---|
| Version pin | VERIFIED | GitHub API: release `1.20.1` (2026-09-21T06:05:38Z); asset `xtool-x86_64.AppImage` digest `sha256:040c58d5c708f613b9b74cbdb24e25e8d72c47ff86941f19463626d811159831` | bump deliberately; re-check release notes |
| Install + checksum | VERIFIED | `sha256 actual=040c58d5…159831` = expected; installed to `/usr/local/bin/xtool`; log `/root/phase0_xtool_install.log` | — |
| FUSE / AppImage | VERIFIED | AppImage executes directly (`/dev/fuse`, `fusermount3` present); `--appimage-extract` not needed | if FUSE ever breaks: `xtool --appimage-extract` and run `squashfs-root/AppRun` |
| `xtool --version` / `--help` | VERIFIED | `xtool 1.20.1`; subcommands `setup auth sdk new dev ds devices install uninstall launch`; `dev build [--sign] [--ipa] [--triple]` | — |
| Darwin SDK | BLOCKED | `xtool sdk status` → `Not installed` | Human step H2–H3 |
| Auth | BLOCKED | `xtool auth status` → `Logged out` | Human step H3 (interactive, never in chat) |
| Device discovery | BLOCKED | `xtool devices --no-wait` → (empty); `usbmuxd` inactive, no `/var/run/usbmuxd` | Human step H4 |
| Wrapper gate | VERIFIED | `bash scripts/xtool-dev.sh build` → `error: Darwin SDK not installed …` exit 2 | — |
| Licence | VERIFIED | `LICENSE.md`: MIT (Kabir Oberai). Build tool only, not shipped in the app | — |
| `xtool.yml` schema | VERIFIED (source) | 1.20.1 `Sources/PackLib/PackSchema.swift`: `version, orgID, bundleID, product, infoPath, entitlementsPath, iconPath, resources, extensions[{product, bundleID, infoPath, resources, entitlementsPath}], skipLSP` | `validate.sh` rejects unknown keys |
| Products must be automatic libraries of the root package | VERIFIED (source + manifest) | `Planner.selectLibrary` filters `type == .autoLibrary`; `validate.sh`: `OK product TabulaApp: automatic library, path App/Sources` | — |
| Info.plist handling | VERIFIED (source) | xtool builds defaults (`CFBundleIdentifier`, `CFBundleVersion "1"`, `CFBundleShortVersionString "1.0.0"`, `UIDeviceFamily [1,2]`, `UILaunchScreen`) and **merges `infoPath` over them verbatim** → shared plists must not contain `$(VAR)` | enforced by `validate.sh` |
| macOS build of xtool exists | VERIFIED | release asset `xtool.app.zip` sha256 `39123efc…33ca2`; binary at `xtool.app/Contents/MacOS/xtool` | used by CI job `ios-xtool-path` |
| `xtool dev build` without login | RESEARCH-ONLY (source) | `DevBuildCommand`: auth token only required with `--sign`; `EnsureSDKOperation` is a no-op on macOS | first CI run proves it |
| xtool SwiftBuild toolset | VERIFIED | downloaded `darwin-tools-linux-llvm v1.1.0 toolset-x86_64.tar.gz` (sha256 `a5166f2d…74188`): only `bin/dsymutil`, `bin/ld64.lld`, `bin/libtool` — no `xcstringstool`, `actool`, `appintentsmetadataprocessor` | explains the catalog/asset/intents gaps |
| SDK size | RESEARCH-ONLY | 1.20.0 notes: new SDK layout bundles all of `Xcode.app/Contents/Developer`, ~7 GB (was ~3 GB); `xtool sdk install --slim` opts out | ample disk (950 GB free) |
| OpenAppleMacros (macro implementations xtool ships) | RESEARCH-ONLY | repo `xtool-org/OpenAppleMacros` v1.3.0 (MIT) README: "Currently tracking: **Xcode 27.0.0 (27A266a)**"; supported: SwiftUI `@Animatable @AnimatableIgnored @Entry @State`, FoundationModels `@Generable @Guide @SessionPropertyEntry`, Previews (expand to empty); NOT supported: SwiftData (`@Model @Query` …), App Intents macros (`@AppIntent @AppEntity` …), TipKit, StateReporting | install the SDK from **Xcode 27.0 (27A266a)** to match (H2) |
| Open upstream items | RESEARCH-ONLY | PR **#217** pure-Swift AppIntents metadata generator: **closed, not merged** (2026-06-02). PR **#219** `.xcassets` compiler: **open** (updated 2026-06-18). PR **#284** one App Group on free teams: **open** (2026-09-28). Issue **#149** SwiftData macros: **open**. Issue **#138** ExtensionKit: **open**. Nothing found on watchOS or `.xcstrings`. Source: `https://api.github.com/repos/xtool-org/xtool/issues/<n>` | re-check at each phase gate |

### 2.1 Bundle-ID prefix (important)

VERIFIED in 1.20.1 source (`Sources/XKit/Utilities/ProvisioningIdentifiers.swift`, `DeveloperServicesAddAppOperation.swift`, `EntitlementWithTeamOrBundleID.swift`):

| Identifier | Canonical (CI/App Store) | xtool-signed on device | Consequence |
|---|---|---|---|
| App bundle ID | `sk.simondev.tabula` | `XTL-<ID>.sk.simondev.tabula` (`<ID>` = first segment of the signing identity ID, uppercased) | local and TestFlight builds are **different apps** with separate data |
| Widget bundle ID | `sk.simondev.tabula.TabulaWidgets` | `XTL-<ID>.sk.simondev.tabula.TabulaWidgets` | — |
| App Group | `group.sk.simondev.tabula` | `group.XTL-<ID>.sk.simondev.tabula` | **never hard-code the group**: use `TimetableCore.AppGroup.identifier(forBundleIdentifier:)` (Linux-tested) |
| Keychain access groups | as declared | replaced by exactly `["<TEAM>.<new bundle ID>"]` | shared keychain between app/extensions does not work on the xtool path |
| iCloud container | `iCloud.sk.simondev.tabula` | not handled by xtool (no iCloud capability registration) | CloudKit testing = CI/TestFlight only |
| Free team | — | App Groups are filtered out (`DeveloperServicesCapability(.appGroups, isFree: false)` + FIXME) | widget↔app sharing fails on free teams until PR #284 ships |

xtool auto-registers only these capabilities from entitlements: Data Protection, App Groups (paid), Associated Domains, HealthKit, HomeKit, Inter-App Audio, Multipath, Network Extensions, Personal VPN, Push, SiriKit, Wireless Accessory, Wi-Fi Aware. **Time Sensitive, iCloud/CloudKit, increased-memory-limit, In-App Purchase capability are not handled** → keep `Config/*.entitlements` (shared with xtool) to App Groups only; add the others in a CI-only entitlements file when those phases start.

## 3. Build paths

| Item | Status | Evidence | Next step / unblock |
|---|---|---|---|
| (a) SwiftPM + `xtool.yml` | VERIFIED (manifest) / BLOCKED (compile) | `swift package describe` passes on Linux; compile needs SDK | H2–H3, then `bash scripts/xtool-dev.sh build` |
| (b) XcodeGen `project.yml` | VERIFIED (generate) / BLOCKED (xcodebuild) | XcodeGen 2.46.0 from source with Swift 6.4: `Build complete! (103.33 secs)`, `Version: 2.46.0`; `xcodegen generate` → `Created project at …/Tabula.xcodeproj` exit 0; pbxproj contains `Embed Watch Content` with `dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"`, `TabulaWidgets.appex in Embed Foundation Extensions`, two `XCLocalSwiftPackageReference`s, shared scheme `TabulaApp.xcscheme`; Config plists left untouched | first CI run |
| XcodeGen licence/maintenance | VERIFIED | MIT; latest release 2.46.0 (2026-07-16), pushed 2026-09-13, not archived; `xcodegen.zip` sha256 `4d9e34b6…196806` | — |
| `${TABULA_DEVELOPMENT_TEAM}` | VERIFIED | unset → XcodeGen keeps the literal `"${TABULA_DEVELOPMENT_TEAM}"`; set to empty → `DEVELOPMENT_TEAM = ""`; set → value | always export it (empty for unsigned builds) — done in CI |
| Same sources | VERIFIED (static) | `validate.sh`: `OK project.yml targets/sources/plists in sync with Package.swift + xtool.yml` | — |

Source mapping (identical on both paths): `App/Sources` (module `TabulaApp`), `WidgetExtension/Sources` (module `TabulaWidgets`), `Packages/TimetableCore`, `Packages/TimetableUI`, `Config/App-Info.plist`, `Config/Widgets-Info.plist`, `Config/Tabula.entitlements`, `Config/TabulaWidgets.entitlements`, `Resources/Localizable.xcstrings`. App bundle is `TabulaApp.app` on both paths; display name "Tabula" comes from the plist.

Differences by design: watch app (`WatchApp/Sources`, CI only) · icon: xtool uses `Resources/AppIcon.png` (`CFBundleIconFile`), Xcode uses `Resources/Assets.xcassets` (xtool cannot compile asset catalogs, PR #219) · strings: Xcode compiles the catalog, xtool path uses `.build-l10n/` from `scripts/l10n-compile.py` · versions: xtool `1.0.0 (1)`, Xcode `MARKETING_VERSION 0.1.0` / `CURRENT_PROJECT_VERSION` (CI overrides with the run number) · `SWIFT_PACKAGE` is defined only on the xtool path (the debug screen shows which path built the app).

## 4. Macros

| Macro | Status | Evidence | Next step / unblock |
|---|---|---|---|
| `@Observable` | RESEARCH-ONLY → expect works | ObservationMacros ship in the open-source toolchain; xtool PR #101 test notes: "OSS toolchain macros continue to work (tested `@Observable`, `#bundle`)" | device row "@Observable ticks" (BLOCKED: H2–H4) |
| SwiftUI `@Entry`, `@State`, `#Preview` | RESEARCH-ONLY → expect works | 1.20.0 notes: "SwiftUI macros (#101)"; `SDKBuilder.oamLibraries = ["FoundationModelsMacros", "PreviewsMacros", "SwiftUIMacros"]`, OpenAppleMacros 1.3.0 | device row "@Entry environment value" |
| FoundationModels `@Generable`, `@Guide` | RESEARCH-ONLY → expect works | 1.20.1 notes: "Adds support for FoundationModels macros (#270)" | device row "@Generable schema" |
| SwiftData `@Model`, `@Query` | RESEARCH-ONLY → expect FAIL | `SwiftDataMacros` not in `oamLibraries`; issue #149 error `external macro implementation type 'SwiftDataMacros.PersistentModelMacro' could not be found`; maintainer suggests GRDB | `bash scripts/probe-build.sh MacroProbeSwiftData` after H3 |
| App Intents | RESEARCH-ONLY | `AppIntent`/`AppShortcutsProvider` are protocols (no macro needed). Shortcuts/Spotlight listing requires `Metadata.appintents` from `appintentsmetadataprocessor` (SwiftBuild `AppIntentsMetadata.xcspec`, macOS binary, not in xtool's toolset); PR #217 closed unmerged | device: is "Run Tabula probe" listed in Shortcuts? (expect no on xtool, yes on TestFlight) |

| `@State` | RESEARCH-ONLY | In the Xcode 27 SDK `@State` is a SwiftUI **macro** (OAM README; xtool PR #101: "State is a PW in the former [6.3], macro in the latter [6.4]"). `@StateObject`, `@Published`, `@Environment` are not macros | base variant uses `@StateObject`/`@Published`; `ImportProbes.swift` still uses `@State` (WARN) |

**Macro isolation (qa-reviewer item 3).** The default (BASE) build contains no Swift macros in env-ci files, so one unsupported macro cannot block every device check. All macro probes (`@Observable`, `@Entry`, `@State`, `@Generable`/`@Guide`) sit behind `#if TABULA_MACRO_PROBES` with non-macro fallbacks (ObservableObject/@Published, plain `EnvironmentKey`, Generable row "not built").
- xtool path: `Package.swift` reads `Context.environment["TABULA_MACRO_PROBES"]`; `scripts/xtool-dev.sh --macro-probes` sets it and builds in a separate work dir (`…/work-macro`).
- VERIFIED on Linux: `swift package dump-package` → TabulaApp settings `[]` without the variable, `[{"kind": {"define": {"_0": "TABULA_MACRO_PROBES"}}, "tool": "swift"}]` with `TABULA_MACRO_PROBES=1`, and `[]` again after unsetting (SwiftPM's manifest cache honours the environment; same scratch path).
- XcodeGen/CI path: `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) TABULA_MACRO_PROBES"` on TabulaApp (Xcode ships Apple's own macro plugins) — VERIFIED in the generated pbxproj.
- `validate.sh` scans App/Widget/Watch/TimetableUI/TimetableCore sources for macro attributes outside the guard (FAIL). Negative test with an injected unguarded `@Observable` and an `@Entry` in the `#else` branch → `FAIL … ['40: @Observable', '45: @Entry var leak2 = 1']`. Known exception reported as WARN: `ImportProbes.swift` (5× `@State`, owner import-ml).

Decision input for ARCHITECTURE: keep the **versioned Codable store** default; SwiftData is not viable on the local path.

## 5. Extensions & watchOS

| Item | Status | Evidence | Next step / unblock |
|---|---|---|---|
| Widget extension (WidgetKit) | RESEARCH-ONLY | xtool `Appex.md`: Foundation extensions via `extensions:`; packer puts them in `PlugIns/<product>.appex`, links `-e _NSExtensionMain` | H2–H4, add widget, check checklist items 4 |
| ExtensionKit extensions | RESEARCH-ONLY → not supported | issue #138 open (`Extensions/` folder not supported) | avoid ExtensionKit-only extension points locally |
| Live Activity (`AlarmLiveActivity`) | RESEARCH-ONLY | lives in the same WidgetKit extension (registered in `TabulaWidgetBundle`) | notifications agent's checklist |
| watchOS app under xtool | RESEARCH-ONLY (expected fail, source) | SDK definition has only `arm64-apple-ios`, `*-apple-ios-simulator`, `*-apple-macosx` triples; `Packer` writes `CFBundleSupportedPlatforms = [iPhoneOS]` and only `iphoneos/iphonesimulator` product dirs | watch = CI-only (XcodeGen) |
| Watch architecture | RESEARCH-ONLY | Apple Watch Series 7 = S7 = arm64_32. swift-build (main `b0458a1`) `Sources/SWBApplePlatform/Specs/watchOSDevice.xcspec`: `ARCHS_STANDARD = ( arm64, arm64_32 )`; arm64_32 has `DeploymentTargetRange = ( "0", "27" )` (inclusive per `VersionRange.contains`), so it is built for `WATCHOS_DEPLOYMENT_TARGET` 26.0. `project.yml` sets no `ARCHS` (validate.sh checks the pbxproj) | CI: `xcodebuild … ONLY_ACTIVE_ARCH=NO`, then `lipo -archs …/TabulaWatch` must contain arm64_32. Never raise the watch deployment target past 26.x while Series 7 is supported |
| watchOS via CI | BLOCKED | `project.yml` target `TabulaWatch` (watchOS 26.0) embedded in the iOS app; CI job verifies `TabulaApp.app/Watch/TabulaWatch.app` | first CI run |
| watchOS on-device install | BLOCKED | without a Mac, the only route is TestFlight (paid account) → iPhone → Watch app | iteration cost below |
| Experiment: local watchOS type-check | BLOCKED (idea) | the full SDK bundles `WatchOS.platform`; try `swift build --build-system swiftbuild --triple arm64_32-apple-watchos26.0 --toolset "$SDK/toolset-swb.json" --package-path Packages/TimetableUI` with `XCODE_EXTRA_PLATFORM_FOLDERS="$SDK/Developer/Platforms"` | try after H3; would catch watchOS compile errors in shared packages without CI |

Iteration-speed cost of the CI-only watch route (estimate, not measured): CI build ~10–20 min + TestFlight processing ~5–30 min + install ≈ **30–60 min per watch change**, vs. a local xtool loop for iOS (unmeasured, expected a few minutes). Mitigation: keep watch UI thin, logic in TimetableCore (Linux-tested), CI watchOS build on every push.

## 6. String Catalogs (`.xcstrings`)

| Item | Status | Evidence | Next step / unblock |
|---|---|---|---|
| SwiftPM native, Linux host | FAILED | probe package: `[1/7] Copying Localizable.xcstrings`; bundle contains raw `Localizable.xcstrings`; lookup → `<MISSING>` | — |
| SwiftBuild, Linux host | FAILED | `warning: no rule to process file '…/Localizable.xcstrings' of type 'text.json.xcstrings' for architecture 'x86_64'`; copied raw; lookup → `<MISSING>` | — |
| SwiftBuild, iOS cross-build via xtool | BLOCKED | swift-build `Specs/XCStrings.xcspec`: `CommandLine = "xcstringstool compile [options] …"` — macOS tool, absent from xtool's toolset → expect build error or raw copy | `bash scripts/probe-build.sh XCStringsSwiftPM` after H3 |
| Mitigation `scripts/l10n-compile.py` | VERIFIED (Linux) | converts catalog → `en.lproj`/`sk.lproj` `Localizable.strings` (+ `.stringsdict` for plurals); Linux Foundation reads them: `en hello: Hello from the String Catalog`, `sk hello: Ahoj zo String Catalogu` | wired into `xtool-dev.sh` + `xtool.yml resources` |
| Plural `.stringsdict` at runtime | BLOCKED | structure matches Apple's documented format (`NSStringLocalizedFormatKey = %#@arg@`, `NSStringPluralRuleType`, `NSStringFormatValueTypeKey = lld`); swift-corelibs Foundation **crashes** on stringsdict lookup on Linux (Signal 11 in `Bundle.localizedString` → `NSString.getCharacters`) so it cannot be checked here | device checklist item 5 (sk: "1 hodina · 3 hodiny · 5 hodín") |
| Limits of the converter | VERIFIED | rejects `substitutions` and `device` variations (non-zero exit); `%%` is not treated as a format specifier; empty or `state: new` units are skipped and fall back to the source language (as do missing translations). `python3 scripts/l10n-compile.py --self-test` → 6/6 OK | revisit in Phase 2 if needed |
| Slovak plural probe on an English device | BLOCKED | the probe loads `sk.lproj` via `Bundle(path:)`, reads the format with `localizedString(forKey:value:table:)` and applies `String(format:locale:)` with `Locale("sk")`. Remaining uncertainty: whether Foundation picks the plural rule from the `locale:` argument or from the process language | device checklist A5 |

## 7. Capabilities (Apple)

Free vs paid, parsed from the official table https://developer.apple.com/help/account/reference/supported-capabilities-ios (fetched 2026-10-04; columns ADP / ADEP / Apple Developer=free):

| Capability | Free Apple Account | Paid ADP | Needed for | xtool handles it? |
|---|---|---|---|---|
| App groups | ✓ | ✓ | widget/watch snapshot sharing | paid only (free filtered; PR #284) |
| iCloud: CloudKit | — | ✓ | sync (Phase 6) | no → CI/TestFlight only |
| In-App Purchase | — | ✓ | Pro (Phase 10) | n/a (no entitlement; StoreKit sandbox via TestFlight) |
| Push notifications | — | ✓ | not planned | yes (paid) |
| Time Sensitive Notifications | — | ✓ | reminders tier 2 | no → CI-only entitlement |
| Increased Debugging Memory Limit | — | ✓ | — | no |
| Increased Memory Limit (`com.apple.developer.kernel.increased-memory-limit`, iOS 15+) | not in the table | assume paid | local LLM (AI_IMPORT) | no → CI/TestFlight only |
| Extended Virtual Addressing | — | ✓ | maybe LLM | no |
| Siri | — | ✓ | only for SiriKit intents; App Intents/Shortcuts need no capability | yes (paid) |
| Associated domains | — | ✓ | universal links (Phase 7) | yes (paid) |
| Sign in with Apple | — | ✓ | not planned | no |
| Background modes / Data protection / Keychain sharing | ✓ | ✓ | — | data protection yes |
| AlarmKit | no capability row | — | loud alarms | RESEARCH-ONLY: Apple's sample says "If the NSAlarmKitUsageDescription key is missing or its value is an empty string, apps can't schedule alarms"; no entitlement documented (`developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit`) |
| Critical Alerts | entitlement on request | — | excluded by spec | — |

Status of every row: RESEARCH-ONLY until tested on device (needs paid account: RISKS #3).

TestFlight readiness (static, VERIFIED by validate.sh):
- `Config/App-Info.plist`: `ITSAppUsesNonExemptEncryption = false` (doc: `bundleresources/information-property-list/itsappusesnonexemptencryption`).
- Privacy manifests `Config/Privacy/App/PrivacyInfo.xcprivacy` and `Config/Privacy/Widgets/PrivacyInfo.xcprivacy`: `NSPrivacyTracking = false`, no tracking domains, no collected data types, `NSPrivacyAccessedAPICategoryUserDefaults` with `CA92.1` ("read and write information that is only accessible to the app itself") and `1C8F.1` ("…only accessible to the apps, app extensions, and App Clips that are members of the same App Group"), both from `bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons` (fetched 2026-10-04). Wired into xtool.yml `resources` (app + extension) and project.yml Resources phases (app + widget). Watch app: none yet (no required-reason API used).
- Re-check required-reason APIs whenever code is added (for example disk-space or file-timestamp APIs in the import/LLM work need their own categories).

## 8. CI (`.github/workflows/ios.yml`)

| Item | Status | Evidence | Next step / unblock |
|---|---|---|---|
| Workflow file | VERIFIED (syntax) | PyYAML parse: jobs `core-linux, ios-xcodegen, ios-xtool-path, release-testflight` | push to GitHub (H6) |
| (a) Linux job | BLOCKED | `container: swift:6.4.0-noble` (tag exists on Docker Hub), `swift test --package-path Packages/TimetableCore` (same command as WSL), then installs python3/PyYAML/rsync and runs `bash scripts/validate.sh` (XcodeGen step skipped there) | first run |
| (b) XcodeGen + unsigned xcodebuild | BLOCKED | `xcodegen generate` + `xcodebuild build -scheme TabulaApp -destination 'generic/platform=iOS' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO` (macro variant); hard-fails unless the appex, the watch binary, `en`/`sk` `.lproj/Localizable.strings(+dict)` in app and widget, both `PrivacyInfo.xcprivacy` exist, `ITSAppUsesNonExemptEncryption` is false and `lipo -archs` of the watch binary contains `arm64_32` | first run |
| (c) xtool path on macOS | BLOCKED | pinned `xtool.app.zip` 1.20.1 (SHA-256 checked) → `xtool dev build` (unsigned, no login, base variant) → hard-fails unless the appex, `en`/`sk` lproj tables (app + widget) and both privacy manifests exist | first run. Fallback if xtool-on-CI is flaky: `swift build --swift-sdk arm64-apple-ios --package-path .` (compiles the same targets, no packaging) |
| (d) TestFlight release | BLOCKED | `workflow_dispatch`; `concurrency.cancel-in-progress` is false for manual runs, so a push cannot cancel an upload; secrets are mapped only into the steps that use them (the config check sees booleans only); skips with a notice if `ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_P8_BASE64 / vars.APPLE_TEAM_ID` are missing; archive with `-allowProvisioningUpdates -authenticationKeyPath/ID/IssuerID`, export (`method app-store-connect`, `destination export`), upload `xcrun altool --upload-app … --apiKey --apiIssuer` | H1, H7, H8 |
| Runner with Xcode 27 | RESEARCH-ONLY | actions/runner-images README: label **`xcode-27`** (preview, issue #14404); image `macOS 27.0 (26A428)`, version `20260928.0222.1`; Xcode `27.0 (default) 27A266a` at `/Applications/Xcode_27.app`, 27.1, 27.2 beta; watchOS 27.0 SDK installed; Xcbeautify 3.2.1. `macos-26` defaults to Xcode 26.6 | switch to the GA label when announced |
| Upload method | RESEARCH-ONLY | Apple "Upload builds" (developer.apple.com/help/app-store-connect/manage-builds/upload-builds): Xcode, `xcrun altool --upload-app`, Transporter, App Store Connect API; iOS apps must be built with Xcode 26+. Chose export + altool because forum reports show `destination=upload` failing with API keys in some setups (developer.apple.com/forums/thread/742458) | — |
| API key role | RESEARCH-ONLY | cloud-managed distribution signing via `xcodebuild` needs an **Admin** key (developer.apple.com/forums/thread/698117); xtool docs ask for a Team Key with **App Manager** role | H7: two keys recommended (least privilege) |
| Cost | RESEARCH-ONLY | docs.github.com billing: standard runners **free for public repos**; private repos: GitHub Free 2,000 min/month, Pro 3,000; rates macOS `$0.062/min` vs Linux `$0.006/min` (~10×). Current docs bill in dollars and no longer state a minute multiplier — check the billing dashboard | decision D2 |

Supply-chain note: XcodeGen and xtool downloads are pinned by SHA-256; GitHub actions are pinned by tag (`@v4`) — pin them to commit SHAs as a later hardening step.

Estimate (not measured): two macOS jobs ≈ 20–40 min per push ≈ $1.2–$2.5 per push on a private repo once the free allowance is used. Mitigations in the workflow: `paths-ignore` for docs, `concurrency` cancel-in-progress, release job manual only.

## 9. Device connection (WSL ↔ iPhone)

| Item | Status | Evidence | Next step / unblock |
|---|---|---|---|
| libimobiledevice / usbmuxd in WSL | VERIFIED | usbmuxd 1.1.1, libimobiledevice-utils 1.4.0 installed; `usbmuxd.service` static (udev rule `39-usbmuxd.rules` starts it on attach) | — |
| usbipd-win | RESEARCH-ONLY | Microsoft Learn "Connect USB devices" (learn.microsoft.com/en-us/windows/wsl/connect-usb): `winget install --interactive --exact dorssel.usbipd-win`; admin `usbipd list`, `usbipd bind --busid <id>`; `usbipd attach --wsl --busid <id>`; kernel ≥ 5.10.60.1 (ours 6.18). Latest usbipd-win v5.3.0, GPL-3.0 (host tool, not distributed with the app) | H4 |
| iTunes relay fallback | RESEARCH-ONLY | xtool docs link issue #19 comment 2898986718 (rena2019): firewall rule for `vEthernet (WSL (Hyper-V firewall))`, `netsh interface portproxy set v4tov4 listenport=27015 connectaddress=127.0.0.1 connectport=27015 listenaddress=<WSL host IP>`, then in WSL `export USBMUXD_SOCKET_ADDRESS="$(ip route list default \| awk '{print $3}'):27015"` | use if `AFCClient.Error.muxError` or install hangs at `[Connecting]` |

## 10. Licences & legal awareness

- xtool: MIT. XcodeGen: MIT. usbipd-win: GPL-3.0 (Windows host tool only). No Swift package dependencies were added.
- **Xcode and Apple SDKs Agreement** (EA2002, dated 06/08/2026, https://www.apple.com/legal/sla/docs/xcode.pdf), §2.7: you agree not to "install, use or run the Apple Software or Apple Services on any non-Apple-branded computer". The xtool workflow installs SDK content extracted from Xcode on a Windows/WSL PC. **Human-awareness risk, not legal advice** — the human decides whether to accept it; the CI path (macOS runners = Apple hardware) is unaffected.

## 11. Failed assumptions / surprises (log)

1. "xtool compiles String Catalogs" — false on Linux host (raw copy); iOS cross-build expected to fail or copy raw → own converter.
2. "One Info.plist with `$(PRODUCT_BUNDLE_IDENTIFIER)` works for both paths" — false: xtool merges plist values verbatim. Fixed: placeholder-free shared plists + `GENERATE_INFOPLIST_FILE=YES` on the Xcode side.
3. "Hard-coded App Group works everywhere" — false: xtool rewrites it to `group.XTL-<ID>.…`. Fixed: runtime resolver in TimetableCore.
4. "XcodeGen drops unset `${VAR}`" — false: it keeps the literal; CI sets the variable explicitly.
5. "Linux Foundation can test plural `.stringsdict`" — false: corelibs crashes; plural correctness is a device check.
6. "WebFetch summaries of the capability table are reliable" — false: the summary claimed everything is free; parsing the HTML shows most capabilities are paid-only (table above is from the parsed HTML).
7. "watchOS can be built locally with xtool" — false (no watchOS triples/packaging).
8. "App Store Connect key with App Manager role is enough for CI distribution signing" — likely false (Admin needed for cloud signing per Apple forums).
9. "`@State` is a property wrapper" — false in the Xcode 27 SDK: it is a SwiftUI macro (OAM README). The base variant now avoids it in env-ci files.
10. Known gap, not a failure: in Phase 0 the debug screen *is* the app, so it ships in Release archives/TestFlight builds. **Phase 2 task:** gate `DebugScreen` behind `#if DEBUG` or a hidden toggle.

## 12. API checks (Apple docs JSON, fetched 2026-10-04)

Base URL `https://developer.apple.com/tutorials/data/documentation/` + path + `.json`. Introduced versions as reported:
`swiftui/entry()` (macro; iOS 13 back-deployed) · `observation/observable()` iOS 17 · `swiftui/labeledcontent` · `swiftui/text/init(verbatim:)` · `swiftui/text/init(timerinterval:pausetime:countsdown:showshours:)` iOS 16 · `swiftui/view/containerbackground(_:for:)` iOS 17 · `swiftui/view/onappear(perform:)` · `swiftui/view/environment(_:_:)` · `swiftui/view/accessibilityelement(children:)` · `swiftui/view/accessibilitylabel(_:)-5f0zj` · `swiftui/view/accessibilityhidden(_:)` · `swiftui/view/foregroundstyle(_:)` · `swiftui/font/monospaced()` · `swiftui/view/textselection(_:)` (**not on watchOS → not used**) · `swiftui/image/init(systemname:)` · `swiftui/state` · `swiftui/environment` · `swiftui/environmentvalues` · `swiftui/list` · `swiftui/section` · `swiftui/button` · `swiftui/foreach` · `swiftui/navigationstack` · `swiftui/view/navigationtitle(_:)-5di1u` · `swiftui/app` · `swiftui/scene` · `swiftui/windowgroup` · `swiftui/widgetbundle` · `swiftui/widget` · `swiftui/widgetconfiguration/supportedfamilies(_:)` · `swiftui/widgetconfiguration/configurationdisplayname(_:)` · `swiftui/widgetconfiguration/description(_:)` · `swiftui/localizedstringkey` · `widgetkit/staticconfiguration` · `widgetkit/timelineprovider` (+ `placeholder(in:)`, `getsnapshot(in:completion:)`, `gettimeline(in:completion:)` with `@Sendable` completions) · `widgetkit/timeline/init(entries:policy:)` · `widgetkit/timelineentry` · `widgetkit/widgetcenter/reloadalltimelines()` · `widgetkit/widgetfamily` · `foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)` · `foundation/userdefaults/init(suitename:)` · `foundation/bundle/bundleidentifier` · `foundation/bundle/localizations` · `foundation/bundle/preferredlocalizations` · `foundation/locale/current` · `foundation/processinfo/operatingsystemversionstring` · `foundation/date/iso8601format(_:)` · `foundation/date/now` · `foundation/url/appending(path:directoryhint:)` · `foundation/localizedstringresource` · `swift/string/init(localized:table:bundle:locale:comment:)` iOS 15 · `uikit/uidevice/systemname` · `uikit/uidevice/systemversion` · `uikit/uidevice/model` · `appintents/appintent` (+ `title`, `description` = `IntentDescription?`, `perform()`; `openappwhenrun` **deprecated in 26 → not used**) · `appintents/intentdescription` · `appintents/intentdialog` · `appintents/intentresult/result(dialog:)` · `appintents/providesdialog` · `appintents/appshortcutsprovider` (+ `appshortcuts`) · `appintents/appshortcut/init(intent:phrases:shorttitle:systemimagename:)-8yntq` iOS 17 (the `-2hk1x` overload is deprecated) · `appintents/appshortcutphrase` · `foundationmodels/generable(description:)` iOS 26 / watchOS 27 · `foundationmodels/guide(description:)` · `foundationmodels/generable/generationschema` · `foundationmodels/systemlanguagemodel` (no watchOS) · `swiftdata/model()` · `swiftdata/query` · `swiftdata/modelcontext/insert(_:)` · `swiftui/environmentvalues/modelcontext` · `swiftui/scene/modelcontainer(for:inmemory:isautosaveenabled:isundoenabled:onsetup:)` · `alarmkit`, `alarmkit/alarmmanager`, `alarmkit/alarmmanager/requestauthorization()` iOS 26 · `bundleresources/entitlements/com.apple.security.application-groups` · `bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit` · `bundleresources/entitlements/com.apple.developer.icloud-container-identifiers` · `bundleresources/information-property-list/nsalarmkitusagedescription` iOS 26 · `…/nssupportsliveactivities` · `…/nscamerausagedescription` · `…/nsphotolibraryusagedescription` · `…/nsextension/nsextensionpointidentifier` · `…/wkapplication` · `…/wkcompanionappbundleidentifier` · `…/wkrunsindependentlyofcompanionapp` · `…/cfbundledisplayname`.
Added in rev. 2: `swiftui/environmentkey` · `swiftui/stateobject` iOS 14 · `combine/observableobject` · `combine/published` · `foundation/bundle/localizedstring(forkey:value:table:)` · `swift/string/init(format:locale:_:)` · `bundleresources/privacy-manifest-files` · `bundleresources/app-privacy-configuration/nsprivacytracking` · `…/nsprivacytrackingdomains` · `…/nsprivacycollecteddatatypes` · `…/nsprivacyaccessedapitypes` (+ `/nsprivacyaccessedapitype`, `/nsprivacyaccessedapitypereasons`) · `bundleresources/information-property-list/itsappusesnonexemptencryption`.
Not found as doc pages (404): `com.apple.developer.usernotifications.time-sensitive` entitlement page (capability exists in the portal table).

## 13. Isolated probes (`Probes/`)

Separate SwiftPM packages with their own `xtool.yml`, not referenced by `Package.swift`, `project.yml` or CI, so an expected failure cannot break the app. Delete after the Phase 0 gate.

| Probe | Question | Command (WSL, after H3) | Expected |
|---|---|---|---|
| `MacroProbeSwiftData` | Do SwiftData `@Model`/`@Query` expand under xtool? | `bash scripts/probe-build.sh MacroProbeSwiftData` | FAIL (`SwiftDataMacros` missing, #149) |
| `XCStringsSwiftPM` | Does SwiftBuild compile a catalog that is a SwiftPM resource, for iOS, on Linux? | `bash scripts/probe-build.sh XCStringsSwiftPM` | unknown: build error (no `xcstringstool`) or raw copy |

## 14. Human steps (numbered; nothing secret ever goes into chat)

- **H1 — Apple Developer Program.** Decide individual vs organisation (organisation needs a D-U-N-S number; the seller name shown on the App Store differs) and enrol at https://developer.apple.com/programs/enroll/ (annual fee). Blocks: App Groups via xtool, CloudKit, Time Sensitive, TestFlight, IAP, increased memory limit.
- **H2 — Xcode 27 .xip.** In a browser: https://developer.apple.com/download/all/?q=Xcode → download **Xcode 27.0 (build 27A266a)** `.xip` — the exact version OpenAppleMacros tracks; a later 27.x may expand macros differently (Apple ID; accepting the Xcode and Apple SDKs Agreement — read §10 first). Then in WSL copy it to ext4: `cp /mnt/c/Users/simon/Downloads/Xcode_27*.xip ~/`
- **H3 — xtool setup (interactive, in your own WSL terminal).** `xtool setup` → login mode `0: API Key` (paid; Team Key, role App Manager; the key file stays on your machine) or `1: Password` (free Apple ID; consider a throwaway Apple ID) → path to the `.xip`. Verify: `xtool sdk status` (expect up to date) and `swift sdk list` (expect `darwin`). Disk ~7 GB (or `xtool sdk install --slim ~/Xcode_27*.xip`).
- **H4 — iPhone over USB.** Windows admin PowerShell: `winget install --interactive --exact dorssel.usbipd-win` → plug in the iPhone, unlock it → `usbipd list` (find the Apple device bus ID) → `usbipd bind --busid <BUSID>` → `usbipd attach --wsl --busid <BUSID>` (keep a WSL window open). In WSL: `idevice_id -l` then `idevicepair pair` and tap **Trust** on the phone. If the phone reconnects (after Trust/reboot) run `usbipd attach` again. Fallback: iTunes relay (§9).
- **H5 — First install.** `bash scripts/xtool-dev.sh` (WSL). On the iPhone enable Settings → Privacy & Security → **Developer Mode** (restart), and for a free account trust the profile under Settings → General → VPN & Device Management. Then run the on-device checklist (§15).
- **H6 — GitHub repo.** Create the repo (public = free macOS minutes; private = paid minutes, see §8; decision D2). The orchestrator commits/pushes only after your approval.
- **H7 — App Store Connect API keys.** App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys. Recommended: key **"CI"** with **Admin** role (cloud distribution signing) and key **"xtool"** with **App Manager** role (local). Download each `.p8` once.
- **H8 — GitHub secrets/variables** (repo → Settings → Secrets and variables → Actions): secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`; variable `APPLE_TEAM_ID`. To produce the base64 locally without printing it: PowerShell `[Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\Downloads\AuthKey_XXXXXXXXXX.p8")) | Set-Clipboard`, paste into the secret field, then clear the clipboard. Never paste keys into chat or commit them (`.gitignore` blocks `*.p8`).
- **H9 — App Store Connect app record.** My Apps → + → New App: platform iOS, bundle ID `sk.simondev.tabula` (register the explicit App IDs `sk.simondev.tabula`, `.TabulaWidgets`, `.watchkitapp` and App Group `group.sk.simondev.tabula` in Certificates, Identifiers & Profiles if automatic signing does not create them). Then run the workflow manually (Actions → iOS CI → Run workflow).

## 15. On-device checklist (Phase 0, after H5) — record results here

Two steps (macro isolation): **Step A** = base variant, `bash scripts/xtool-dev.sh` (items 1–5, 8, 10–12; "Macro probes" row = OFF, macro rows say "not built"). **Step B** = macro variant, `bash scripts/xtool-dev.sh --macro-probes` (items 6, 7, 9; "Macro probes" row = ON). If step B fails to build, record the compiler error: that is the macro verdict, and the step A results still stand. Caveat: `ImportProbes.swift` uses `@State` (a macro), so step A is only truly macro-free once import-ml removes it.

1. App launches; title "Tabula · Phase 0 probes". **Build path** row says `xtool / SwiftPM`.
2. **Bundle ID** row: record the exact `XTL-…` value.
3. **App Group**: tap "Run App Group round-trip" → free team: expect Container URL FAIL (nil); paid team: all three PASS.
4. Add the **"Tabula probe"** widget (small). It shows "App Group: OK/MISSING", the app's value and a ticking countdown. After step 3 + "Refresh read-backs", the **Widget read-back** row shows `<value> @ <time>`. Widget gallery name is "Tabula probe" (a raw `probe.widget.name` = extension strings not compiled).
5. (A5) **Localization**: en.lproj and sk.lproj PASS; sk line reads "Ahoj zo String Catalogu | 1 hodina · 3 hodiny · 5 hodín". Switch the phone to Slovak → "Current language" row turns Slovak.
6. (Step B) **@Observable**: "Tick" increments the counter.
7. (Step B) **@Entry**: shows `injected-by-DebugScreen` (PASS). (Step A shows the same value via a plain EnvironmentKey, status INFO.)
8. **AppIntent**: "Run AppIntent in-process" → PASS + timestamp. Shortcuts app → search "Tabula": is "Run Tabula probe" listed? Run it from there, then "Refresh read-backs" → timestamp changes.
9. (Step B) **@Generable**: schema text visible (Step A: "not built").
10. App icon on the Home Screen is the blue grid.
11. `bash scripts/probe-build.sh MacroProbeSwiftData` and `… XCStringsSwiftPM`: record exit status + key error lines.
12. Import and AlarmKit sections: see the import-ml and notifications checklists.

## 16. Proposed `Commands` section for CLAUDE.md (orchestrator to merge; not edited by me)

```
## Commands
- Linux validation (run before every commit): `bash scripts/validate.sh`            (inside WSL)
- Core tests: `bash scripts/core-test.sh`  (= swift test --package-path Packages/TimetableCore, ext4 scratch path)
- Local build: `bash scripts/xtool-dev.sh build`   · build+install+launch on iPhone: `bash scripts/xtool-dev.sh`
- Macro-probe variant (CLAUDE.md rule 5): `bash scripts/xtool-dev.sh --macro-probes [build]`
- String Catalog compiler self-test: `python3 scripts/l10n-compile.py --self-test`
- Isolated probes: `bash scripts/probe-build.sh <MacroProbeSwiftData|XCStringsSwiftPM>`
- Regenerate Xcode project (CI does this): `TABULA_DEVELOPMENT_TEAM= xcodegen generate --spec project.yml`
- From Windows Git Bash: `MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -- bash -lc 'cd "/mnt/c/Users/simon/Documents/Claude Code/school_timetable" && bash scripts/validate.sh'`
- CI: `.github/workflows/ios.yml` (TestFlight: Actions → iOS CI → Run workflow)
```

## 17. Local LLM runtime (import-ml)

Full report: [`docs/spikes/LLM_RUNTIME.md`](spikes/LLM_RUNTIME.md) · spike code: `spikes/llm-runtime/` (llama.cpp fetched by pinned tag, never vendored). Merged by the orchestrator, 2026-10-04.

| Item | Status | Evidence | Next step / unblock |
|---|---|---|---|
| llama.cpp CPU build (CMake) on WSL | VERIFIED | tag `b11382` (commit `11fe0215`): configure 7.6 s, build 122.1 s (-j16); `llama-cli --version` → `0.5.0-dev (build 1, commit 11fe021)` | — |
| llama.cpp from source as a SwiftPM target, Swift 6.4 | VERIFIED (Linux) | `scripts/run-spike.sh`: SwiftBuild release build 50.2 s, 0 warnings; probe prints `llama_print_system_info … CPU : LLAMAFILE = 1 \| REPACK = 1`; 3.73 MB stripped (CPU, x86_64). Upstream bug found: `src/models/clef.cpp` missing `#include <algorithm>` (masked by unity builds) | fallback route only |
| Grammar-constrained output from Swift | VERIFIED (model-free) | malformed GBNF rejected (NULL); grammar walk with a vocab-only GGUF from the llama.cpp repo (no weights) produced `{"day":"wed","period":2,…}`, accepted by `JSONSerialization` | real decoding = Phase 9 |
| Official XCFramework as SwiftPM `binaryTarget` | VERIFIED (Linux resolve) / BLOCKED (iOS) | `b11382` zip 61.8 MB, slices ios-arm64 + macOS; iOS framework 11.35 MB dynamic, Metal source embedded (`newLibraryWithSource`), exports `llama_sampler_init_grammar`; Linux resolve + checksum 7.2 s, `canImport(llama) == false` when platform-gated | H2–H3, then xtool build embedding `llama.framework` |
| XCFramework under xtool | RESEARCH-ONLY (source) | SwiftPM 6.4 / swift-build / xtool 1.20.1 sources: slice selection by target platform, codesign check macOS-only, xtool embeds + signs binary-target frameworks | device test |
| MLX Swift 0.32.3 | RESEARCH-ONLY → not viable on xtool path | README: SwiftPM CLI cannot build Metal shaders; Metal compiler only via `xcrun` on macOS; no grammar-constrained decoding; `mlx-swift-lm` uses macros + nested framework | — |
| Foundation Models API names | RESEARCH-ONLY (docs) | `SystemLanguageModel.default`, `.availability` (`deviceNotEligible` / `appleIntelligenceNotEnabled` / `modelNotReady`, `@unknown default`), `supportedLanguages`, `supportsLocale(_:)`, `@Generable`. **`isSupported` does not exist** (AI_IMPORT.md is wrong). iOS 27 adds image `Attachment`, `LanguageModel`, Core AI, `OCRTool` (gated) | probe on device |
| Apple Intelligence language coverage | RESEARCH-ONLY | of our 12: en, de, fr, ja, zh only; sk, cs, pl, hu, ro, sr, uk unsupported | — |
| Vision `RecognizeDocumentsRequest` | RESEARCH-ONLY (docs) | `[DocumentObservation]` → `.document.tables` → rows/columns → `Cell` (`rowRange`, `columnRange`, `content.text`); per-cell confidence derived from `lines[i].topCandidates(n).confidence`; `supportedRecognitionLanguages` is an instance property; Apple states 26 languages but publishes no list | probe on device (decisive for sk/cs/pl/hu/ro/sr) |
| Increased memory limit | RESEARCH-ONLY | only "Increased Debugging Memory Limit" appears in the capability table; xtool 1.20.1 deletes unrecognised App ID capabilities → not provisionable via xtool; use `os_proc_available_memory()` | CI/TestFlight build in Phase 9 |
| Licences | VERIFIED (LICENSE files) | llama.cpp, ggml, mlx-swift, mlx, mlx-c, mlx-swift-lm: MIT | — |

**Recommendation (needs human approval: new dependency):** llama.cpp via a pinned `bNNNNN` XCFramework `binaryTarget` + checksum, linked only from a thin iOS-only adapter; `TimetableCore` owns the protocol, GBNF grammars and output validator (Linux-testable); from-source package kept as fallback and for Linux decoding tests in Phase 9. Probe needs **no** Info.plist keys (PhotosPicker is out-of-process).

## 18. AlarmKit & notifications (notifications)

Full report + 60-row device matrix: [`docs/spikes/ALARMKIT.md`](spikes/ALARMKIT.md). Merged by the orchestrator, 2026-10-04.

| Item | Status | Evidence | Next step / unblock |
|---|---|---|---|
| AlarmKit API surface | RESEARCH-ONLY (docs) | `AlarmManager.shared`, `requestAuthorization()`, `authorizationState`, `authorizationUpdates`, `alarms`, `alarmUpdates`, `schedule(id:configuration:)`, `cancel/stop/pause/resume/countdown(id:)`; `AlarmConfiguration` `.alarm/.timer`/countdown init (iOS 27 adds `appEntityIdentifier:` overloads); `Alarm.Schedule.fixed(Date)` / `.relative(time:repeats:)`; `Alert(stopButton:)` deprecated in 26.1 → `#available` | device |
| Syntax check of probe files | VERIFIED | `swiftc -parse -swift-version 6` passes on the 3 files; deliberately broken copy fails; TimetableUI + `#if canImport(AlarmKit)` metadata builds on Linux | type-check needs SDK |
| Entitlement | RESEARCH-ONLY | none; `NSAlarmKitUsageDescription` + separate per-app authorisation (not "the Clock app's permission model") | — |
| Alarm count limit | RESEARCH-ONLY → **undocumented, dynamic** | Apple DTS FAQ (developer.apple.com/forums/thread/797158): depends on device state; `schedule` throws `maximumLimitReached` | probe "limit" button on device |
| Silent / Focus / reboot / Watch | RESEARCH-ONLY | rings through Silent + every Focus, survives reboot/force-quit, forwarded to paired Watch; no watchOS AlarmKit; hidden/Face-ID-locked apps silently fail to alert; any hardware button stops ringing | device matrix |
| Time Sensitive | RESEARCH-ONLY | `.timeSensitive` interruption level; entitlement `com.apple.developer.usernotifications.time-sensitive` (capability paid-only; no doc page, 404); does **not** override Silent; HIG: for events "happening now or within an hour"; not provisionable by xtool → CI-only entitlements file | CI/TestFlight build |
| 64 pending cap | RESEARCH-ONLY | documented only on the deprecated `UILocalNotification` page (soonest 64 kept, rest silently dropped) | probe "64-cap" button on device |

Spec conflicts raised (decisions in the Phase 0 gate report): Time Sensitive for offsets > 60 min; auto-scheduled "exam tomorrow" alarms vs App Review; snooze depends on the countdown Live Activity; alarm buttons need App Intents (unproven under xtool); adapter should diff alarms by stable ID.
