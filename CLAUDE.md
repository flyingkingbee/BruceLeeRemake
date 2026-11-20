# Bruce Lee (Claude Code)

This workspace is a native Windows C++ remake of the Commodore 64 *Bruce Lee*. `README.md` covers the controls, the scoring, and the build. `DESIGN.md` describes how a frame runs, how the pictures are stored, and how collision works.

## Rules

The rules live in `.cursor\rules\`, and that folder is the only real copy. Cursor applies them by itself. Claude Code loads them through the imports below. Every rule here is marked `alwaysApply`, so follow all of them in every session. Edit a rule only under `.cursor\rules\`. A new rule file needs its own import line here.

@.cursor/rules/original-c64.mdc

@.cursor/rules/automatic-testing.mdc

@.cursor/rules/commit-message.mdc

@.cursor/rules/issue-tracking.mdc

## Skills

The skills live in `.cursor\skills\`, and that folder is the only real copy. `.claude\skills` is a directory junction to it, so Claude Code loads the same skills. Git ignores the junction. Add and edit skills only under `.cursor\skills\`, one folder per skill with a `SKILL.md` inside. Claude Code reads the skill list when a session starts, so a new skill shows up in the next session.

If `.claude\skills` is missing, for example after a fresh clone, recreate the junction from the workspace root in PowerShell, then start a new session:

```powershell
New-Item -ItemType Directory -Force .claude | Out-Null; New-Item -ItemType Junction -Path .claude\skills -Target (Resolve-Path .cursor\skills).Path
```

Do not copy the skills into `.claude\skills`. Keep one copy in `.cursor\skills`, so Cursor and Claude Code always run the same version.
