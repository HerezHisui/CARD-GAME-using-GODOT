# Midnight DRRills (Godot 4.7, GDScript)

@AGENTS.md

## Extra rules for Claude Code

- Project root for Godot is `new-game-project/`. Docs are in `docs/`. Read `docs/refactor-plan.md` before any refactor step.
- Plan first. Show the plan in a few lines and wait for my OK before editing.
- One step per session. Do not start the next step on your own.
- Name only the files you need. Do not open or edit anything else. If you need another file, ask me.
- Never guess a path, node name or function name. Search for it, or ask.
- Keep changes small and simple, like a first-year CS student would write them. No new patterns, autoloads or abstractions unless I ask.
- Comments are short and plain. Do not delete or shorten existing comments.
- Do not change card numbers, balance or save formats during a refactor.
- Test baseline: 30 pass, 1 fail (`classroom_integration`, lighting check, headless limit), 1 skipped (`ui_consistency`). Do not try to fix those two.
- Run the headless smoke tests that cover the files you touched, before and after. Do not weaken a test to make it pass.
- Tag git before a risky refactor step: `git tag before-<step-name>`.
- Commit once per finished step with a plain-English message.
- Final report: max 5 lines (what changed, tests run, what is next).
- Stop and tell me if a step fails twice or context passes about 70 percent.
