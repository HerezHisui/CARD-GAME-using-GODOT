# Midnight DRRills (Godot 4.7.2) - standing rules for Claude Code

Core rule: fit Claude, Claude Code and the work. Be fast, never skip a check: run the suites, report every changed test with a reason, never push.

Cowork writes the prompt files in `prompts/` and reviews your diff. Read the prompt file you are told to read and follow it.
These rules apply to every task. A prompt file can add to them.

## Hard rules
- Commit locally on your work branch with named paths (never `git add -A`), one commit per part. Never `git push`.
  Simple pushes through the export script. Never commit docs/notes, prompts, Claude outputs or export_presets.cfg.
- Work on the branch the prompt names. You may create branches. Do not delete branches.
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
- One suite: `godot --headless --path . -s tests/<name>_smoke.gd`, with a 200 second time limit.
- For the full run, use batches of 8 suites, each with timeout 200.
- Test baseline (2026-11-09, branch bloat2): 135 suites, 135 pass, 0 fail, 0 timeouts.
- Report exit codes, and any of: SCRIPT ERROR, FAILED, Parse Error, null instance, Index, ERROR, WARNING.
  Ignore "Unreferenced static string". It only appears when a timeout kills the run.
- Exit 124 means a hang. A runtime error in a signal handler, or a paused tree, hangs a suite.
  Show the last 20 lines and stop.

## Godot traps seen in this project
- `_input` goes to later-added nodes first. The director (added after the seat) sees keys before the seat.
- A paused tree (menu open) stops nodes that are not `PROCESS_MODE_ALWAYS`.
  `create_timer(x, false)` then hangs a test. Wait in frames instead.
- Fixtures that call `_enemy_turn()` need `game.disaster_is_human = false`.
- A card under the mouse stays raised. Move the mouse away before an "at rest" check.
- A direct handler call can pass while the real click fails. Test through the real input path.

## Report format
End every report with four headings: DIFF, RESULTS, BY EYE, FRICTION.
BY EYE lists what Simple must check by hand, because headless tests cannot show feel.
FRICTION lists anything slow, confusing or missing, so Cowork can log it.
Do not commit. Show the diff summary and stop.
