# Midnight DRRills (Godot 4.7.2) - standing rules for Claude Code

Cowork writes the prompt files in `prompts/` and reviews your diff. Read the prompt file you are told to read and follow it.
These rules apply to every task. A prompt file can add to them, but it cannot remove the commit rule.

## Hard rules
- Never run `git commit`, `git push`, `git add` or `git stash`. Simple commits after Cowork reviews the diff.
- Work on branch `multiplayer-hotseat`. Do not switch branches.
- Work on branch `lan-prototype` is allowed for LAN stages (gated by `LAN_ENABLED` in `scripts/versus_match.gd`).
- Do not `cd`. You start in the project folder (`new-game-project`).
- Keep CRLF in files that use CRLF. Keep lines at most 120 characters.
- Do not edit existing tests to make them pass. Add tests, or stop and report.
- Do not touch the nested old copy of the docs. Docs live in `github-publish/docs/`.
- Singleplayer must not change. New multiplayer behaviour stays behind its flag
  (for example `game.disaster_seat_on`).

## Files you may edit
- Edit only the files the prompt lists.
- A named shared file (for example `scripts/run_director.gd`) may be edited when the real cause is there,
  but only with a guard that keeps singleplayer unchanged. If the cause is in a file the prompt did not list, stop and ask.
- Stop and ask when a check cannot pass without a code change beyond what the prompt listed.

## Running tests
- Godot: `C:/Users/0stef/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`
- One suite: `godot --headless --path . -s tests/<name>_smoke.gd`, with a 200 second time limit.
- For the full run, use batches of 8 suites, each with timeout 200.
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
