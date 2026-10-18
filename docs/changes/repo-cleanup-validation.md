# Repository cleanup validation

Date: October 18, 2026. Source repository: `github-publish`.

## Scope

Moved October 18 card logic, UI and debug reports into `docs/changes/`.
Removed exported patches, report logs and obsolete `mirror-before` backups.
Renamed date-named smoke suites and their existing UID sidecars, updated references,
and added repository-wide `* text=auto`. The project's existing `eol=lf` rule remains.
Runtime scripts, scenes, card data and `project.godot` match baseline commit `cd88891`.
The playable mirror's uncommitted work was left untouched.

## Test names and final checks

| Previous suite | Current suite | Headless result |
| --- | --- | --- |
| oct15_smoke.gd | coin_rewards_smoke.gd | Passed |
| oct16_cleanup_smoke.gd | graveyard_save_compatibility_smoke.gd | Passed |
| oct16_section3_smoke.gd | blood_pact_inspection_debug_smoke.gd | Passed |
| oct16_smoke.gd | recovery_coordination_smoke.gd | Passed |
| oct18_balance_smoke.gd | balance_rules_smoke.gd | Passed |
| oct18_card_logic_smoke.gd | card_logic_smoke.gd | Passed |
| oct18_ui_smoke.gd | hud_navigation_smoke.gd | Passed |

All seven renamed suites passed with exit code 0 and no engine errors after cleanup.
Content comparison confirmed six suites are unchanged; the balance suite only updates
its inherited script path to `res://tests/card_logic_smoke.gd`. Screenshot filenames
and test output messages were retained to preserve existing behavior.

Engine: Godot 4.7.2 console executable.
Command, from the source repository:

```powershell
& 'C:\Users\0stef\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path new-game-project --script res://tests/<suite>.gd
```

## Existing baseline failure

Before renaming tests, all 29 `tests/*_smoke.gd` suites were run headlessly:
28 passed; unchanged `notes3_smoke.gd` exited with code 1 for these assertions:

- Line 99: physical drag-release moves and heals other ally, source stays.
- Line 107: right-click cancellation restores board card.

No test or runtime code was changed to address these failures. The failing suite
was not rerun. All seven renamed suites passed both before and after renaming;
the other unchanged suites were not rerun after cleanup.
No rendered audit or manual gameplay session was performed.

## Repository checks

- `git diff --check` and staged whitespace checks passed.
- Runtime files match baseline `cd88891`.
- No stale dated suite references remain outside this historical rename table.
- No tracked `.patch` files, report logs or `mirror-before` backups remain.
- `git check-attr text` reports `auto` for root documentation and project tests.

Earlier implementation reports and parity hashes describe their original sessions,
not a new mirror validation. Reports retain their historical findings.
