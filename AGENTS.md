# AGENTS.md — instructions for any LLM agent working in this repository

This repo ships one skill: `skills/wmux-global-agents/`.

- To **run** it for a user: read `skills/wmux-global-agents/SKILL.md` and follow it exactly (check → confirm → apply → verify).
- To **modify** it: keep `scripts/setup.ps1` ASCII-only (Windows PowerShell 5.1 reads BOM-less files as ANSI);
  put any non-ASCII text in `templates/*.md` (UTF-8). Keep every change idempotent, additive and backed up.
- Never commit personal data: user names, home paths, tokens, `oauth_creds.json`, `.claude.json`.
- Test changes without touching the real system: `setup.ps1 -Apply -HomeDir <temp> -SkipPath -SkipProfile -SkipExecutionPolicy`.
