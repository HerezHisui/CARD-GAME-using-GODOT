# Debug panel rework

Implemented from `C:/Users/0stef/Downloads/files/prompt_debug.md`.

## Changes

- Remove debug explanations: removed the password hint, panel description, and status help; shortened resource and status labels.
- Add live card stat editing: reused the card picker for Cost, ATK, HP, and statuses, with immediate badge updates and checkpoints.
- Preserve exact password access: retained the existing masked prompt requiring exactly `*****`, including fresh authentication on reopening.

Defaults: Cost edits the raw `cost` field, ATK edits base attack, HP edits current health with a minimum of 1; raising HP raises its healing ceiling, utilities only expose Cost, and card edits apply immediately.

The picker includes living hand cards and units on either board. Numbered entries distinguish duplicate names. Empty and stale selections cannot write stats. Existing attack modifiers still affect the displayed ATK. Edits affect the selected runtime instance; deck collection and recovery definitions remain unchanged. Existing save serialization already handles these fields, so no save format changes were needed.

## Files touched

The following paths were changed in both `github-publish/new-game-project/` and `CARD-GAME-using-GODOT-main/new-game-project/`:

- `scripts/run_director.gd`: simplify debug text and add focused helpers for selecting, loading, and editing live card stats.
- `tests/debug_card_smoke.gd`: cover immediate edits, badges, selection changes, bounds, utilities, stale targets, empty battles, and save restoration.
- `tests/blood_pact_inspection_debug_smoke.gd`: update the expected field count to include the three new card inputs.

Delivery report retained here; implementation changes are available in Git history.

## Validation

Godot 4.7.2, using `--headless --path <project> --script res://tests/<suite>.gd`:

| Suite | Source | Playable copy |
| --- | --- | --- |
| `debug_card_smoke.gd` | Passed, zero failures | Passed, zero failures |
| `ui_interaction_smoke.gd` | Passed, zero failures | Passed, zero failures |
| `blood_pact_inspection_debug_smoke.gd` | Passed | Not rerun |
| `explorer_mode_smoke.gd` | Passed | Not rerun |

The existing interaction and October 16 suites also passed before editing. The new suite initially failed because its empty-battle fixture remained in SETUP after clearing combat. Resetting that fixture to PLAYER_PLAY fixed the test; the final run passed. Test saves use the project's disposable regression paths.

`git diff --cached --check` passed. SHA-256 comparison confirmed all three delivered source files match the playable copy. Visual layout was not checked; project instructions restrict this task to headless validation.

Local source commit: `8550cdb` (`Simplify debug panel and add live card stat editing`). Unrelated changes in the playable copy were preserved.

## Patch

The implementation is available in Git history at commit `8550cdb`.
