# AGENTS.md — instructions for any LLM agent working in this repository

This repo ships one skill: `skills/wmux-global-agents/`.

- To **run** it for a user: read `skills/wmux-global-agents/SKILL.md` and follow it exactly (check → confirm → apply → verify).
- `scripts/guide.ps1` and `시작하기.bat` are the **human** interactive path. LLMs must use `scripts/setup.ps1 -Json`, never `guide.ps1`.
- To **modify** it: keep `scripts/setup.ps1`, `scripts/fix-tls-root.ps1` and `시작하기.bat` ASCII-only (Windows PowerShell 5.1 / cmd read
  BOM-less files as ANSI); put non-ASCII text in `templates/*.md` (UTF-8). `scripts/guide.ps1` contains Korean, so it MUST be saved as
  UTF-8 **with BOM**. Keep every change idempotent, additive and backed up.
- Test the interactive guide without touching the system: `guide.ps1 -TestMode -HomeDir <temp>` (pipe answers via stdin);
  `-SimulateNoAgents` exercises the "no agent installed" branch.
- Never commit personal data: user names, home paths, tokens, `oauth_creds.json`, `.claude.json`.
- Test changes without touching the real system: `setup.ps1 -Apply -HomeDir <temp> -SkipPath -SkipProfile -SkipExecutionPolicy`.
