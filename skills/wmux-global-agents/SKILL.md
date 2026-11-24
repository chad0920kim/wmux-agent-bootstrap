---
name: wmux-global-agents
description: Set up a Windows + wmux machine so the agent CLIs (claude, grok, agy/Antigravity, wmux) can be launched from ANY folder and ANY wmux pane, and optionally install one global reply-language rule (e.g. Korean) for every agent. Use when a new wmux user says "claude/grok/agy not found in another folder", "make agents callable globally", "wmux 초기 설정", "전역에서 에이전트 호출", "모든 에이전트 한국어 전역 규칙".
---

# wmux-global-agents

Windows-only (PowerShell 5.1+). One deterministic script does the work; **you (the LLM) only run it,
read its JSON, ask the user to confirm, and explain the result.** Do not re-implement its steps by hand.

## Execution contract (read first — these rules exist because LLMs fail here)

1. **Never improvise.** Use only the commands in this file. Do not invent flags for `claude`/`grok`/`agy`/`wmux`
   (run `<tool> --help` if you need one). Do not edit `setup.ps1`.
2. **Always launch the script with `powershell -NoProfile -ExecutionPolicy Bypass -File ...`.**
   Bypass applies to that one process only and changes nothing on the system. Without it,
   a default Windows machine (policy `Restricted`) refuses to run any `.ps1`, and a model tends to
   "fix" that by weakening the policy globally. Don't.
3. **Two-phase: check, then apply.** No `-Apply` = read-only. Show the user what would change and get an
   explicit "yes" before running with `-Apply`. Approval for one run does not cover a different run.
4. **Always pass `-Json`** and parse the output. Report to the user in the user's own language,
   in plain words — not raw JSON.
5. **Follow `nextAction`** in the JSON. If `errors` is non-empty or `verify.allFound` is false after apply: stop,
   show the report, and use *Troubleshooting* below. Do not re-run in a loop.
6. **Never read or print** credential files (`oauth_creds.json`, `.claude.json`, tokens, API keys).
   Detecting agents needs none of them.
7. If you have no shell tool, give the user the exact command to paste themselves (see *Manual run*).
8. **Do not run `guide.ps1` or `시작하기.bat`.** They are the interactive, human-facing path (they wait for keyboard input and
   would hang you). You always use `setup.ps1 -Json`. If the user prefers clicking, tell them to double-click `시작하기.bat`.
9. If a download/install step fails with `0x80072f0d`, "untrusted root" or an SSL/TLS trust error, do not disable certificate
   checks. Read `docs/TROUBLESHOOTING.md` §1 and let the user decide; `scripts/fix-tls-root.ps1` needs administrator rights.

## What it changes (tell the user before applying)

| # | Change | Scope | Reversible |
|---|--------|-------|-----------|
| 1 | Append missing agent folders to the **User** PATH (registry). Never removes/reorders entries. | current user | yes — original saved in backup dir |
| 2 | Add a marked `Sync-AgentPath` block to the PowerShell profile so *new tabs/panes* always see the latest PATH | current user | yes — delete the marked block |
| 3 | Set `CurrentUser` execution policy to `RemoteSigned` **only if** it is `Restricted`/unset (profile scripts need it) | current user | yes |
| 4 | Add a marked language-rule block to each detected agent's global rule file | current user | yes — delete the marked block |

Rule files: Claude `~/.claude/CLAUDE.md`, Antigravity `~/.gemini/config/GEMINI.md`, Grok `~/.grok/rules/language.md`.
Existing content is kept; every touched file is backed up to `~/.wmux-agent-bootstrap/backups/<timestamp>/`.

## Steps

Let `$SKILL` = absolute path of this skill's folder (the folder containing this file).

### Step 1 — Ask the user one question
Language rule: `ko` (Korean), `en` (English), or `none` (skip). Offer a custom file via `-RulesFile <path>` only if they ask.

### Step 2 — Check (read-only)
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SKILL\scripts\setup.ps1" -Json -Language <ko|en|none>
```
Read: `agents[].found`, `path.missingDirs`, `profile[].status`, `executionPolicy.status`, `rules[].status`, `verify`.
- `status` values: `unchanged` / `already-present` = nothing to do; `would-create|append|update|add|set-RemoteSigned` = will change.
- If `executionPolicy.status` is `blocked-by-group-policy` or `allsigned-needs-human-decision`: the script will not touch it.
  Tell the user it needs their/IT's decision; continue with the other steps.
- If no agent is found: stop and tell the user to install an agent CLI first.

### Step 3 — Confirm
Summarise the pending changes (use the table above) and ask: "Apply these changes?" If `changesPending` is false, say it is already set up and stop.

### Step 4 — Apply
Same command + `-Apply`:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$SKILL\scripts\setup.ps1" -Json -Language <ko|en|none> -Apply
```
It ends with a **fresh-shell check**: a new `powershell.exe` started in another folder with a minimal PATH must find every
detected agent. `verify.allFound: true` is the success criterion.

### Step 5 — Tell the user
- Already-open terminal tabs keep their old PATH. In each, run `. $PROFILE.CurrentUserAllHosts` (or `Sync-AgentPath`), or open a new tab.
- Agents already running a conversation read their rule file only at start-up: restart them to apply the language rule.

### Step 6 (optional) — Refresh already-open wmux panes
Only if the user asks. **Never send keystrokes to a pane that is running an agent conversation.**
```powershell
wmux list-panes                                   # find pane ids
$screen = (wmux read-screen --tail 5 --to <PANE_ID>) -join "`n"
if ($screen -match 'PS [^\r\n]+>\s*$') { wmux send '. $PROFILE.CurrentUserAllHosts' --submit --to <PANE_ID> } else { 'not at idle prompt - skipped' }
```
Do this per pane, one at a time, and report which were skipped.

## Manual run (no LLM needed)
```powershell
cd <this repo>\skills\wmux-global-agents\scripts
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Language ko            # check
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Language ko -Apply      # apply
```

## Troubleshooting

| Symptom | Cause | Do |
|---------|-------|----|
| `verify.allFound=false`, `shellStderr` mentions "running scripts is disabled" | policy is Restricted and step 3 was skipped/blocked | re-run without `-SkipExecutionPolicy`; if GPO-blocked, ask IT |
| Agent `found:false` but user says it is installed | installed in a non-standard folder | ask for the folder; add it to PATH by hand, then re-run check |
| New tab still lacks the agent | tab opened before apply, or wmux restored an old environment | run `. $PROFILE.CurrentUserAllHosts`; if still missing, restart wmux |
| Profile path looks odd (`OneDrive\...`) | Documents is redirected to OneDrive | expected; the script follows the real Documents folder |
| Agent still answers in the wrong language | session started before the rule existed, or a project-level rule overrides | restart the agent; check the project's own `CLAUDE.md`/`GEMINI.md` |

## Undo
Delete the block between `>>> wmux-agent-bootstrap:... >>>` and `<<< ... <<<` in the touched files, or restore from
`~/.wmux-agent-bootstrap/backups/<timestamp>/`. The previous User PATH is saved in `user-path.before.txt` there.
