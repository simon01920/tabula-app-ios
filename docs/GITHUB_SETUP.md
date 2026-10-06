# GitHub setup: push access, Actions, minutes

Repo: `simon01920/tabula-app-ios` (**private**). Owner of this doc: env-ci-engineer. Last updated 2026-10-06.

## Status

| Item | State |
|---|---|
| Auth on this PC | **DONE 2026-10-06, option (a)**: the human installed GitHub CLI (`C:\Program Files\GitHub CLI\gh.exe`), ran `gh auth login` (account `simon01920`, HTTPS, keyring) and `gh auth setup-git` |
| `origin` | switched to `https://github.com/simon01920/tabula-app-ios.git` by the orchestrator |
| First push | `main` with commits `b2c0458` (Phase 0) and `1b4ad59` (Phase 1 plan) |
| First CI run | the push did not auto-trigger (new repo); dispatched manually: run **37449454629** (`gh workflow run "iOS CI" -f upload=false`) |
| Who pushes | only the orchestrator, after human approval. Subagents use `gh` **read-only** (`gh run view`, `gh run view --log-failed`) |

Option (b) below is kept as reference (for example for a second machine). Never generate or paste keys or tokens into chat.

## Option (a): GitHub CLI over HTTPS (used)

PowerShell (normal user):

```powershell
winget install --id GitHub.cli --exact          # installs gh.exe to C:\Program Files\GitHub CLI\
# open a NEW terminal so PATH picks it up
gh auth login --hostname github.com --git-protocol https --web
#   -> one-time code shown in the terminal, browser opens github.com/login/device, approve
gh auth setup-git                               # makes git use gh as credential helper
gh auth status                                  # expect: Logged in to github.com account simon01920
```

Point the existing clone at HTTPS (it was created with an SSH URL):

```powershell
cd "C:\Users\simon\Documents\Claude Code\school_timetable"
git remote set-url origin https://github.com/simon01920/tabula-app-ios.git
git remote -v
```

Inside WSL the Windows credential helper is not visible. Either push from Windows (recommended; the repo lives
on the Windows drive anyway) or run `gh auth login` again inside WSL after `sudo apt-get install gh`.

## Option (b): SSH key (reference)

PowerShell (normal user). The key is created on your machine only; only the `.pub` file is ever shared:

```powershell
ssh-keygen -t ed25519 -C "simon01920@tabula-pc" -f "$HOME\.ssh\id_ed25519"   # choose a passphrase
Get-Service ssh-agent | Set-Service -StartupType Automatic; Start-Service ssh-agent   # admin PowerShell
ssh-add "$HOME\.ssh\id_ed25519"
Get-Content "$HOME\.ssh\id_ed25519.pub" | Set-Clipboard
```

Then in the browser: https://github.com/settings/keys, **New SSH key**, title `tabula-pc`, type
*Authentication Key*, paste, save. Verify and switch the remote:

```powershell
ssh -T git@github.com            # expect: "Hi simon01920! You've successfully authenticated…"
git remote set-url origin git@github.com:simon01920/tabula-app-ios.git
```

## Verify (either option)

```powershell
git ls-remote origin             # prints refs (HEAD, refs/heads/main) without asking for credentials
git fetch origin && git status   # "Your branch is up to date with 'origin/main'"
```

## Actions

- **Enable:** repo → Settings → Actions → General. Already enabled (run 37449454629 ran). The strictest
  setting that works is "Allow actions created by GitHub": the only `uses:` are `actions/checkout` and
  `actions/upload-artifact` (pinned to commit SHAs); XcodeGen and xtool are plain `curl` downloads checked by
  SHA-256. Workflow permissions: "Read repository contents" (the workflows declare `permissions: contents: read`).
- **Workflows:** `.github/workflows/ios.yml` ("iOS CI": Linux tests/validation, XcodeGen build, xtool build,
  manual TestFlight job) and `.github/workflows/ui-screenshots.yml` ("UI screenshots (iOS Simulator)").
- **Run manually:** Actions → workflow → "Run workflow", or `gh workflow run "iOS CI" -f upload=false` /
  `gh workflow run "UI screenshots (iOS Simulator)" -f screens="debug" -f watch=false`.
- **Read results:** `gh run list --limit 5`, `gh run view <id>`, `gh run view <id> --log-failed`;
  screenshots: run page → **Artifacts** → `ui-screenshots-<n>` (or `gh run download <id> -n ui-screenshots-<n>`).
- **Variables / secrets for the paid account:** none needed today. See `docs/PAID_ACCOUNT_SWITCHOVER.md`.

## Minutes and cost (private repo)

- GitHub-hosted runners are free for public repos only. Private repos get a monthly allowance (GitHub Free:
  2,000 minutes, Pro: 3,000) and macOS minutes cost about **10×** Linux minutes (`$0.062` vs `$0.006` per
  minute in the current billing docs; check Settings → Billing for the live numbers and set a **spending
  limit**, which defaults to $0 for accounts without a payment method, so runs simply stop when the allowance
  is used up).
- Measured on run 37449454629: Linux job 1 m 15 s, XcodeGen macOS job 1 m 07 s. The xtool macOS job was
  cancelled after 40 billed minutes because the workflow started xtool's GUI binary instead of its CLI
  wrapper (fixed; `docs/ENVIRONMENT.md` §2). Every macOS job is now capped at 15 minutes (TestFlight 30).
- Guards in the workflows: `paths-ignore` for docs-only commits (iOS CI), path filters + no PR trigger
  (screenshots), `concurrency` cancel-in-progress, per-job `timeout-minutes`, TestFlight job manual only.
