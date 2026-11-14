# Midnight DRRills (Godot 4.7.2) - standing rules for Claude Code

Core rule: fit Claude, Claude Code and the work. Be fast, never skip a check: run the suites, report every changed test with a reason, never push.

## The three shapes (Simple's design philosophy, full text in the project doc design-philosophy.md)
Triangle = stability. Filter for every change: it must serve at least one corner and hurt none, or it is cut.
- Clean: the screen reads at a glance, short text, no clutter, no dead code, tidy scripts.
- Simple: learned in seconds, fewer buttons and words, no paragraph needed to use it.
- Solid: works every time. Suites pass, no SCRIPT ERROR, no test changed without a reason, input and drag never hang.
- Build order: Solid, then Simple, then Clean. Sound, shake and animation come last.
Hexagon = efficiency, for code and data: modular (small pieces), reusable (one template, many uses), lean (no waste),
fast (measured, never guessed), scalable (the 100th card or 5th hero fits), data-driven (rules in data, not code).
Never over-engineer: no new module, layer or abstraction without a measured reason.
Circle = perfection, for the loop and polish: whole (no dead ends), flowing (few clicks, little waiting), balanced
(no best pick), consistent (same look, words and behaviour on every screen and mode, P1 and P2 alike), polished
(text fits, every action gives feedback), replayable. A direction, never a gate: it does not block shipping.
Stack: triangle sets the rules, hexagon builds under them, circle finishes on top.

Cowork writes the prompt files in `new-game-project/prompts/` and reviews your diff. A prompt path like `prompts/x.txt`
means that folder. Read the prompt file you are told to read and follow it.
These rules apply to every task. A prompt file can add to them.
When a prompt file names parts to run in a row, these rules and the prompt win over the parent folder's CLAUDE.md
(its plan-first and wait-for-OK lines are for refactors only).

## Hard rules
- Do not commit unless the prompt says to. Simple commits from PowerShell with named paths. Never `git add -A`.
  Never `git push`. Never add a Co-Authored-By or Claude trailer to any commit message.
  Never commit docs/notes, prompts, Claude outputs, repos-out or export_presets.cfg.
- Public repo rule: no AI tool names or attribution in any file that reaches the public repo (code, tests, docs,
  README). Write "AI tools" if a doc must say it. check-public.sh blocks the rest. Never weaken that guard.
- Work on the branch the prompt names. You may create branches. Do not delete branches.
- Never run two Godot processes on this project at once, and never run Godot while Simple has the editor playing.
- Do not `cd`. You start in the project folder (`new-game-project`).
- Keep CRLF in files that use CRLF. Keep lines at most 120 characters.
- Tests may be edited, fixed or retired when the test is stale or wrong. List every changed test and why in the report.
  Never weaken a test to hide a real code bug: fix the code instead.
- Do not touch the nested old copy of the docs. Docs live in `github-publish/docs/`.
- Singleplayer must not change. New multiplayer behaviour stays behind its flag
  (for example `game.disaster_seat_on`).

## Files you may edit
- Edit the files the prompt lists, the files an AUTHORIZED message lists, and any NEW file (tests, scripts,
  docs/notes). A prompt that lists no files means the files its steps name.
- A shared file (for example `scripts/run_director.gd`) may be edited when the real cause is there,
  but only with a guard that keeps singleplayer unchanged.
- If the real cause is in a file nobody listed: do NOT stop the whole goal. Skip that item, write the file and
  the reason in the report, finish the other items, and ask once at the end.
- Never change a LAN message shape, `PROTOCOL`, `lan_session.gd` or `lan_actions.gd` unless the prompt names them.

## Working through a goal
- Stop between parts only if the prompt says STOP AFTER EACH PART. Otherwise run the parts in order and report once
  at the end, saving a cumulative `docs/notes/<name>-after-part-N.patch` after each part.
- Items the prompt lists as DEFERRED or SKIPPED are decided: note them in the report and continue.
- After each part run the suites the change touches, plus `ui_consistency_smoke` and `versus_smoke`.
  Run ALL suites once at the end of the goal. A failing suite you did not expect stops that part.
- Stop below 15 percent of the 5-hour limit. Do not ask questions the prompt already answers.
- Do not read or probe skill, observation or notes folders outside `docs/notes`.

## Running tests
- Godot: `C:/Users/0stef/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`
- One suite: `godot --headless --fixed-fps 60 --path . -s tests/<name>_smoke.gd`, with a 200 second time limit.
  `--fixed-fps 60` gives every frame 1/60 s of game time, so timers and tweens do not wait on the clock.
  Same checks, about 3 times faster. Drop the flag only to look at real-time feel.
- For the full run, use batches of 8 suites, each with timeout 200. Run lan_* suites and versus_smoke one at a time.
- Test baseline (2026-11-14, branch lan-prototype 27a0b19, --fixed-fps 60): 143 suites, 143 pass, full run about 160 s.
  lan_smoke alone takes about 33 s (ENet's own timeout). "resources still in use at exit" is known noise.
- Report exit codes, and any of: SCRIPT ERROR, FAILED, Parse Error, null instance, Index, ERROR, WARNING.
  Ignore "Unreferenced static string". It only appears when a timeout kills the run.
- Exit 124 means a hang. A runtime error in a signal handler, or a paused tree, hangs a suite.
  Show the last 20 lines and stop.

## Tools
- Godot skills copied from GodotPrompter (MIT, pinned 60c28fd) sit in `~/.claude/skills/godot-*`. They give general
  Godot advice only. These rules and the prompt win when they disagree. Do not install other plugins or MCP servers.
- Two-window LAN test in the editor: Debug > Customize Run Instances, 2 instances, launch args `-- host` and
  `-- join 127.0.0.1` (debug builds only, scripts/lan_autostart.gd). Both instances share user://.

## Godot traps seen in this project
- `_input` goes to later-added nodes first. The director (added after the seat) sees keys before the seat.
- A paused tree (menu open) stops nodes that are not `PROCESS_MODE_ALWAYS`.
  `create_timer(x, false)` then hangs a test. Wait in frames instead.
- Fixtures that call `_enemy_turn()` need `game.disaster_is_human = false`.
- A card under the mouse stays raised. Move the mouse away before an "at rest" check.
- A direct handler call can pass while the real click fails. Test through the real input path.
- A parse error in a preloaded script hangs every suite until timeout. Run one suite right after any scripted edit.
- Wait in frames with a cap (600), never in unbounded loops. A bug can freeze a real window that headless never shows.
- Do not put variable names like password or tool names in tests or docs: check-public.sh blocks them.

## Report format
End every report with five headings: DIFF, RESULTS, BY EYE, FRICTION, SHAPES.
SHAPES is three short lines: triangle (clean, simple, solid: what you checked), hexagon (what you reused or left
alone instead of adding), circle (any screen or mode that now differs from the others).
BY EYE lists what Simple must check by hand, because headless tests cannot show feel.
FRICTION lists anything slow, confusing or missing, so Cowork can log it.
Show the diff summary and stop.
