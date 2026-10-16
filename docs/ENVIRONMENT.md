# ENVIRONMENT — verified facts, failures and human steps

Owner: env-ci-engineer · Phase 0 spike · Last updated: 2026-10-06 (rev. 3: first real compile, CI run, simulator pipeline, paid-account placeholders)
Status legend: **VERIFIED** (I ran it here, output quoted) · **FAILED** (I *executed* it here and it did not work) ·
**BLOCKED** (needs a device, an Apple account or a CI run; the unblock step is given) ·
**RESEARCH-ONLY** (taken from official docs or source code, not executed; "expected fail" = a source-based prediction, not a run).
Since 2026-10-06 all Apple-platform Swift **compiles**: iOS app + widget via xtool on WSL (base and macro variants,
0 errors, 0 warnings) and via XcodeGen/xcodebuild in CI (incl. the watch app); the watch sources also type-check
locally. Nothing has run on a device yet (no device access: human decision 2026-10-06); UI verification goes
through the CI iOS Simulator job (§19). Log files of the runs quoted here: `/root/phase0_*.log` in WSL.

## 0. Verdict summary

| Area | Verdict | One line |
|---|---|---|
| WSL toolchain (Swift 6.4, Linux tests) | VERIFIED | `swift test` on TimetableCore passes; TimetableUI tests 9/9; repo path with a space works; scripts now load swiftly in non-login shells (`scripts/lib/toolchain.sh`) |
| xtool 1.20.1 install | VERIFIED | AppImage runs under FUSE, SHA-256 matches the release digest |
| Darwin SDK (Xcode 27.0 **27A266a**) | VERIFIED | `xtool sdk status` → `installed · Flavor normal · epoch=2,darwinTools=1.1.0,oam=1.3.0`; bundle `Xcode.app/Contents/version.plist` `ProductBuildVersion 27A266a` = the build OpenAppleMacros 1.3.0 tracks; 9.4 GB |
| xtool **build** (iOS device, unsigned) | VERIFIED (after 2 fixes) | `bash scripts/xtool-dev.sh build` → `Build complete! (13.60 secs)`, `Wrote to …/xtool/TabulaApp.app`, 18 s wall clean, **0 errors / 0 warnings** (negative control proves warnings are surfaced). Fixes: cross-import overlays flag, widget `-u _main` (§2) |
| xtool **install** on iPhone | BLOCKED | no device access for now (human decision 2026-10-06); also needs `xtool auth` (currently `Logged out`) + USB passthrough (H4) |
| Simulator build | VERIFIED (local build) / CI pipeline UNRUN | `xtool dev build --triple arm64-apple-ios-simulator` works (Mach-O platform 7); no simulator exists on Windows. UI checks run on the CI iOS Simulator (`ui-screenshots.yml`, §19) |
| XcodeGen spec | VERIFIED | locally `xcodegen generate`; in CI run 37449454629 `xcodebuild` **Build Succeeded** (Xcode 27.0 27A266a): app + widget + watch (`watch archs: arm64 arm64_32`), all bundle checks `ok` |
| Both build paths use the same sources | VERIFIED (compiled on both) | xtool on WSL + XcodeGen in CI; `scripts/validate.sh` → `ALL CHECKS PASSED` (123 OK) incl. identity single-source + paid-switch checks |
| Macro policy (PHASE2_PLAN §0.1, since 2026-10-09) | VERIFIED (compiled, both variants + xtool Release) | `@Observable`/`@State`/`@Entry`/`@Environment` allowed in app code (AppModel is `@Observable`); guard narrowed to `App/Sources/Debug/**` + TimetableUI/TimetableCore; SwiftData banned everywhere (§4). Phase 0 history: | base variant: 0 macro symbols (`ObservationTickProbe`/`Phase0GenerableSlot` absent); macro variant: present. `ImportProbes.swift` no longer uses `@State` (no WARN) |
| Macros under xtool | **VERIFIED (compile)**: `@Observable`, `@Entry`, `@State`, `@Generable`/`@Guide` · **FAILED**: SwiftData | `--macro-probes` build 0 errors/0 warnings; binary has 64 `ObservationTickProbe` + 118 `Phase0GenerableSlot` symbols. SwiftData probe: `plugin for module 'SwiftDataMacros' not found`. Runtime behaviour = device/simulator check |
| App Intents under xtool | VERIFIED (compiles) / metadata absent (VERIFIED) | links; the xtool bundle has **no** `Metadata.appintents` → Shortcuts listing expected only on the Xcode/TestFlight path |
| String Catalogs under xtool | **FAILED (executed, iOS cross-build)** / mitigated | `.xcstrings` as SwiftPM resource = hard build error (`xtool/.xtool-tmp/xcstringstool … is not an executable file`); `scripts/l10n-compile.py` `.lproj` tables are in the bundle (app + widget, en + sk); validate.sh forbids `.xcstrings` SwiftPM resources |
| Widgets under xtool | VERIFIED (build + package) / device BLOCKED | `PlugIns/TabulaWidgets.appex` (346 KB, `__text` + `__swift5_entry`, `NSExtensionPointIdentifier com.apple.widgetkit-extension`, ad-hoc signed with the App Group) |
| watchOS under xtool | FAILED by design (no triple) / **local type-check VERIFIED** | xtool's swift-sdk has no watchOS triple, but the bundle's Xcode.app contains `WatchOS27.0.sdk`: `scripts/watch-typecheck.sh` type-checks TimetableCore + TimetableUI + WatchApp for `arm64_32-apple-watchos26.0` in 8.4 s; negative control fails with `'textSelection' is unavailable in watchOS`. Link/package/install = CI/TestFlight |
| Watch architecture (Series 7 = arm64_32) | VERIFIED (CI) | CI run 37449454629: `watch archs: arm64 arm64_32` |
| TestFlight readiness (static) | VERIFIED (static) | `ITSAppUsesNonExemptEncryption = false`; `PrivacyInfo.xcprivacy` for app and widget on both paths (UserDefaults CA92.1 + 1C8F.1) |
| CI workflow | PARTIAL (root cause of the failure found + fixed, re-run pending) | [run 37449454629](https://github.com/simon01920/tabula-app-ios/actions/runs/37449454629): core-linux ✓ (1 m 15 s), ios-xcodegen ✓ (1 m 07 s), ios-xtool-path ✗ cancelled after 40 min: we started `xtool.app/Contents/MacOS/xtool`, which is the **GUI app** unless `XTL_CLI=1` (xtool source `macOS/XToolMac/XToolMac.swift`); the CLI is `Contents/Resources/bin/xtool`. Fixed + 15-min caps (§8) |
| Paid-account placeholders | VERIFIED (static) / CI assertion UNRUN | `Config/AppIdentity.xcconfig` single source + `TABULA_PAID_ACCOUNT` switch; 8/8 negative tests fail as intended; runbook `docs/PAID_ACCOUNT_SWITCHOVER.md` (§20) |
| TestFlight upload | BLOCKED | paid Apple Developer Program deferred (human decision 2026-10-06); steps in `docs/PAID_ACCOUNT_SWITCHOVER.md` |

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
| swiftly in non-login shells | FAILED → fixed | `wsl.exe --exec bash -c 'command -v swift'` → nothing (swiftly only adds itself to PATH via `~/.profile`); first `xtool sdk install` died at 99 % with `Could not find executable 'clang' in PATH`. Fix: every script sources `scripts/lib/toolchain.sh` (`tabula_load_toolchain` searches `$TABULA_SWIFTLY_ENV`, `$SWIFTLY_HOME_DIR`, `$XDG_DATA_HOME/swiftly`, `~/.local/share/swiftly`, `/root/.local/share/swiftly`; `tabula_require swift clang xtool` fails with a hint). VERIFIED: step A/B builds run from `wsl.exe --exec bash` | run scripts as-is; for ad-hoc commands `. ~/.local/share/swiftly/env.sh` first |
| Calling WSL from Git Bash | VERIFIED (gotcha) | `wsl.exe -d Ubuntu -- bash -c '…$VAR…'` re-parses the command in a second shell, so `$VAR` set inside the quotes expands to empty; use `wsl.exe -d Ubuntu --exec bash -c '…'` or `--exec bash script.sh` | — |

## 2. xtool

| Item | Status | Evidence | Next step / unblock |
|---|---|---|---|
| Version pin | VERIFIED | GitHub API: release `1.20.1` (2026-09-21T06:05:38Z); asset `xtool-x86_64.AppImage` digest `sha256:040c58d5c708f613b9b74cbdb24e25e8d72c47ff86941f19463626d811159831` | bump deliberately; re-check release notes |
| Install + checksum | VERIFIED | `sha256 actual=040c58d5…159831` = expected; installed to `/usr/local/bin/xtool`; log `/root/phase0_xtool_install.log` | — |
| FUSE / AppImage | VERIFIED | AppImage executes directly (`/dev/fuse`, `fusermount3` present); `--appimage-extract` not needed | if FUSE ever breaks: `xtool --appimage-extract` and run `squashfs-root/AppRun` |
| `xtool --version` / `--help` | VERIFIED | `xtool 1.20.1`; subcommands `setup auth sdk new dev ds devices install uninstall launch`; `dev build [--sign] [--ipa] [--triple]` | — |
| Darwin SDK | VERIFIED | human-supplied `Xcode_27.xip` (2,014,229,334 B, sha256 `6a270c53…a67c3`); `xtool sdk install` (2nd attempt, after the PATH fix) → `xtool sdk status`: `Darwin SDK is installed · Path /root/.swiftpm/swift-sdks/darwin.artifactbundle · Flavor normal · Version epoch=2,darwinTools=1.1.0,oam=1.3.0`; `swift sdk list` → `darwin`; 9.4 GB. Finalized swift-sdk triples: `arm64-apple-ios`, `arm64/x86_64-apple-ios-simulator`, `arm64/x86_64-apple-macosx` (iPhoneOS27.0, iPhoneSimulator27.0, MacOSX27.0 SDKs) | — |
| Xcode build in the SDK | VERIFIED | `Xcode.app/Contents/version.plist`: `ProductBuildVersion 27A266a`, `CFBundleShortVersionString 27.0`; `Info.plist` `DTXcodeBuild 27A266`; iPhoneOS.platform `ProductBuildVersion 24A430` (27.0); WatchOS.platform `24R360` (27.0). **= OpenAppleMacros' tracked 27A266a** | keep this xip; re-check OAM when changing Xcode |
| watchOS SDK presence | VERIFIED (corrects an earlier note) | not a swift-sdk triple, but physically present: `…/Xcode.app/Contents/Developer/Platforms/WatchOS.platform/Developer/SDKs/WatchOS27.0.sdk` (340 MB platform) + WatchSimulator | used by `scripts/watch-typecheck.sh` |
| Auth | BLOCKED (not needed to build) | `xtool auth status` → `Logged out`; `dev build` needs no login (VERIFIED) | only for device installs (H3 login part, deferred) |
| Device discovery | BLOCKED | no device access for now (human decision 2026-10-06) | H4 later |
| Wrapper gate | VERIFIED | (before SDK) `bash scripts/xtool-dev.sh build` → `error: Darwin SDK not installed …` exit 2 | — |
| Cross-import overlays | FAILED → fixed | first build: `ImportProbes.swift:220:32: error: cannot find type 'PhotosPickerItem' in scope`. The type lives in the cross-import overlay `_PhotosUI_SwiftUI` (SDK has `PhotosUI.swiftcrossimport/SwiftUI.swiftoverlay`). xtool's `toolset.json` passes `-Xfrontend -enable-cross-import-overlays` but its SwiftBuild `toolset-swb.json` does not. Fix: `Package.swift` `.unsafeFlags(["-Xfrontend", "-enable-cross-import-overlays"])` on TabulaApp + TabulaWidgets (root package, so allowed). Also matters for `_StoreKit_SwiftUI`, `_AppIntents_SwiftUI`, `_MapKit_SwiftUI` | report upstream (xtool issue) when convenient |
| Empty widget appex → signing failure | FAILED → fixed | after compiling: `>>> Can't find free space of LoadCommands for CodeSignature!` / `Error: Signing failed` (zsign, during xtool's ad-hoc "Applying entitlements…", even without `--sign`). Root cause: the appex had **no `__text`** (sections `__stubs __got` only, 49 KB): xtool links extensions with `-e _NSExtensionMain`, nothing references the widget's `_main`, so ld64.lld never pulls the package objects; zsign computes header space from `__text`. Reproduced by relinking SwiftBuild's exact command: `-u _main` → 321 KB with `__text … __swift5_entry`. Fix: TabulaWidgets `linkerSettings: .unsafeFlags(["-Xlinker","-u","-Xlinker","_main"])`. Guards: `xtool-dev.sh` (llvm-objdump) and CI (`otool -l`) fail if `__text`/`__swift5_entry` are missing | device check: widget renders (proves `__swift5_entry` lookup works with `_NSExtensionMain`) |
| Bundle produced by `xtool dev build` | VERIFIED | `TabulaApp.app`: `TabulaApp` (arm64, 1.17 MB), `Info.plist` merged (xtool defaults `CFBundleIdentifier sk.simondev.tabula`, `CFBundleVersion 1`, `CFBundleShortVersionString 1.0.0`, `MinimumOSVersion 26.0`, `CFBundleSupportedPlatforms [iPhoneOS]`, `UIRequiredDeviceCapabilities [arm64]`, `CFBundleIconFile AppIcon` + all keys of `Config/App-Info.plist`), `AppIcon.png`, `PrivacyInfo.xcprivacy`, `en.lproj`/`sk.lproj` `Localizable.strings(+dict)`, `_CodeSignature`, embedded entitlements `{application-groups: [group.sk.simondev.tabula]}`; `PlugIns/TabulaWidgets.appex` (`CFBundlePackageType XPC!`, `NSExtensionPointIdentifier com.apple.widgetkit-extension`, same resources). No `Metadata.appintents`, no `Assets.car` (expected). Strongly linked: ActivityKit, AlarmKit, AppIntents, FoundationModels, PhotosUI, `_PhotosUI_SwiftUI`, SwiftUI, Vision, WidgetKit… (fine: minimum iOS 26) | — |
| SDK version stamped in binaries | VERIFIED (oddity) | `LC_BUILD_VERSION platform=2 minos=26.0.0 sdk=26.0.0` although compiled against iPhoneOS27.0.sdk (`-target-sdk-version 27.0`); the xcodebuild path will stamp 27.0. Runtime "linked-on-or-after" behaviour may differ between the paths | watch for iOS 27-only behaviour differences between xtool and TestFlight builds |
| Probe packages | VERIFIED (executed) | §13 | — |
| Licence | VERIFIED | `LICENSE.md`: MIT (Kabir Oberai). Build tool only, not shipped in the app | — |
| `xtool.yml` schema | VERIFIED (source) | 1.20.1 `Sources/PackLib/PackSchema.swift`: `version, orgID, bundleID, product, infoPath, entitlementsPath, iconPath, resources, extensions[{product, bundleID, infoPath, resources, entitlementsPath}], skipLSP` | `validate.sh` rejects unknown keys |
| Products must be automatic libraries of the root package | VERIFIED (source + manifest) | `Planner.selectLibrary` filters `type == .autoLibrary`; `validate.sh`: `OK product TabulaApp: automatic library, path App/Sources` | — |
| Info.plist handling | VERIFIED (source) | xtool builds defaults (`CFBundleIdentifier`, `CFBundleVersion "1"`, `CFBundleShortVersionString "1.0.0"`, `UIDeviceFamily [1,2]`, `UILaunchScreen`) and **merges `infoPath` over them verbatim** → shared plists must not contain `$(VAR)` | enforced by `validate.sh` |
| macOS build of xtool exists | VERIFIED | release asset `xtool.app.zip` sha256 `39123efc…33ca2`; binary at `xtool.app/Contents/MacOS/xtool` | used by CI job `ios-xtool-path` |
| `xtool dev build` without login | VERIFIED (WSL) / macOS CI re-run pending | WSL: builds with `xtool auth status` = `Logged out`. Source (`DevCommand.swift` 1.20.1): token only for `--sign`; `EnsureSDKOperation` is a no-op on macOS; no prompt in the build path. The CI hang was not a prompt (see next row) | — |
| macOS xtool CLI entry point | VERIFIED (source + release zip) / FAILED as first used | release `xtool.app.zip` (sha256 `39123efc…33ca2`, cached at `~/.cache/tabula/dl/`): `Contents/MacOS/xtool` (36 MB, bundle `sh.xtool.XToolMac`) + `Contents/Resources/bin/xtool` (705-byte bash wrapper ending `XTL_CLI=1 "$APP_PATH/Contents/MacOS/xtool" "$@"`). `macOS/XToolMac/XToolMac.swift`: `if ProcessInfo.processInfo.environment["XTL_CLI"] == "1" { try await runXTool() } else { XToolMacUI.main() }`. The official Homebrew cask links `Contents/Resources/bin/xtool`. CI run 37449454629 symlinked the GUI binary → `xtool --version` printed nothing and the job was cancelled after 40 min (orphan `xtool` process killed at cleanup) | `ios.yml` now puts `Contents/Resources/bin` on PATH; validate.sh fails if `Contents/MacOS` is ever put on PATH again |
| xtool SwiftBuild toolset | VERIFIED | downloaded `darwin-tools-linux-llvm v1.1.0 toolset-x86_64.tar.gz` (sha256 `a5166f2d…74188`): only `bin/dsymutil`, `bin/ld64.lld`, `bin/libtool` — no `xcstringstool`, `actool`, `appintentsmetadataprocessor` | explains the catalog/asset/intents gaps |
| SDK size | VERIFIED | `du -sh` → **9.4 GB** (normal flavor; includes the full Xcode.app incl. WatchOS/tvOS/visionOS platforms) | `--slim` would drop the watchOS SDK used by `watch-typecheck.sh` |
| OpenAppleMacros (macro implementations xtool ships) | VERIFIED (match + compile) | repo `xtool-org/OpenAppleMacros` v1.3.0 (MIT) README: "Currently tracking: **Xcode 27.0.0 (27A266a)**" = the installed SDK's build. Compile line loads `SwiftUIMacros`, `FoundationModelsMacros`, `PreviewsMacros` via the SDK's `swift-plugin-server` and `ObservationMacros`, `FoundationMacros`, `SwiftMacros` from the swiftly toolchain. NOT provided: SwiftData (probe FAILED), App Intents macros, TipKit, StateReporting | re-check when Xcode changes |
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

xtool auto-registers only these capabilities from entitlements: Data Protection, App Groups (paid), Associated Domains, HealthKit, HomeKit, Inter-App Audio, Multipath, Network Extensions, Personal VPN, Push, SiriKit, Wireless Accessory, Wi-Fi Aware. **Time Sensitive, iCloud/CloudKit, increased-memory-limit, In-App Purchase capability are not handled** → keep `Config/*.entitlements` (shared with xtool) to App Groups only. The others are prepared (2026-10-06) in the CI-only `Config/Entitlements/PaidAccount/*.entitlements`, selected only by `TABULA_PAID_ACCOUNT = 1` (§20, `docs/PAID_ACCOUNT_SWITCHOVER.md`).

## 3. Build paths

| Item | Status | Evidence | Next step / unblock |
|---|---|---|---|
| (a) SwiftPM + `xtool.yml` | VERIFIED (compile + package, WSL) | step A (base) and step B (macro) both `Build complete!`, 0 errors / 0 warnings, ~18–20 s clean; bundle inspected (§2) | install = device (deferred) |
| (b) XcodeGen `project.yml` | VERIFIED (CI xcodebuild) | [CI run 37449454629](https://github.com/simon01920/tabula-app-ios/actions/runs/37449454629) (`xcode-27-arm64` image 20260928.0222.1, Xcode 27.0 Build version 27A266a, SDKs `iphoneos27.0` / `watchos27.0`, xcbeautify 3.2.1): **Build Succeeded**, every bundle check `ok` incl. `PlugIns/TabulaWidgets.appex`, `Watch/TabulaWatch.app/TabulaWatch`, en/sk `.strings`+`.stringsdict`, both privacy manifests, `ITSAppUsesNonExemptEncryption=false`, `watch archs: arm64 arm64_32`. Only warning from our project: `User supplied UIDeviceFamily key in the Info.plist will be overwritten` → **fixed** (key removed from the shared plist; Xcode uses `TARGETED_DEVICE_FAMILY "1"`, xtool falls back to its default `[1, 2]`, harmless for local dev installs) | — |
| XcodeGen licence/maintenance | VERIFIED | MIT; latest release 2.46.0 (2026-07-16), pushed 2026-09-13, not archived; `xcodegen.zip` sha256 `4d9e34b6…196806` | — |
| Team ID + identity wiring | VERIFIED (static + local XcodeGen) / Xcode resolution: CI assertion UNRUN | replaced XcodeGen's `${TABULA_DEVELOPMENT_TEAM}` env expansion (which kept the literal when unset) by Xcode build-setting references from `Config/AppIdentity.xcconfig` (project-level `configFiles`): `DEVELOPMENT_TEAM = $(TABULA_DEVELOPMENT_TEAM)`, `PRODUCT_BUNDLE_IDENTIFIER = $(TABULA_BUNDLE_ID)[.TabulaWidgets/.watchkitapp]`, `CODE_SIGN_ENTITLEMENTS = $(TABULA_APP_ENTITLEMENTS)` / `$(TABULA_WIDGET_ENTITLEMENTS)`. `xcodegen generate` needs no env any more (validate.sh runs it with the variable unset; pbxproj has both `baseConfigurationReference … AppIdentity.xcconfig`). CI `ios-xcodegen` asserts the resolution with `xcodebuild -showBuildSettings` | next CI run |
| Same sources | VERIFIED (compiled on both paths) | `validate.sh`: `OK project.yml targets/sources/plists in sync with Package.swift + xtool.yml`; both paths compiled 2026-10-06 | — |

Source mapping (identical on both paths): `App/Sources` (module `TabulaApp`), `WidgetExtension/Sources` (module `TabulaWidgets`), `Packages/TimetableCore`, `Packages/TimetableUI`, `Config/App-Info.plist`, `Config/Widgets-Info.plist`, `Config/Tabula.entitlements`, `Config/TabulaWidgets.entitlements`, `Resources/Localizable.xcstrings`. App bundle is `TabulaApp.app` on both paths; display name "Tabula" comes from the plist.

Differences by design: watch app (`WatchApp/Sources`, CI only; local type-check only) · device family: Xcode `TARGETED_DEVICE_FAMILY "1"`, xtool default `[1, 2]` · xtool-only `Package.swift` flags (`-enable-cross-import-overlays`, widget `-u _main`) · icon: xtool uses `Resources/AppIcon.png` (`CFBundleIconFile`), Xcode uses `Resources/Assets.xcassets` (xtool cannot compile asset catalogs, PR #219) · strings: Xcode compiles the catalog, xtool path uses `.build-l10n/` from `scripts/l10n-compile.py` · versions: xtool `1.0.0 (1)`, Xcode `MARKETING_VERSION 0.1.0` / `CURRENT_PROJECT_VERSION` (CI overrides with the run number) · `SWIFT_PACKAGE` is defined only on the xtool path (the debug screen shows which path built the app).

## 4. Macros

| Macro | Status | Evidence | Next step / unblock |
|---|---|---|---|
| `@Observable` | **VERIFIED (compile, xtool)** | `--macro-probes` build: 0 errors/0 warnings; `ObservationMacros` loaded from the swiftly toolchain (`-load-resolved-plugin …/libObservationMacros.so`); binary contains 64 `ObservationTickProbe` symbols + Observation registrar references. Also compiled in CI (Xcode) | runtime: CI simulator screenshot / device "Tick" row |
| SwiftUI `@Entry`, `@State`, `#Preview` | **VERIFIED (compile, xtool)** for `@Entry`, `@State` | `SwiftUIMacros` via the SDK's `swift-plugin-server` (OpenAppleMacros, Xcode 27A266a); 22 `phase0ProbeToken` symbols. `#Preview` not used | runtime: "@Entry environment value" row |
| FoundationModels `@Generable`, `@Guide` | **VERIFIED (compile, xtool)** | 118 `Phase0GenerableSlot` symbols; the binary calls `GenerationSchema(type:description:properties:)` and `GenerationSchema.Property(name:description:type:guides:)`, i.e. the macro expansion | runtime: "@Generable schema" row |
| SwiftData `@Model`, `@Query` | **FAILED (executed)** | `bash scripts/probe-build.sh MacroProbeSwiftData` → exit 1: `error: external macro implementation type 'SwiftDataMacros.PersistentModelMacro' could not be found for macro 'Model()'; plugin for module 'SwiftDataMacros' not found` (×5) and `error: unknown attribute 'Query'`. Log `/root/phase0_probe_MacroProbeSwiftData.log` | keep the versioned Codable store (ARCHITECTURE) |
| App Intents | VERIFIED (compile) / metadata absent | links on the xtool path; bundle has no `Metadata.appintents` (no `appintentsmetadataprocessor` in xtool's toolset; PR #217 closed unmerged) | device/TestFlight: is "Run Tabula probe" listed in Shortcuts? (expect no on xtool, yes on TestFlight) |

| `@State` | VERIFIED (macro in the Xcode 27 SDK; compiles via OAM) | In the Xcode 27 SDK `@State` is a SwiftUI **macro** (OAM README; xtool PR #101). Compiles under xtool in the macro variant. `@StateObject`, `@Published`, `@Environment` are not macros | base variant uses `@StateObject`/`@Published`; `ImportProbes.swift` no longer uses `@State` (validate.sh: no WARN) |

**Macro policy since Phase 2 (PHASE2_PLAN §0.1, Stage A 2026-10-09).** `@Observable`, `@State`, `@Entry` and `@Environment` are allowed in real app code (`App/Sources` outside `Debug/`, `WidgetExtension`, `WatchApp`); in the Xcode 27 SDK a macro-free SwiftUI app is impossible anyway (`@State` is a macro). `validate.sh` (`scripts/validate_config.py`) now enforces:

| Rule | Scope | Why |
|---|---|---|
| Macro outside `#if TABULA_MACRO_PROBES` = FAIL | `App/Sources/Debug/**` | the Phase 0 probes keep their base/macro variants; new debug UI uses `@StateObject`/`@Published` |
| Macro outside `#if TABULA_MACRO_PROBES` = FAIL | `Packages/TimetableUI/Sources`, `Packages/TimetableCore/Sources` | Linux `swift test` and `scripts/watch-typecheck.sh` (plain `swiftc`, no SwiftUI macro plugins) must keep compiling them |
| `import SwiftData`, `@Model`, `@Query`, `@Attribute`, `@Relationship`, `@Transient`, `@ModelActor` = FAIL | App, Widget, Watch, TimetableUI, TimetableCore | SwiftData macros FAILED under xtool (table above) |
| Every file in `App/Sources/Debug/**` is wrapped in `#if DEBUG … #endif` | Debug | PHASE2_PLAN §0.2 (debug code never ships) |

- VERIFIED 2026-10-09: base variant `bash scripts/xtool-dev.sh build` (AppModel `@Observable` + `@State` in the shell, without `TABULA_MACRO_PROBES`) → `Build complete!`, 0 errors / 0 compiler warnings; `--macro-probes` → `Build complete!`; `xtool dev build -c release` → `Build complete!`, `DeveloperScreen` symbols 0 (Debug folder compiled out) vs 176 in the Debug build.
- Negative tests (throwaway copy, 2026-10-09), each produced the intended FAIL: `@State` in `Debug/DebugRoutes.swift`; `import SwiftData` in `Today/TodayRoutes.swift`; `@Observable` in TimetableUI; an unwrapped file in `Debug/`. (Limitation kept from Phase 0: only attributes at the start of a line are detected.)
- The `TABULA_MACRO_PROBES` define itself is unchanged: `Package.swift` reads `Context.environment["TABULA_MACRO_PROBES"]`, `scripts/xtool-dev.sh --macro-probes` sets it (work dir `…/work-macro`); the XcodeGen/CI path always defines it.
- Phase 0 history: the base variant used to contain no macros at all (0 `ObservationTickProbe` / 0 `Phase0GenerableSlot` symbols vs 64 / 118 in the macro variant, 2026-10-06).

Decision input for ARCHITECTURE: keep the **versioned Codable store** default; SwiftData is not viable on the local path (now executed, not just predicted). `@Observable` **is** viable on both paths (compile-verified; runtime check pending), so Phase 2 may use it, subject to the CLAUDE.md rule-5 gate decision by the orchestrator/human.

## 5. Extensions & watchOS

| Item | Status | Evidence | Next step / unblock |
|---|---|---|---|
| Widget extension (WidgetKit) | VERIFIED (build + package, both paths) / runtime BLOCKED | xtool: `PlugIns/TabulaWidgets.appex` after the `-u _main` fix (§2); CI: `TabulaWidgets.appex in Embed Foundation Extensions` built. Whether the widget actually renders (gallery, timeline, App Group read-back) is a device check; the simulator job cannot add widgets to the Home Screen | device (later) |
| ExtensionKit extensions | RESEARCH-ONLY → not supported | issue #138 open (`Extensions/` folder not supported) | avoid ExtensionKit-only extension points locally |
| Live Activity (`AlarmLiveActivity`) | RESEARCH-ONLY | lives in the same WidgetKit extension (registered in `TabulaWidgetBundle`) | notifications agent's checklist |
| watchOS app under xtool | FAILED by design (source) | SDK definition has only `arm64-apple-ios`, `*-apple-ios-simulator`, `*-apple-macosx` triples; `Packer` writes `CFBundleSupportedPlatforms = [iPhoneOS]` and only `iphoneos/iphonesimulator` product dirs | watch build = CI (XcodeGen) |
| Watch architecture | VERIFIED (CI) | CI run 37449454629: `watch archs: arm64 arm64_32` (Series 7 = S7 = arm64_32; swift-build `watchOSDevice.xcspec` arm64_32 `DeploymentTargetRange ("0", "27")`). `project.yml` sets no `ARCHS` | never raise the watch deployment target past 26.x while Series 7 is supported |
| watchOS via CI | VERIFIED | `TabulaWatch` compiled + linked + embedded at `TabulaApp.app/Watch/TabulaWatch.app/TabulaWatch` | — |
| watchOS on-device install | BLOCKED | without a Mac, the only route is TestFlight (paid account, deferred) → iPhone → Watch app | iteration cost below |
| **Local watchOS type-check** | **VERIFIED** | `bash scripts/watch-typecheck.sh`: `swiftc -target arm64_32-apple-watchos26.0 -sdk …/WatchOS27.0.sdk -resource-dir …/XcodeDefault.xctoolchain/usr/lib/swift` emits TimetableCore + TimetableUI modules and type-checks `WatchApp/Sources` → `watchOS type-check OK (arm64_32-apple-watchos26.0)` in **8.4 s**. Negative control (iOS-only `.textSelection(.enabled)` in a throwaway copy) → `error: 'textSelection' is unavailable in watchOS`, exit 1. Runs in `validate.sh` when the SDK is present (SKIP in the CI Linux job) | — |
| watchOS simulator screenshot | UNRUN (optional CI input) | `ui-screenshots.yml` input `watch: true` boots the largest Apple Watch simulator, installs `TabulaApp.app/Watch/TabulaWatch.app`, screenshots it (`continue-on-error`) | run manually when watch UI exists |

Iteration-speed cost of the watch route (2026-10-06): watchOS **compile errors** now surface locally in ~8 s (type-check), so the expensive loop is only for **runtime/UI**: CI build ~1–2 min (measured: whole XcodeGen job 1 m 07 s) + optional CI watch-simulator screenshot (~3 min extra, estimate) ≈ **5–10 min**; on the real Watch only via TestFlight (paid account): + processing 5–30 min + install ≈ **30–60 min per change** (estimate). Mitigation unchanged: thin watch UI, logic in TimetableCore (Linux-tested).

## 6. String Catalogs (`.xcstrings`)

| Item | Status | Evidence | Next step / unblock |
|---|---|---|---|
| Xcode path (XcodeGen, CI) | VERIFIED (CI) | [run 37449454629](https://github.com/simon01920/tabula-app-ios/actions/runs/37449454629): Xcode compiled `Resources/Localizable.xcstrings` into `TabulaApp.app/{en,sk}.lproj/Localizable.strings` + `.stringsdict` and `TabulaWidgets.appex/{en,sk}.lproj/Localizable.strings` (all `ok`) | runtime lookup: CI simulator `debug-localization` screenshot |
| SwiftPM native, Linux host | FAILED | probe package: `[1/7] Copying Localizable.xcstrings`; bundle contains raw `Localizable.xcstrings`; lookup → `<MISSING>` | — |
| SwiftBuild, Linux host | FAILED | `warning: no rule to process file '…/Localizable.xcstrings' of type 'text.json.xcstrings' for architecture 'x86_64'`; copied raw; lookup → `<MISSING>` | — |
| SwiftBuild, iOS cross-build via xtool | **FAILED (executed)** | `bash scripts/probe-build.sh XCStringsSwiftPM` → exit 1: `error: …/Resources/Localizable.xcstrings Could not read xcstrings file: The command \`(cd … && env -i … …/xtool/.xtool-tmp/xcstringstool compile --dry-run --output-directory … Localizable.xcstrings)\` … xcstringstool is not an executable file.` → a `.xcstrings` SwiftPM resource **breaks the whole build** (not a raw copy). Log `/root/phase0_probe_XCStringsSwiftPM.log` | `validate.sh` fails if any Package.swift target declares a `.xcstrings` resource |
| `.lproj` tables in the xtool bundle | VERIFIED | `l10n-compile.py` output copied by xtool.yml: app and widget each have `en.lproj` + `sk.lproj` `Localizable.strings` (730/763 B) and `.stringsdict` (590/690 B) | runtime lookup = device/simulator check |
| Mitigation `scripts/l10n-compile.py` | VERIFIED (Linux) | converts catalog → `en.lproj`/`sk.lproj` `Localizable.strings` (+ `.stringsdict` for plurals); Linux Foundation reads them: `en hello: Hello from the String Catalog`, `sk hello: Ahoj zo String Catalogu` | wired into `xtool-dev.sh` + `xtool.yml resources` |
| Plural `.stringsdict` at runtime | BLOCKED | structure matches Apple's documented format (`NSStringLocalizedFormatKey = %#@arg@`, `NSStringPluralRuleType`, `NSStringFormatValueTypeKey = lld`); swift-corelibs Foundation **crashes** on stringsdict lookup on Linux (Signal 11 in `Bundle.localizedString` → `NSString.getCharacters`) so it cannot be checked here | device checklist item 5 (sk: "1 hodina · 3 hodiny · 5 hodín") |
| Limits of the converter | VERIFIED | rejects `substitutions` and `device` variations (non-zero exit); `%%` is not treated as a format specifier; empty or `state: new` units are skipped and fall back to the source language (as do missing translations). `python3 scripts/l10n-compile.py --self-test` → 11/11 OK (C1 added every plural category set, `sr-Latn`/`zh-Hans` folders, positional re-ordering) | revisit in Phase 2 if needed |
| 12-language bundle on the xtool path (Phase 2 C1) | VERIFIED (build) | `bash scripts/xtool-dev.sh build` (2026-10-10) → 0 errors, no "no usable translation" warnings; the script now prints the bundle's localisations: app and widget appex both contain `cs de en fr hu ja pl ro sk sr-Latn sr uk zh-Hans` `.lproj` (each `Localizable.strings` + `.stringsdict`); built `Info.plist` has `CFBundleLocalizations` = the 12 ids | runtime resolution on a device (checklist: Serbian Latin vs Cyrillic, plural forms) |
| Localised Info.plist strings (Phase 3 C2), xtool path | VERIFIED (build) | `Resources/InfoPlist.xcstrings` (5 keys: `CFBundleDisplayName`, `NS{AlarmKit,Camera,Microphone,PhotoLibrary}UsageDescription`; 12 languages, `needs_review`). `scripts/infoplist-strings.py` (thin wrapper over `l10n-compile.py`, file stem = table name; also fails if a display-name/`NS*UsageDescription` key of `Config/App-Info.plist` is missing from the catalog) is run by `xtool-dev.sh` (and the ios.yml xtool job) into `.build-l10n/`; xtool.yml copies the `<lang>.lproj` dirs into the app; since Phase 3 polish the widget gets a separate Localizable-only copy (`.build-l10n/widget`, §25). `bash scripts/xtool-dev.sh build` (2026-10-15) → exit 0; `TabulaApp.app/{cs,de,en,fr,hu,ja,pl,ro,sk,sr,sr-Latn,uk,zh-Hans}.lproj/InfoPlist.strings` = 13 files, `sk.lproj/InfoPlist.strings` holds all 5 keys with Slovak text. Generated at build time (git-ignored), nothing to keep in sync | iOS picks the value at runtime: device checklist C2 |
| Localised Info.plist strings, Xcode path | UNVERIFIED (CI only) | `project.yml` adds `Resources/InfoPlist.xcstrings` to the TabulaApp resources phase (validate_config.py checks it; XcodeGen generation passes). That Xcode compiles it into `<lang>.lproj/InfoPlist.strings` for a target with `INFOPLIST_FILE` + `GENERATE_INFOPLIST_FILE` was NOT proven here (no macOS, Apple docs not fetched this session); the next CI run must list `TabulaApp.app/sk.lproj/InfoPlist.strings`. Known xtool-path difference: the widget appex also carries the app's InfoPlist.strings (same lproj dirs), so its `CFBundleDisplayName` reads "Tabula" instead of "Tabula Widgets"; not user-visible in practice | CI run: list the app bundle |
| XcodeGen `knownRegions` | NOT CONFIGURABLE | XcodeGen 2.46 has no such option (a `knownRegions:` key was ignored; pbxproj `knownRegions = (Base, en)`; it derives regions from `.lproj` dirs and from catalogs found when scanning source *directories*, not a file entry). Not needed: CI run 37449454629 emitted `sk.lproj` with the same Base+en regions | `CFBundleLocalizations` in `Config/App-Info.plist` / `Config/Widgets-Info.plist` declares all 13 ids on both paths (validate_config.py) |
| `Bundle.preferredLocalizations` on Linux | NOT USABLE | swift-corelibs `Bundle.preferredLocalizations(from:forPreferences:)` returns `["en"]` for every preference (even `sk-SK`), so language matching of `sr` / `sr-Latn` / `zh-Hans` cannot be verified off-device. Chosen ids follow Apple/CLDR conventions (`sr` = Cyrillic, `sr-Latn`, `zh-Hans`) | device checklist, `docs/localization/REVIEW.md` |
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
| Workflow files | VERIFIED (syntax + structure) | `ios.yml` jobs `core-linux, ios-xcodegen, ios-xtool-path, release-testflight`; `ui-screenshots.yml` job `ios-simulator-screenshots` (§19). Every `run:` block passes `bash -n`; validate.sh checks triggers, cost guards, SHA pinning, secret scoping | — |
| Repo + first run | VERIFIED | repo `simon01920/tabula-app-ios` (private), pushed 2026-10-06 by the orchestrator (gh CLI over HTTPS, `docs/GITHUB_SETUP.md`); first run **37449454629** (workflow_dispatch, `upload=false`) | — |
| (a) Linux job | VERIFIED | run 37449454629: success in 1 m 15 s (`swift:6.4.0-noble`; TimetableCore tests + validate.sh). From now on validate.sh also runs the TimetableUI tests there | — |
| (b) XcodeGen + unsigned xcodebuild | VERIFIED | run 37449454629: success in 1 m 07 s; details §3. New since: `-showBuildSettings` assertion of identity + paid switch (both states, team override), `CFBundleIdentifier` = xcconfig | next run proves the new step |
| (c) xtool path on macOS | **FAILED (executed) → root cause fixed, re-run pending** | run 37449454629: steps up to "Compile String Catalog" succeeded in 6 s; the next step's first command `xtool --version` never printed; cancelled at 40 min (all billed). Cause: GUI binary instead of the CLI wrapper (§2). Fix: `Contents/Resources/bin` on PATH; 60 s smoke test `xtool --version` (step cap 2 min); `xtool dev build` under an outer `perl -e 'alarm shift; exec @ARGV' 540` timeout (macOS has no GNU `timeout`; verified on WSL: exit 142 when it fires), stdin `</dev/null`, step cap 10 min; job cap **15 min**; appex `__text`/`__swift5_entry` check. If the smoke test fails, a diagnostic `xcodebuild build -scheme Tabula-Package -destination 'generic/platform=iOS'` (scheme name RESEARCH-ONLY: Xcode's `<package>-Package` convention; `xcodebuild -list` is printed first) compiles the SwiftPM targets for evidence and the job still **fails** (both paths must stay green). Note: that run also used the pre-fix sources, which fail on xtool regardless (PhotosPickerItem, empty appex) | next CI run |
| macOS job caps | VERIFIED (static) | `timeout-minutes: 15` on `ios-xcodegen`, `ios-xtool-path`, `ios-simulator-screenshots`; `release-testflight` 30 (archive + export + upload; killing an upload midway is worse); validate.sh enforces the caps | — |
| XcodeGen embedded-binary validation | VERIFIED (CI) | run 37449454629 log: `Validate Embedded Binary TabulaWatch.app`, `Validate Embedded Binary TabulaWidgets.appex`, `Validate TabulaApp.app` | — |
| Action versions | VERIFIED | run 37449454629 warned `Node.js 20 is deprecated … actions/checkout@v4, actions/upload-artifact@v4`. Now `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1` and `actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` (both v7.0.1, `using: node24`, resolved via the GitHub API); validate.sh fails on any unpinned `uses:` | bump deliberately |
| (d) TestFlight release | BLOCKED | `workflow_dispatch`; `concurrency.cancel-in-progress` is false for manual runs, so a push cannot cancel an upload; secrets are mapped only into the steps that use them (the config check sees booleans only); skips with a notice if `ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_P8_BASE64 / vars.APPLE_TEAM_ID` are missing; archive with `-allowProvisioningUpdates -authenticationKeyPath/ID/IssuerID`, export (`method app-store-connect`, `destination export`), upload `xcrun altool --upload-app … --apiKey --apiIssuer` | H1, H7, H8 |
| Runner with Xcode 27 | VERIFIED | run 37449454629 log: `Image: xcode-27-arm64`, image version `20260928.0222.1`, `Xcode 27.0` / `Build version 27A266a`, SDKs `iOS 27.0 -sdk iphoneos27.0`, `watchOS 27.0 -sdk watchos27.0`, xcbeautify 3.2.1. Same Xcode build as the local SDK | switch to the GA label when announced |
| Upload method | RESEARCH-ONLY | Apple "Upload builds" (developer.apple.com/help/app-store-connect/manage-builds/upload-builds): Xcode, `xcrun altool --upload-app`, Transporter, App Store Connect API; iOS apps must be built with Xcode 26+. Chose export + altool because forum reports show `destination=upload` failing with API keys in some setups (developer.apple.com/forums/thread/742458) | — |
| API key role | RESEARCH-ONLY | cloud-managed distribution signing via `xcodebuild` needs an **Admin** key (developer.apple.com/forums/thread/698117); xtool docs ask for a Team Key with **App Manager** role | H7: two keys recommended (least privilege) |
| Cost | RESEARCH-ONLY | docs.github.com billing: standard runners **free for public repos**; private repos: GitHub Free 2,000 min/month, Pro 3,000; rates macOS `$0.062/min` vs Linux `$0.006/min` (~10×). Current docs bill in dollars and no longer state a minute multiplier — check the billing dashboard | decision D2 |

Supply-chain note: XcodeGen and xtool downloads are pinned by SHA-256; GitHub actions are pinned to commit SHAs (2026-10-06).

**Trigger matrix** (orchestrator cost decision 2026-10-06; private repo, macOS ≈ 10× Linux; enforced by validate.sh):

| Event / change | `core-linux` | `changes` (Linux) | `ios-xcodegen` + `ios-xtool-path` (macOS) | `release-testflight` (macOS) | `ios-simulator-screenshots` (macOS) |
|---|---|---|---|---|---|
| docs-only (`docs/**`, `**/*.md`, `examples/**`) | — (no workflow) | — | — | — | — |
| push/PR to main: TimetableCore **tests**, TimetableUI tests, `Probes/`, `spikes/`, other `scripts/` | ✓ | ✓ → app=false | — | — | — |
| push/PR to main: `Packages/TimetableCore/Sources/**` or `Package.swift`, `WatchApp/**`, `Config/**` (except App-Info.plist), `Package.swift`, `project.yml`, `xtool.yml`, `scripts/l10n-compile.py`, `scripts/identity.py`, `ios.yml` | ✓ | ✓ → app=true | ✓ | — | — |
| push to main: `App/**`, `WidgetExtension/**`, `Packages/TimetableUI/Sources/**`, `Resources/**`, `Config/App-Info.plist` | ✓ | ✓ → app=true | ✓ | — | ✓ |
| PR to main with the same app/UI changes | ✓ | ✓ → app=true | ✓ | — | — (never on PRs) |
| PR to another branch | — | — | — | — | — |
| manual "iOS CI" (`upload` default **false**) | ✓ | app=true | ✓ | only if `upload: true` (job-level `if`, no runner otherwise) | — |
| manual "UI screenshots" | — | — | — | — | ✓ |

App-relevant list = `scripts/ci_paths.py` (`--self-test`, 31 cases). Two documented deviations from the orchestrator's list, both only *reduce* or protect minutes: `Packages/TimetableUI/**` → `Sources/**` + `Package.swift` (TimetableUI tests are Linux-only, per "tests-only → no macOS job"); `scripts/identity.py` added (the macOS `ios-xcodegen` job executes it). No base commit (new branch, force push with a missing `before`) → app=true (safe default).

**Expected macOS minutes** (GitHub bills each job rounded **up** to whole minutes): app/UI push to main ≈ `ios-xcodegen` 2 (measured 1 m 07 s) + `ios-xtool-path` ~2–3 (estimate) + screenshots ~5–8 (estimate) ≈ **9–13 billed macOS min** (≈ $0.55–0.80 at $0.062/min beyond the allowance); core-sources/config push ≈ **4–5**; same change as PR + merge ≈ 4–5 + 9–13; tests/scripts-only push = **0** macOS (≈ 2–3 Linux min); worst case of a hung job = 15 (TestFlight 30). Measured so far: Linux 1 m 15 s, XcodeGen 1 m 07 s; the first xtool job burned 40 min (GUI binary, fixed). Private-repo notes: `docs/GITHUB_SETUP.md`.

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
10. ~~Known gap: in Phase 0 the debug screen *is* the app, so it ships in Release archives/TestFlight builds.~~ **Closed in Phase 2 Stage A (2026-10-09):** every file in `App/Sources/Debug/` is wrapped in `#if DEBUG` (validate.sh enforces it), the debug routes are registered only in DEBUG (`Routing/RouteRegistry.swift`), and Release ignores `-TabulaSeed`/`-TabulaNow`/`-TabulaTimeZone`. VERIFIED with `xtool dev build -c release`: 0 `DeveloperScreen` symbols. The CI screenshot job builds Debug, so it still sees the debug routes.
11. "Sourcing swiftly's env.sh once is enough": false in non-login shells (`wsl.exe -- bash -c`); `xtool sdk install` failed with `Could not find executable 'clang' in PATH`. Fixed: `scripts/lib/toolchain.sh` in every script (2026-10-06).
12. "xtool compiles what Xcode compiles": false for cross-import overlays (`PhotosPickerItem` not found): xtool's SwiftBuild toolset omits `-enable-cross-import-overlays`. Fixed in Package.swift.
13. "xtool packs a working widget appex": false with SwiftBuild + ld64.lld: the appex had no code, and zsign then failed with `Can't find free space of LoadCommands for CodeSignature!` (misleading message). Fixed with `-u _main`; guarded in xtool-dev.sh and CI.
14. "The Xcode 27 xip/SDK has no watchOS SDK" (orchestrator note 2026-10-06): false. `WatchOS27.0.sdk` is inside the bundle's `Xcode.app`; only xtool's swift-sdk triples omit it. That enabled the local watchOS type-check.
15. "A `.xcstrings` SwiftPM resource is copied raw by xtool": false for the iOS cross-build, which is a **hard build error**.
16. "Our shared Info.plist is warning-free in Xcode": false, `UIDeviceFamily` triggered an Xcode warning (removed).
17. "`xtool.app/Contents/MacOS/xtool` is the CLI" (Phase 0 workflow): false. It is the GUI app unless `XTL_CLI=1`; the CLI is `Contents/Resources/bin/xtool`. Cost: one CI run cancelled after 40 billed macOS minutes. Fixed, with 15-min caps on every macOS job.

## 12. API checks (Apple docs JSON, fetched 2026-10-04)

Base URL `https://developer.apple.com/tutorials/data/documentation/` + path + `.json`. Introduced versions as reported:
`swiftui/entry()` (macro; iOS 13 back-deployed) · `observation/observable()` iOS 17 · `swiftui/labeledcontent` · `swiftui/text/init(verbatim:)` · `swiftui/text/init(timerinterval:pausetime:countsdown:showshours:)` iOS 16 · `swiftui/view/containerbackground(_:for:)` iOS 17 · `swiftui/view/onappear(perform:)` · `swiftui/view/environment(_:_:)` · `swiftui/view/accessibilityelement(children:)` · `swiftui/view/accessibilitylabel(_:)-5f0zj` · `swiftui/view/accessibilityhidden(_:)` · `swiftui/view/foregroundstyle(_:)` · `swiftui/font/monospaced()` · `swiftui/view/textselection(_:)` (**not on watchOS → not used**) · `swiftui/image/init(systemname:)` · `swiftui/state` · `swiftui/environment` · `swiftui/environmentvalues` · `swiftui/list` · `swiftui/section` · `swiftui/button` · `swiftui/foreach` · `swiftui/navigationstack` · `swiftui/view/navigationtitle(_:)-5di1u` · `swiftui/app` · `swiftui/scene` · `swiftui/windowgroup` · `swiftui/widgetbundle` · `swiftui/widget` · `swiftui/widgetconfiguration/supportedfamilies(_:)` · `swiftui/widgetconfiguration/configurationdisplayname(_:)` · `swiftui/widgetconfiguration/description(_:)` · `swiftui/localizedstringkey` · `widgetkit/staticconfiguration` · `widgetkit/timelineprovider` (+ `placeholder(in:)`, `getsnapshot(in:completion:)`, `gettimeline(in:completion:)` with `@Sendable` completions) · `widgetkit/timeline/init(entries:policy:)` · `widgetkit/timelineentry` · `widgetkit/widgetcenter/reloadalltimelines()` · `widgetkit/widgetfamily` · `foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)` · `foundation/userdefaults/init(suitename:)` · `foundation/bundle/bundleidentifier` · `foundation/bundle/localizations` · `foundation/bundle/preferredlocalizations` · `foundation/locale/current` · `foundation/processinfo/operatingsystemversionstring` · `foundation/date/iso8601format(_:)` · `foundation/date/now` · `foundation/url/appending(path:directoryhint:)` · `foundation/localizedstringresource` · `swift/string/init(localized:table:bundle:locale:comment:)` iOS 15 · `uikit/uidevice/systemname` · `uikit/uidevice/systemversion` · `uikit/uidevice/model` · `appintents/appintent` (+ `title`, `description` = `IntentDescription?`, `perform()`; `openappwhenrun` **deprecated in 26 → not used**) · `appintents/intentdescription` · `appintents/intentdialog` · `appintents/intentresult/result(dialog:)` · `appintents/providesdialog` · `appintents/appshortcutsprovider` (+ `appshortcuts`) · `appintents/appshortcut/init(intent:phrases:shorttitle:systemimagename:)-8yntq` iOS 17 (the `-2hk1x` overload is deprecated) · `appintents/appshortcutphrase` · `foundationmodels/generable(description:)` iOS 26 / watchOS 27 · `foundationmodels/guide(description:)` · `foundationmodels/generable/generationschema` · `foundationmodels/systemlanguagemodel` (no watchOS) · `swiftdata/model()` · `swiftdata/query` · `swiftdata/modelcontext/insert(_:)` · `swiftui/environmentvalues/modelcontext` · `swiftui/scene/modelcontainer(for:inmemory:isautosaveenabled:isundoenabled:onsetup:)` · `alarmkit`, `alarmkit/alarmmanager`, `alarmkit/alarmmanager/requestauthorization()` iOS 26 · `bundleresources/entitlements/com.apple.security.application-groups` · `bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit` · `bundleresources/entitlements/com.apple.developer.icloud-container-identifiers` · `bundleresources/information-property-list/nsalarmkitusagedescription` iOS 26 · `…/nssupportsliveactivities` · `…/nscamerausagedescription` · `…/nsphotolibraryusagedescription` · `…/nsextension/nsextensionpointidentifier` · `…/wkapplication` · `…/wkcompanionappbundleidentifier` · `…/wkrunsindependentlyofcompanionapp` · `…/cfbundledisplayname`.
Added in rev. 2: `swiftui/environmentkey` · `swiftui/stateobject` iOS 14 · `combine/observableobject` · `combine/published` · `foundation/bundle/localizedstring(forkey:value:table:)` · `swift/string/init(format:locale:_:)` · `bundleresources/privacy-manifest-files` · `bundleresources/app-privacy-configuration/nsprivacytracking` · `…/nsprivacytrackingdomains` · `…/nsprivacycollecteddatatypes` · `…/nsprivacyaccessedapitypes` (+ `/nsprivacyaccessedapitype`, `/nsprivacyaccessedapitypereasons`) · `bundleresources/information-property-list/itsappusesnonexemptencryption`.
Not found as doc pages (404): `com.apple.developer.usernotifications.time-sensitive` entitlement page (capability exists in the portal table).

## 13. Isolated probes (`Probes/`)

Separate SwiftPM packages with their own `xtool.yml`, not referenced by `Package.swift`, `project.yml` or CI, so an expected failure cannot break the app. Delete after the Phase 0 gate.

| Probe | Question | Command (WSL) | Result 2026-10-06 |
|---|---|---|---|
| `MacroProbeSwiftData` | Do SwiftData `@Model`/`@Query` expand under xtool? | `bash scripts/probe-build.sh MacroProbeSwiftData` | **FAILED (exit 1)** as predicted: `external macro implementation type 'SwiftDataMacros.PersistentModelMacro' could not be found for macro 'Model()'; plugin for module 'SwiftDataMacros' not found`, `unknown attribute 'Query'` |
| `XCStringsSwiftPM` | Does SwiftBuild compile a catalog that is a SwiftPM resource, for iOS, on Linux? | `bash scripts/probe-build.sh XCStringsSwiftPM` | **FAILED (exit 1)**: build error, not a raw copy: `…/xtool/.xtool-tmp/xcstringstool … is not an executable file` |

Both questions are answered, so the probes can be deleted at the Phase 0 gate (orchestrator decision).

## 14. Human steps (numbered; nothing secret ever goes into chat)

Status 2026-10-06: **H2 done** (Xcode 27.0 27A266a xip supplied) · **H3 SDK part done** (`xtool sdk install`;
`xtool auth` login not done, not needed for builds) · **H6 done** (repo + gh CLI auth, `docs/GITHUB_SETUP.md`) ·
**H4/H5 deferred** (no device access; UI checks via CI simulator, §19) · **H1, H7, H8, H9 deferred** (paid account;
exact order and what each unblocks: `docs/PAID_ACCOUNT_SWITCHOVER.md`; H8 now also includes the GitHub
variable `TABULA_PAID_ACCOUNT`).

- **H1 — Apple Developer Program.** Decide individual vs organisation (organisation needs a D-U-N-S number; the seller name shown on the App Store differs) and enrol at https://developer.apple.com/programs/enroll/ (annual fee). Blocks: App Groups via xtool, CloudKit, Time Sensitive, TestFlight, IAP, increased memory limit.
- **H2 — Xcode 27 .xip.** In a browser: https://developer.apple.com/download/all/?q=Xcode → download **Xcode 27.0 (build 27A266a)** `.xip` — the exact version OpenAppleMacros tracks; a later 27.x may expand macros differently (Apple ID; accepting the Xcode and Apple SDKs Agreement — read §10 first). Then in WSL copy it to ext4: `cp /mnt/c/Users/simon/Downloads/Xcode_27*.xip ~/`
- **H3 — xtool setup (interactive, in your own WSL terminal).** `xtool setup` → login mode `0: API Key` (paid; Team Key, role App Manager; the key file stays on your machine) or `1: Password` (free Apple ID; consider a throwaway Apple ID) → path to the `.xip`. Verify: `xtool sdk status` (expect up to date) and `swift sdk list` (expect `darwin`). Disk ~7 GB (or `xtool sdk install --slim ~/Xcode_27*.xip`).
- **H4 — iPhone over USB.** Windows admin PowerShell: `winget install --interactive --exact dorssel.usbipd-win` → plug in the iPhone, unlock it → `usbipd list` (find the Apple device bus ID) → `usbipd bind --busid <BUSID>` → `usbipd attach --wsl --busid <BUSID>` (keep a WSL window open). In WSL: `idevice_id -l` then `idevicepair pair` and tap **Trust** on the phone. If the phone reconnects (after Trust/reboot) run `usbipd attach` again. Fallback: iTunes relay (§9).
- **H5 — First install.** `bash scripts/xtool-dev.sh` (WSL). On the iPhone enable Settings → Privacy & Security → **Developer Mode** (restart), and for a free account trust the profile under Settings → General → VPN & Device Management. Then run the on-device checklist (§15).
- **H6 — GitHub repo.** Create the repo (public = free macOS minutes; private = paid minutes, see §8; decision D2). The orchestrator commits/pushes only after your approval.
- **H7 — App Store Connect API keys.** App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys. Recommended: key **"CI"** with **Admin** role (cloud distribution signing) and key **"xtool"** with **App Manager** role (local). Download each `.p8` once.
- **H8 — GitHub secrets/variables** (repo → Settings → Secrets and variables → Actions): secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`; variable `APPLE_TEAM_ID`. To produce the base64 locally without printing it: PowerShell `[Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\Downloads\AuthKey_XXXXXXXXXX.p8")) | Set-Clipboard`, paste into the secret field, then clear the clipboard. Never paste keys into chat or commit them (`.gitignore` blocks `*.p8`).
- **H9 — App Store Connect app record.** My Apps → + → New App: platform iOS, bundle ID `sk.simondev.tabula` (register the explicit App IDs `sk.simondev.tabula`, `.TabulaWidgets`, `.watchkitapp` and App Group `group.sk.simondev.tabula` in Certificates, Identifiers & Profiles if automatic signing does not create them). Then run the workflow manually (Actions → iOS CI → Run workflow).

## 15. Phase 0 checklist: what is covered where (local compile / CI simulator / real device later)

Two build variants (macro isolation): **Step A** = base, `bash scripts/xtool-dev.sh [build]`; **Step B** = macro
variant, `bash scripts/xtool-dev.sh --macro-probes [build]`. Both **compile** (2026-10-06, 0 errors/0 warnings).
No device is available for now (human decision), so the columns say what each layer can prove:
**Local** = xtool compile/package on WSL (+ bundle inspection) · **CI sim** = `ui-screenshots.yml` on the iOS
Simulator (XcodeGen build = Apple's own macro plugins; screenshot per `-TabulaScreen` id, light/dark/AX-XXXL; launch
smoke test) · **Device** = later, after a device is available (xtool install) or via TestFlight (paid account).

| # | Check | Local (done) | CI sim (`-TabulaScreen …`) | Device (later) |
|---|---|---|---|---|
| 1 | App launches; title "Tabula · Phase 0 probes"; **Build path** row | compiles + packages (both variants) | launch smoke test + title + row shows `XcodeGen / xcodebuild` (`debug`) | row shows `xtool / SwiftPM` |
| 2 | **Bundle ID** row (`XTL-…` on xtool installs) | `CFBundleIdentifier sk.simondev.tabula` in bundle (rewritten only when xtool signs) | shows `sk.simondev.tabula` (`debug`) | record exact `XTL-…` |
| 3 | **App Group** round-trip (button) | entitlement embedded (ad-hoc) | not covered (needs a tap; unsigned sim build) | free team: Container URL FAIL expected; paid: 3× PASS |
| 4 | **Widget** in gallery + read-back | appex packaged with code (`__text`, `__swift5_entry`) | not covered (simctl cannot add widgets) | gallery name "Tabula probe", countdown, read-back row |
| 5 | **Localization** en/sk incl. Slovak plurals | `en.lproj`/`sk.lproj` `.strings` + `.stringsdict` present in app + widget | rows PASS/FAIL + sk line "1 hodina · 3 hodiny · 5 hodín" (`debug-localization`) | same on the xtool build (own catalog compiler) + switch phone to Slovak |
| 6 | **@Observable** tick | macro variant compiles (64 symbols) | row visible; tick needs a tap (`debug-macros`) | tap "Tick" (Step B) |
| 7 | **@Entry** value | compiles (OAM `SwiftUIMacros`) | `injected-by-DebugScreen` PASS (`debug-macros`) | Step B on the xtool build (OAM expansion at runtime) |
| 8 | **AppIntent** in-process + Shortcuts listing | compiles; xtool bundle has no `Metadata.appintents` | row visible; needs a tap (`debug-macros`) | tap + Shortcuts search (expect listed only on TestFlight) |
| 9 | **@Generable** schema text | compiles (118 symbols, schema calls) | schema text visible (`debug-macros`) | Step B on the xtool build |
| 10 | App icon | `AppIcon.png` + `CFBundleIconFile` (xtool); asset catalog (Xcode) | not visible in app screenshots | Home Screen |
| 11 | SwiftData / xcstrings probes | **done**: both FAILED as recorded in §13 | — | — |
| 12 | Import + AlarmKit sections | compile | static rows: OCR language flags, Foundation Models availability, AlarmKit authorization state (`debug-import`, `debug-alarms`) | photo OCR, alarms ringing, Silent/Focus matrix (`docs/spikes/*`) |
| 13 | Dark mode / Dynamic Type layout | — | light, dark and `accessibility-extra-extra-extra-large` screenshots of every id | VoiceOver pass |
| 14 | watch app | `scripts/watch-typecheck.sh` OK | optional `watch: true` input → watch simulator screenshot | Series 7 via TestFlight only |

Caveat: the CI simulator runs the **XcodeGen** build (Apple's macro plugins, Xcode-compiled catalog). The xtool-specific
runtime questions (OpenAppleMacros expansion at runtime, own `.lproj` tables, `XTL-` identifiers) stay device items,
or could use the locally built simulator `.app` (`--simulator`) on a hosted simulator (§19).

## 16. Proposed `Commands` section for CLAUDE.md (orchestrator to merge; not edited by me)

```
## Commands
- Linux validation (run before every commit): `bash scripts/validate.sh`            (inside WSL)
- Core tests: `bash scripts/core-test.sh`  (= swift test --package-path Packages/TimetableCore, ext4 scratch path)
- Local build: `bash scripts/xtool-dev.sh build`   · build+install+launch on iPhone: `bash scripts/xtool-dev.sh`
- Macro-probe variant (CLAUDE.md rule 5): `bash scripts/xtool-dev.sh --macro-probes [build]`
- iOS Simulator .app (local, no simulator to run it): `bash scripts/xtool-dev.sh --simulator`
- watchOS type-check (local, ~8 s): `bash scripts/watch-typecheck.sh`
- Identity values / paid switch: `python3 scripts/identity.py [--set TABULA_PAID_ACCOUNT=1] [NAME]`
- String Catalog compiler self-test: `python3 scripts/l10n-compile.py --self-test`
- Isolated probes: `bash scripts/probe-build.sh <MacroProbeSwiftData|XCStringsSwiftPM>`
- Regenerate Xcode project (CI does this): `xcodegen generate --spec project.yml` (no env needed any more)
- From Windows Git Bash: `MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu --exec bash -c 'cd "/mnt/c/Users/simon/Documents/Claude Code/school_timetable" && bash scripts/validate.sh'`
- CI: `.github/workflows/ios.yml` (TestFlight: Actions → iOS CI → Run workflow) · UI screenshots: `.github/workflows/ui-screenshots.yml`
- Open a screen directly: launch argument `-TabulaScreen <id>` (ids: the feature `*Routes.swift` files, registry `App/Sources/Routing/RouteRegistry.swift`); deterministic data `-TabulaSeed empty|blank|elementary|secondary|university`, fixed clock `-TabulaNow <ISO-8601>|live`, zone `-TabulaTimeZone <IANA id>` (DEBUG builds only, §19)
- Add UI strings: `python3 scripts/l10n-add.py KEY "English" "comment"` (or `--from file.json`); `--check` = canonical-form check (validate.sh runs it)
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

## 19. Simulator build & UI screenshots (replacement for device UI checks)

No physical device for now (human decision 2026-10-06). The Windows tools the human installed (VS 2022, Windows SDK,
Swift for Windows, Android Studio) cannot run iOS apps: the iOS Simulator exists only on macOS. So UI is checked
on GitHub's macOS runners.

| Item | Status | Evidence | Next step |
|---|---|---|---|
| Local simulator build (xtool) | VERIFIED (build) | `bash scripts/xtool-dev.sh --simulator` (= `xtool dev build --triple arm64-apple-ios-simulator` in `~/.cache/tabula/work-sim`) → `Build complete! (14.27 secs)` clean, 0 errors/0 warnings; app + appex are Mach-O **platform 7 (iOS Simulator)**, arm64, ad-hoc signed with the App Group entitlement. Caveat: xtool's packer still writes `CFBundleSupportedPlatforms = [iPhoneOS]`, and nothing here can run it | only useful for a hosted simulator or a Mac |
| Hosted simulator (Appetize) | RESEARCH-ONLY (no account) | docs.appetize.io (fetched 2026-10-06): iOS uploads must be a `.zip`/`.tar.gz` of a **simulator `.app`** (`.ipa` not supported), ARM simulator builds recommended; launch arguments via `launchArgs` (JSON array) reach `ProcessInfo.arguments`, so `-TabulaScreen` works; device table lists iPhone 17 Pro Max with iOS 26.0. Pricing/free tier not checked. Whether it accepts xtool's simulator build (`CFBundleSupportedPlatforms` mismatch) is unknown; the CI artifact `TabulaApp-iphonesimulator-<n>` (xcodebuild, zipped) is the safer upload | paid service = ask the human first (CLAUDE.md) |
| CI job `ios-simulator-screenshots` (`.github/workflows/ui-screenshots.yml`) | UNRUN on macOS (written; `bash -n` + structure checked; picker logic tested on sample `simctl` JSON; the create and screenshot steps dry-run on WSL with a stub `xcrun`: live app → 6 PNGs + job summary, simulated crash → exit 1 + per-shot crash logs. The dry run caught and fixed a bug: sourcing `SIM_NAME=iPhone 17 Pro Max` as shell) | `xcode-27` runner: logs `xcrun simctl list devicetypes` + `runtimes`; creates a fresh simulator of the **largest "Pro Max"** on the newest available iOS runtime (override input `device`); `xcodebuild build -destination "platform=iOS Simulator,id=…" CODE_SIGNING_ALLOWED=NO`; boots, fixes the status bar (9:41, full battery), installs; for every id in `screens` (default `debug debug-localization debug-macros debug-import debug-alarms`): `simctl launch … -TabulaScreen <id>`, 8 s, **fails if the process is gone** (crash on launch), `simctl io … screenshot` in `appearance light`, `appearance dark` and `content_size accessibility-extra-extra-extra-large`; optional `watch` input screenshots the watch app on the largest Apple Watch simulator; uploads PNGs + `log show` + build log | first run after the orchestrator pushes |
| Triggers / cost | VERIFIED (static, validate.sh enforces) | manual, or push to `main` touching only on-screen inputs: `App/**`, `WidgetExtension/**`, `Packages/TimetableUI/Sources/**` + `Package.swift`, `Resources/**`, `Config/App-Info.plist`, the workflow itself (not TimetableCore, not the rest of `Config/`, not TimetableUI tests); never on PRs; `cancel-in-progress`; `timeout-minutes: 15`; estimate 5–8 macOS minutes per run (billed rounded up per job). Full matrix: §8 | — |
| Simulator picker | VERIFIED (self-test) / FAILED as first written | qa-reviewer: `xcrun simctl list -j runtimes devicetypes` treats `devicetypes` as a **search term** → `"runtimes": []`. Now `xcrun simctl list -j` (full) + `scripts/sim_pick.py`; `--self-test` on a realistic full sample (devicetypes/runtimes/devices/pairs; iOS 26.4 + 27.0 + unavailable 27.2 with `availabilityError`; watchOS 26.4 + 27.0; tvOS) → 8/8: iOS 27.0 + iPhone 17 Pro Max, unavailable runtime ignored, override honoured, unknown override fails, watchOS 27.0 + Series 11 (46mm), empty-runtimes (old bug) fails loudly, partial JSON rejected, fallback without `supportedDeviceTypes` respects `minRuntimeVersion`. Runs in validate.sh; validate.sh fails on any `simctl list -j <word>` in the workflow | — |
| Launch-route registry (Phase 2 Stage A) | VERIFIED (Linux tests + iOS compile) / runtime UNRUN | `TimetableUI.RouteTable` + `LaunchOptions` (Linux tests), `App/Sources/Routing/{AppRoute,RouteRegistry}.swift`, one `*Routes.swift` provider per feature folder; validate.sh fails on duplicate/malformed ids. Unknown id → normal app shell; the developer screen (`-TabulaScreen debug-developer`) and the `debug` screen show `UNKNOWN "<id>"` | runtime proof = first CI screenshot |

**How the human views the screenshots:** github.com/simon01920/tabula-app-ios → **Actions** → "UI screenshots (iOS
Simulator)" → open a run → **Summary** lists device/runtime and every PNG → section **Artifacts** →
`ui-screenshots-<run number>` (zip: `screenshots/<id>-light|dark|ax-xxxl-text.png`, `logs/app.log`, build log;
kept 14 days). CLI: `gh run download <run id> -n ui-screenshots-<n>`. Manual run: Actions → the workflow → **Run
workflow** (choose `screens`, optional `device`, `watch`).

**How Phase 2 screens register (Stage A, 2026-10-09):** add `AppRoute("<feature>.<name>", <placement>) { View() }` to
your feature's provider (`Onboarding/OnboardingRoutes.swift`, `Today/TodayRoutes.swift`, `Timetable/TimetableRoutes.swift`,
`Editors/EditorRoutes.swift`, `Settings/SettingsRoutes.swift`); placements: `.tabRoot(tab)`, `.sheet(over: tab)`,
`.onboarding`, `.standalone`. Add the id to the workflow's `screens` list. Data-driven screens are captured with a seed:

| Launch argument (DEBUG builds only) | Effect |
|---|---|
| `-TabulaSeed empty` | in-memory store with nothing in it → onboarding |
| `-TabulaSeed blank` | onboarding finished (secondary preset), no subjects/lessons → empty states |
| `-TabulaSeed elementary` | ZŠ 3.A: 6×45 min bells, tiles, room change + cancelled lesson on the reference day |
| `-TabulaSeed secondary` | gymnázium 2.B: A/B weeks, short-day overrides on Thu 15 Oct, tasks, exams (= Tools/EngineDemo data) |
| `-TabulaSeed university` | FIIT 2nd year: free-form 90-min blocks, odd/even weeks, buildings, lecture/seminar/lab |
| `-TabulaNow <ISO-8601 with offset>` / `live` | only with `-TabulaSeed` (never the real store): fixed clock (default: Tue 2026-10-13 10:20 Europe/Bratislava) / real clock |
| `-TabulaTimeZone <IANA id>` | only with `-TabulaSeed`: device zone override (default: Europe/Bratislava) |

Example: `xcrun simctl launch booted sk.simondev.tabula -TabulaSeed secondary -TabulaScreen today -AppleLanguages "(sk)"`.
Release builds ignore every launch argument, `-TabulaScreen` included (Phase 2 decision P2-6, enforced in Phase 3 Stage A; `LaunchOptions` + tests). `-TabulaReminders live` (DEBUG, with a seed) switches the seed app from in-memory reminder clients to the real notification centre and AlarmKit.

**Custom screen sets:** Actions → "UI screenshots (iOS Simulator)" → Run workflow → `screens` = space-separated
`id[@seed[@lang]]` entries (route ids: any `AppRoute("…")` in `App/Sources/*/**Routes.swift`; seeds `empty|blank|elementary|secondary|university`; `lang` = `-AppleLanguages` code, e.g. `sk`, `de`, `ja`). Example: `editor.bell@university editor.terms@secondary@sk timetable.week@secondary@de`. The default set (workflow `SCREENS` and the dispatch input default, kept identical) covers onboarding, Today, the three timetable views, lesson detail, the lesson/subject/timetables editors, settings and two localised shots; pushes to `main` use the default. `debug` (and `debug-*`) can still be requested explicitly. Editors opened by route (no `EditorContext`) show seed data (first lesson/subject).

## 20. Paid-account placeholders (account deferred)

Full runbook: [`docs/PAID_ACCOUNT_SWITCHOVER.md`](PAID_ACCOUNT_SWITCHOVER.md). Variables list: `.env.example`.

| Item | Status | Evidence |
|---|---|---|
| Single source of identity | VERIFIED (static) | `Config/AppIdentity.xcconfig`: `TABULA_DEVELOPMENT_TEAM =` (empty placeholder), `TABULA_PAID_ACCOUNT = 0`, `TABULA_BUNDLE_ID_PREFIX = sk.simondev`, `TABULA_BUNDLE_ID = sk.simondev.tabula`, `TABULA_APP_GROUP = group.sk.simondev.tabula`, `TABULA_ICLOUD_CONTAINER = iCloud.sk.simondev.tabula`, `TABULA_SHARE_DOMAIN = tabula.simondev.sk`, entitlement selectors. Read by Xcode (project-level `configFiles`) and by `scripts/identity.py` (CI, validate). xtool.yml, `Config/*.entitlements`, `Watch-Info.plist` and `TimetableCore.AppGroup.canonicalIdentifier` keep literals, checked against it |
| Paid-only entitlements, not wired | VERIFIED (static) | `Config/Entitlements/PaidAccount/Tabula.entitlements`: App Group, `icloud-container-identifiers [$(TABULA_ICLOUD_CONTAINER)]`, `icloud-services [CloudKit]`, `aps-environment development` (CKSyncEngine docs: "requires the CloudKit and Remote notifications entitlements"), `usernotifications.time-sensitive` (key RESEARCH-ONLY, no Apple doc page), `kernel.increased-memory-limit`, `associated-domains [applinks:$(TABULA_SHARE_DOMAIN)]`; key formats checked against Apple's docs JSON 2026-10-06. Widget file: App Group only |
| One switch | VERIFIED (static) / Xcode resolution UNRUN | `TABULA_APP_ENTITLEMENTS = $(TABULA_APP_ENTITLEMENTS_$(TABULA_PAID_ACCOUNT))` (same for the widget); CI release job passes GitHub variables `APPLE_TEAM_ID` → `TABULA_DEVELOPMENT_TEAM` and `TABULA_PAID_ACCOUNT` (default 0) to `xcodebuild`. `ios-xcodegen` asserts both switch states + team override with `-showBuildSettings` |
| Guard (switch off ⇒ no paid entitlement anywhere) | VERIFIED | `validate.sh` 123 OK. Negative tests on a throwaway copy, each produced the intended FAIL: switch committed ON; paid key added to `Config/Tabula.entitlements`; xtool.yml pointed at PaidAccount; project.yml hard-coding the paid file; bundle-ID drift xtool.yml vs xcconfig; a value in `.env.example`; undefined `$(VAR)` in a paid file; project.yml shadowing `TABULA_PAID_ACCOUNT` |

## 21. Reminder adapter (Phase 3 Stage A, notifications-engineer, 2026-10-10)

Apple docs read as DocC JSON (`developer.apple.com/tutorials/data/documentation/<path>.json`) on 2026-10-10. Code:
`Packages/TimetableUI/Sources/TimetableUI/Reminders/` (pure, Linux-tested) and `App/Sources/Reminders/` (thin live
clients). Device behaviour: `docs/checklists/PHASE3_DEVICE.md` §A.

| Fact | Status | Source / evidence |
|---|---|---|
| `BGTaskScheduler.submit(_:)` is iOS 13–26, **deprecated in iOS 27.0**; replacement `submitTaskRequest(_:) async throws` / `(_:completionHandler:)` is **iOS 27.0+** ("do not call from the main thread"). One pending refresh request per app (a new submit replaces it); errors `notPermitted`, `tooManyPendingTaskRequests`, `unavailable`, `immediateRunIneligible` | VERIFIED (docs) + COMPILED (`#available(iOS 27)` branch, 0 warnings) | [submit(_:)](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/submit(_:)), [submitTaskRequest](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/submittaskrequest(_:completionhandler:)) |
| `register(forTaskWithIdentifier:…)` returns false unless the id is in `BGTaskSchedulerPermittedIdentifiers`; must finish before the end of launch; **registering the same id twice kills the app** | VERIFIED (docs) | [register](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:)). We use SwiftUI `Scene.backgroundTask(.appRefresh(id))` (iOS 16; "the system considers the task completed when the action closure returns"), which registers it — never call `register` ourselves |
| App refresh tasks need `UIBackgroundModes` = `fetch`; `earliestBeginDate` only guarantees "not sooner" | VERIFIED (docs) | [BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask), [earliestBeginDate](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate). Keys in `Config/App-Info.plist` (shared by xtool + XcodeGen; `validate_config.py` checks id == `BackgroundRefreshPolicy.taskIdentifier`) |
| `backgroundRefreshStatus`: don't warn when `.restricted`; Background App Refresh is **disabled automatically in Low Power Mode** | VERIFIED (docs) | [backgroundRefreshStatus](https://developer.apple.com/documentation/uikit/uiapplication/backgroundrefreshstatus); `ProcessInfo.isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChange` |
| `UNUserNotificationCenter.delegate` must be set before the app finishes launching (`willFinishLaunching`/`didFinishLaunching`) | VERIFIED (docs) | [delegate](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/delegate). Done in `TabulaAppDelegate` (`UIApplicationDelegateAdaptor`), which owns `AppServices` |
| Delegate callbacks: completion handlers are `@Sendable`; without `willPresent` the system shows nothing in the foreground | VERIFIED (docs) + COMPILED (nonisolated implementations, Swift 6) | [didReceive](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter(_:didreceive:withcompletionhandler:)), [willPresent](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter(_:willpresent:withcompletionhandler:)) |
| `setNotificationCategories` replaces all categories; `UNNotificationAction(identifier:title:options:icon:)` + `UNNotificationActionIcon(systemImageName:)` are iOS 15 | VERIFIED (docs) | [setNotificationCategories](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/setnotificationcategories(_:)), [action init](https://developer.apple.com/documentation/usernotifications/unnotificationaction/init(identifier:title:options:icon:)) |
| `requestAuthorization`: "Request only the authorization options that you plan to use" → we request `[.alert, .sound]` | VERIFIED (docs) | [requestAuthorization](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:)) |
| **`UNCalendarNotificationTrigger` time-zone semantics are NOT documented** (neither the class, `init(dateMatching:repeats:)`, `dateComponents` nor the local-notification article mention `DateComponents.timeZone`) | UNDOCUMENTED → decision | Decision: components year…second + explicit Gregorian `calendar` + `timeZone` = plan zone ⇒ one absolute instant; wall-clock times that occur twice (DST fall-back) use `UNTimeIntervalNotificationTrigger` for the exact interval. Re-plan on every zone change re-maps (same planner ids). Device rows A6.2/A6.4 |
| `userInfo` keys/values must be plist types; `removePendingNotificationRequests` runs asynchronously; `removeDeliveredNotifications` ignores ids not displayed | VERIFIED (docs) | [userInfo](https://developer.apple.com/documentation/usernotifications/unmutablenotificationcontent/userinfo), [removePending](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/removependingnotificationrequests(withidentifiers:)) |
| `UIApplication.openNotificationSettingsURLString` (iOS 16) deep-links to the app's notification settings | VERIFIED (docs) | [openNotificationSettingsURLString](https://developer.apple.com/documentation/uikit/uiapplication/opennotificationsettingsurlstring) (health check action for B4) |
| AlarmKit (re-checked): `alarms` = this client's alarms, one-shot alarms disappear after firing + stopping ("persist your alarms in your own store"); `maximumLimitReached` = "A maximum number of alarms is already scheduled" (no number); `authorizationUpdates` exists (initial emission not documented) | VERIFIED (docs) | [alarms](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarms), [maximumLimitReached](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmerror/maximumlimitreached). Hence: alarm **ledger** written before scheduling; learned soft limit (24 h) after a refusal, overflow → Time Sensitive notifications (planner `alarmOverflow`) |
| `Alarm.state` (`.scheduled`, `.alerting`, `.countdown` = snoozed, `.paused`) is read with `alarms`; ringing/snoozed/paused alarms are never cancelled by a re-plan (only when their item closed) | VERIFIED (docs, ALARMKIT.md §2.3) + COMPILED | `LiveAlarmClient.scheduledAlarms()`, `ReminderApplyOperations` |
| **Alarm-count limit**: still undocumented and dynamic (Phase 0 F5); the app imposes a soft limit of **10** loud alarms per plan and learns a lower one from `maximumLimitReached` | RESEARCH-ONLY → device A7.6 (+ probe F1/F2) | Record the measured N here after the device run |
| Snooze on loud alarms = `secondaryButtonBehavior: .countdown` + `postAlert` **9 min** (iOS Clock default; product choice), needs the TabulaWidgets Live Activity, which now renders `AlarmAttributes<TabulaAlarmMetadata>` (shared with the DEBUG probes) | COMPILED (xtool base + macro), device A4.9 | `LiveAlarmClient.swift`, `WidgetExtension/Sources/AlarmLiveActivity.swift` |
| Build evidence | VERIFIED | `validate.sh` ALL CHECKS PASSED (TimetableUI 218 tests incl. 42 reminder-adapter tests; QA fix pass: in-progress alarms kept, due notifications kept, render signature, dynamic reserve), `xtool-dev.sh build` and `--macro-probes build`: 0 errors / 0 warnings, watchOS type-check OK |

## 22. Failed assumption: exit codes through `wsl.exe --` (found 2026-10-11)
`wsl.exe -d Ubuntu -- bash -lc '…; echo $?'` runs the command line through the WSL user's login shell **first**. That shell expands `$?` and `$VAR` before the inner `bash` runs, so exit codes print as 0.

Verified:
- `wsl.exe -d Ubuntu -- bash -lc 'bash -c "exit 3"; echo $?'` prints `0`.
- With `--exec` instead of `--` it prints `3`.

Consequences:
- Every "EXIT=…" value printed in orchestrator or agent logs through `--` before this date is meaningless.
- Gate verdicts were based on the scripts' own `ALL CHECKS PASSED` / `N CHECK(S) FAILED` summary lines, which are unaffected.
- **Always use `wsl.exe -d Ubuntu --exec bash -lc '…'`** (CLAUDE.md Commands updated).

## 23. Attachments (Phase 3 stage B3, sync-storage-engineer, 2026-10-14)

Apple docs read as DocC JSON (`developer.apple.com/tutorials/data/documentation/<path>.json`) on 2026-10-10/14. Code:
`Packages/TimetableUI/Sources/TimetableUI/Attachments/` (pure Foundation store + rules, Linux-tested on temp dirs) and
`App/Sources/Attachments/` (UI, audio). Device behaviour: `docs/checklists/PHASE3_DEVICE.md` §B3.

| Fact | Status | Source / evidence |
|---|---|---|
| `PhotosPickerItem.loadTransferable(type:) async throws -> sending T?` (iOS 16); `supportedContentTypes` = types "in order of the most preferred"; modifier `photosPicker(isPresented:selection:matching:preferredItemEncoding:)` (iOS 16) | VERIFIED (docs) + COMPILED | [loadTransferable](https://developer.apple.com/documentation/photosui/photospickeritem/loadtransferable(type:)), [supportedContentTypes](https://developer.apple.com/documentation/photosui/photospickeritem/supportedcontenttypes), [photosPicker](https://developer.apple.com/documentation/swiftui/view/photospicker(ispresented:selection:matching:preferreditemencoding:)). Needs the cross-import overlay flag (RISKS #41), already in `Package.swift` |
| `fileImporter(isPresented:allowedContentTypes:allowsMultipleSelection:onCompletion:)` (iOS 14) returns **security-scoped URLs**: call `startAccessingSecurityScopedResource()` before reading and `stopAccessingSecurityScopedResource()` after; on cancel `onCompletion` is not called | VERIFIED (docs) + COMPILED | [fileImporter](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:)), [startAccessingSecurityScopedResource](https://developer.apple.com/documentation/foundation/url/startaccessingsecurityscopedresource()). We copy inside the access window and keep no bookmark. No `NSFileCoordinator` (device row B3.3 checks a not-yet-downloaded iCloud Drive file) |
| `AVAudioApplication.shared.recordPermission` + `AVAudioApplication.requestRecordPermission(completionHandler:)` (iOS 17, handler `@Sendable (Bool)`); a denial can only be changed in Settings | VERIFIED (docs) + COMPILED | [requestRecordPermission](https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission(completionhandler:)), [recordPermission](https://developer.apple.com/documentation/avfaudio/avaudioapplication/recordpermission-swift.property). Asked only on the first tap of Record; `NSMicrophoneUsageDescription` (English placeholder, not localized yet like the other usage strings) in `Config/App-Info.plist` |
| `AVAudioRecorder` (iOS 3, not deprecated in the current docs), `AVAudioSession.Category.playAndRecord`, `AVAudioPlayer` | VERIFIED (docs) + COMPILED | [AVAudioRecorder](https://developer.apple.com/documentation/avfaudio/avaudiorecorder), [playAndRecord](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord), [AVAudioPlayer](https://developer.apple.com/documentation/avfaudio/avaudioplayer). AAC mono 44.1 kHz `.m4a`, max 10 min (`record(forDuration:)`) |
| `quickLookPreview(_ item: Binding<URL?>)` (iOS 14) | VERIFIED (docs) + COMPILED | [quickLookPreview](https://developer.apple.com/documentation/swiftui/view/quicklookpreview(_:)) (`import QuickLook`) |
| `CGImageSourceCreateThumbnailAtIndex` + `kCGImageSourceThumbnailMaxPixelSize` (iOS 4) for downsampled thumbnails | VERIFIED (docs) + COMPILED | [thumbnail](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)), [max pixel size](https://developer.apple.com/documentation/imageio/kcgimagesourcethumbnailmaxpixelsize) |
| `FileProtectionType.completeUntilFirstUserAuthentication` (iOS 5) on attachment folders/files (readable by background refresh after the first unlock) | VERIFIED (docs) + COMPILED (`#if os(iOS) \|\| os(watchOS)`; no-op on Linux) | [completeUntilFirstUserAuthentication](https://developer.apple.com/documentation/foundation/fileprotectiontype/completeuntilfirstuserauthentication) |
| Backup: `isExcludedFromBackup` "is only useful for excluding cache and other application support files which are not needed in a backup"; only `tmp/` and `Library/Caches` are excluded by default | VERIFIED (docs) → decision | [isExcludedFromBackup](https://developer.apple.com/documentation/foundation/urlresourcevalues/isexcludedfrombackup), [Optimizing your app's data for iCloud backup](https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup). Attachments are user data, so they are **not excluded**. Whether App Group containers are part of device backups is not stated on these pages → device row B3.17 |
| Linux swift-corelibs: `FileManager.copyItem/moveItem/attributesOfItem/setAttributes(.modificationDate)/createSymbolicLink`, `precomposedStringWithCanonicalMapping`, `Unicode.Scalar.Properties.generalCategory` behave as on Apple platforms for these uses; `attributesOfItem` does not follow a final symlink (`fileExists(atPath:isDirectory:)` does) | VERIFIED (Linux tests) | `AttachmentStoreTests.swift` (29 tests) |
| `AVAudioSession.interruptionNotification` is posted **on the main thread**; `AVAudioRecorderDelegate.audioRecorderDidFinishRecording(_:successfully:)` fires when recording "stops or finishes due to reaching its time limit" | VERIFIED (docs) + COMPILED | [interruptionNotification](https://developer.apple.com/documentation/avfaudio/avaudiosession/interruptionnotification), [didFinishRecording](https://developer.apple.com/documentation/avfaudio/avaudiorecorderdelegate/audiorecorderdidfinishrecording(_:successfully:)). Interruption `.began` or the 600 s cap stops and finalises the recording (kept, reason shown) |
| `interactiveDismissDisabled(_:)` (iOS 15) may be applied to any view in the sheet; the docs do not say how conflicting values combine | VERIFIED (docs) → decision | [interactiveDismissDisabled](https://developer.apple.com/documentation/swiftui/view/interactivedismissdisabled(_:)). So the in-flight state is passed into `EditorScaffold(isBusy:)`, which applies one combined `isDirty \|\| isBusy` (no competing modifiers) |
| Spec vs code: PHASE3_PLAN §0.7 names the quota `limit(.attachmentBytes)`; the code has `Limit.attachmentQuotaMB` (10⁶ bytes). Used as is, no core change | NOTE | `AttachmentQuota(entitlements:)` |

**Storage layout:** `<store directory>/Attachments/<ATTACHMENT-UUID>/<sanitized name>` (store directory = App Group
`Tabula/` or the Application Support fallback, next to `tabula.json`); staging in `Attachments/.staging/<random>/`,
renamed into place. Seed runs (`-TabulaSeed`) use `tmp/TabulaSeedAttachments`.

## 24. Phase 3 final QA fixes (2026-10-15)
| Fact / assumption | Status | Source / evidence |
|---|---|---|
| `UIViewController.presentedViewController` (iOS 5): "The view controller that is presented by this view controller, or one of its ancestors in the view controller hierarchy"; nil when nothing was presented modally | VERIFIED (docs) + COMPILED | [presentedViewController](https://developer.apple.com/documentation/uikit/uiviewcontroller/presentedviewcontroller). Used read-only by `WindowPresentationProbe` (RootPresentation.swift) to know whether a SwiftUI sheet/alert/Quick Look is up. That SwiftUI sheets presented from a tab's content always show up on the window root's `presentedViewController` is **not documented** → device rows Q6.1–Q6.7 |
| `onChange(of:initial:_:)` with a zero-parameter action (iOS 17) | VERIFIED (docs) + COMPILED | [onChange(of:initial:_:)](https://developer.apple.com/documentation/swiftui/view/onchange(of:initial:_:)-8wgw9) |
| Failed assumption: Windows Python `write_text` / text-mode writes produce **CRLF**; `scripts/l10n-add.py --check` (run by validate.sh in WSL) then fails. Run the l10n scripts inside WSL (via a script file: PowerShell 5.1 strips the inner double quotes of `bash -lc '…"path with spaces"…'`) | FACT (observed) | this fix pass |
| Git inside WSL cannot use a worktree created by Windows git (`.git` file points to a `C:/…` gitdir) → run git from Windows, builds/tests from WSL | FACT (observed) | this fix pass |

## 25. Phase 3 polish (2026-10-15)
| Fact / assumption | Status | Source / evidence |
|---|---|---|
| Failed assumption (C2, §6 row "Localised Info.plist strings, xtool path"): "xtool.yml already copies whole `<lang>.lproj` dirs, so no xtool.yml change". The widget appex listed the same `.build-l10n/<lang>.lproj` dirs, so on the xtool path it also received the app's `InfoPlist.strings` (`CFBundleDisplayName = "Tabula"` overriding "Tabula Widgets", plus the camera/microphone/photo/AlarmKit texts), while `project.yml` adds `InfoPlist.xcstrings` to the app only | FIXED + VERIFIED (build) | Widget resources now come from `.build-l10n/widget/<lang>.lproj`, a second Localizable-only `l10n-compile.py` run in `scripts/xtool-dev.sh` and the ios.yml xtool job (xtool copies a resource dir by its name, so it still lands as `<lang>.lproj`). `xtool-dev.sh` packages into a fresh `TabulaApp.app` (old layouts cannot linger) and exits 4 if the widget has any `InfoPlist.strings`; ios.yml fails the same way; `validate_config.py` checks both paths. `TABULA_WORKDIR=/root/.cache/tabula/polish-work bash scripts/xtool-dev.sh build` → `Build complete! (31.40 secs)`, 0 warnings, `InfoPlist.strings in TabulaApp.app: 13 files`, `… TabulaWidgets.appex: 0 files`, widget `en.lproj` = `Localizable.strings` + `.stringsdict` |
| SwiftUI `.sheet(item:)`: setting the binding does not prove the sheet is on screen (a presentation can fail when another sheet starts presenting in the same moment; SwiftUI then logs and keeps the binding set) | ASSUMPTION (not documented) → defended | The shell's root sheet state now comes from its content's `onAppear`/`onDisappear` (`AppNavigation.visibleRootSheet`); a root sheet not appeared 2 s after it was set (`RootPresentationPolicy.appearTimeout`) is cleared and its link / offer queued again with the original request time. Device row Q6.11 |

## 26. CI flake: `swift-package` segfault (2026-10-14)
- **Observed:** iOS CI run 38600687712 (Linux job, Swift 6.4) failed in `validate.sh`: `swift test Packages/TimetableUI` exited because **`/usr/bin/swift-package` itself segfaulted** (crash frame in `libdispatch.so`). It was not a test failure; no test had reported a failure.
- **Verified:** the job was rerun on the same commit `b854087` and passed. Local WSL and QA runs of the same tree passed every time. This is classified as a toolchain flake.
- **Action if it recurs:** add a single retry around the Linux `swift test` step in `ios.yml`, and record it in RISKS.

## 27. Phase 4 Stage A — widget snapshot, *Now & Next* (widgets-watch-engineer, 2026-10-16)
| Fact / assumption | Status | Source / evidence |
|---|---|---|
| `widgetURL(_:)` (iOS 14, watchOS 9): one per hierarchy, "if multiple views have `widgetURL` modifiers, the behavior is undefined" | VERIFIED (docs) + COMPILED | https://developer.apple.com/documentation/swiftui/view/widgeturl(_:) |
| Widget / Live Activity taps: "the system activates the containing app and passes the URL to `onOpenURL(perform:)` … depending on the life cycle"; `Link` works in `accessoryRectangular`, `systemSmall` and larger | VERIFIED (docs) + COMPILED | https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity . The article does **not** say whether the URL scheme must be registered (`CFBundleURLTypes`); `tabula://` is not registered → device rows A1.2 / A3.8, RISKS #63 |
| Reload budget: "typically includes from 40 to 70 refreshes" per widget per day; reloads do not count while "the widget's containing app is in the foreground", on a system locale change or a Dynamic Type change; "timeline entries that are at least about 5 minutes apart"; policies `.atEnd` / `.after(_:)` / `.never` | VERIFIED (docs) | https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date . Nothing about time-zone or significant-time changes → RISKS #64 |
| `Text(timerInterval:pauseTime:countsDown:showsHours:)` iOS 16 / watchOS 9; in a widget it "becomes horizontally flexible", so it gets a frame | VERIFIED (docs) + COMPILED | https://developer.apple.com/documentation/swiftui/text/init(timerinterval:pausetime:countsdown:showshours:) |
| `ProgressView(timerInterval:countsDown:label:currentValueLabel:)` iOS 16 / watchOS 9; "Date-relative progress views … don't support custom styles" (accessoryCircular uses the built-in `.circular`; whether it draws a live ring is a device check, RISKS #65) | VERIFIED (docs) + COMPILED | https://developer.apple.com/documentation/swiftui/progressview/init(timerinterval:countsdown:label:currentvaluelabel:) |
| `WidgetRenderingMode` `.fullColor` / `.accented` / `.vibrant` (iOS 16, watchOS 9) via `@Environment(\.widgetRenderingMode)`; vibrant = iPhone Lock Screen | VERIFIED (docs) + COMPILED | https://developer.apple.com/documentation/widgetkit/widgetrenderingmode . Read-only, so the app's gallery cannot show accented/vibrant (device rows A3.x) |
| `widgetAccentable(_:)` iOS 16 / watchOS 9; `showsWidgetContainerBackground` iOS 15 / watchOS 8; `containerBackground(_:for:)` iOS 17 / watchOS 10 | VERIFIED (docs) + COMPILED | https://developer.apple.com/documentation/swiftui/view/widgetaccentable(_:) · https://developer.apple.com/documentation/swiftui/environmentvalues/showswidgetcontainerbackground · https://developer.apple.com/documentation/swiftui/view/containerbackground(_:for:) |
| HIG widget sizes: no 440×956 row; closest 430×932 → small 170×170, medium 364×170, large 364×382, circular 76×76, rectangular 172×76, inline 257×26 pt; StandBy shows two small widgets scaled up with the background removed | VERIFIED (docs) | https://developer.apple.com/design/human-interface-guidelines/widgets (the gallery uses the 430×932 sizes) |
| Failed assumption: `Text + Text` for "Math · 12:34" — **deprecated in iOS 26** (xtool warning "Use string interpolation on `Text` instead") | FIXED + VERIFIED (build) | `NowNextInlineView` uses the catalog key `widget.nowNext.inline.current %@ %@` (`"%1$@ · %2$@"`) with the timer `Text` interpolated |
| Failed assumption: a `switch` over `WidgetFamily` with `@unknown default` is warning-free — the iOS 27 SDK adds `systemExtraLargePortrait` (`@available(iOS 27.0)`) and the watch-only `accessoryCorner` (`@available(iOS, unavailable)`), so it warns "switch must be exhaustive" | FIXED + VERIFIED (build) | SDK `WidgetKit.swiftmodule/arm64e-apple-ios.swiftinterface`; `NowNextEntryView.kind(of:)` maps by equality |
| Shared widget views live in **TimetableUI** (`Widgets/NowNextWidgetViews.swift`, `#if canImport(SwiftUI) && canImport(WidgetKit)`): app and extension already link TimetableUI on both build paths, so `Package.swift` / `xtool.yml` / `project.yml` needed no change; the watch type-check compiles them for watchOS (Phase 5 can reuse them) | VERIFIED (compile: xtool iOS + watchOS type-check) | `watchOS type-check OK (arm64_32-apple-watchos26.0)`; xtool `Build complete!`, 0 warnings, widget appex check OK |
| Widget snapshot sizes (JSON, sorted keys) at Tue 2026-10-13 10:20: secondary 7 508 B, elementary 5 145 B, university 3 230 B; asserted < 20 000 B on three dates per scenario | VERIFIED (Linux test) | `WidgetSnapshotStoreTests.encodedSnapshotStaysSmall` |
| The widget state at every 5-minute instant across the covered days equals the Today header (`TodayState.make`) for secondary (Tue, Fri→Mon, holiday), university and elementary (cancelled day) | VERIFIED (Linux test) | `WidgetTimelinePlannerTests.stateMatchesTheTodayTab` |
| Widget language: strings are rendered with a lookup in the app's language (`<lang>.lproj` of the appex, from the snapshot's `languageCode`); the gallery name/description and the inline format key use the system language | DESIGN (device row A2.14) | `WidgetSnapshotReader.lookup(language:)` |
| Git inside WSL still cannot use this worktree (`fatal: not a git repository … C:/…/.git/worktrees/…`); validate.sh does not need git | FACT (observed, again) | this stage |
