# Third-party Claude Code components

## everything-claude-code (ECC)
- Source: https://github.com/affaan-m/everything-claude-code, commit `90606c8` (2026-10-20).
- Licence: MIT, Copyright (c) 2026 Affaan Mustafa. The full text is in the source repo's `LICENSE`, and a copy is at `~/.claude/ECC-LICENSE.txt` on the dev PC.
- Installed 2026-10-23 at the human's request. The orchestrator read each file before installing it; no hooks, scripts or MCP servers were installed.

| Component | Where | Local change |
|---|---|---|
| agents `swift-reviewer`, `swift-build-resolver`, `a11y-architect` | `.claude/agents/` | Added a "Tabula project override" note after the frontmatter (WSL commands; CLAUDE.md rules win) |
| skills `swiftui-patterns`, `swift-concurrency-6-2`, `swift-actor-persistence`, `swift-protocol-di-testing`, `liquid-glass-design`, `accessibility` | `.claude/skills/` | none |
| agents `silent-failure-hunter`, `pr-test-analyzer`, `type-design-analyzer`, `comment-analyzer`; skill `verification-loop` | user level, `~/.claude/` (not in this repo) | none |

### Skipped, and why
| Component | Reason |
|---|---|
| hooks | They auto-run Node scripts on every tool call. Install them only with the human's explicit OK |
| MCP configs | They connect to external services |
| web/JS agents (`performance-optimizer`, `refactor-cleaner`, `build-error-resolver`, `planner`) | Not our stack. Claude Code already ships a `Plan` agent |
| `security-review`, `tdd-workflow` skills | Next.js/Jest-centric |
| `ios-icon-gen` | Needs macOS `sips` and downloads from an external icon API |
| `i18n-sync` | JSON locale files. We use String Catalogs plus `scripts/l10n-*.py` |
| rules | Would load into every session and overlap with CLAUDE.md |

### How they fit the routing (CLAUDE.md)
- They are supplementary reviewers and references.
- `qa-reviewer` (Opus) remains the merge gate.
- Feature work stays with the existing role agents.
- Typical use:
  - `swift-reviewer` as an extra pass on Swift-heavy diffs;
  - `a11y-architect` for the accessibility audit (Phase 11);
  - `liquid-glass-design` and `swiftui-patterns` during the UI/UX overhaul.
