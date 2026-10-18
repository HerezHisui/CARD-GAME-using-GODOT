# October 18 UI implementation

Items 2–9 are implemented in the source and playable projects. Item 1 is pending because the separately referenced icon was not attached and its path has not been supplied. No substitute icon was invented.

Source: `github-publish/new-game-project`. Playable copy: `CARD-GAME-using-GODOT-main/new-game-project`. Source baseline: `0a980f4`.

| Item | Files touched under `new-game-project` | Change / commit summary | Commit | Patch |
| --- | --- | --- | --- | --- |
| 1 | None | Pending: replace disaster encounter icon once the reference is available; retain existing node dimensions and anchor. | None | None |
| 2 | `scripts/run_director.gd` | Remove inspection headings and closing instructions from live and catalog inspections. | `813f27a` | Inspection (see Git history) |
| 3 | `scripts/board_actions.gd`, `scripts/game_3d_manager.gd` | Open overhead view for board targeting, relocation, formation healing/buffs, and area utilities. Combat already opened overhead. | `8cff1ab` | Overhead (see Git history) |
| 4 | `scripts/card_3d.gd`, `scripts/game_3d_manager.gd`, `scripts/run_director.gd`, `scripts/ui_theme.gd`; `tests/oct18_ui_smoke.gd`, `tests/plans_notes_smoke.gd`, `tests/ui_consistency_smoke.gd` | Remove redundant HUD/menu controls and explanatory text; replace card effect text with icons and keep complete rules in inspection. | `146f3fc` | Cleanup (see Git history) |
| 5 | `scripts/run_director.gd`, `tests/oct18_ui_smoke.gd` | Rename player buff headings to Adaptations and Augmentations. | `2c0933f` | Labels (see Git history) |
| 6 | `scripts/ui_theme.gd`, `scripts/game_presentation.gd`, `tests/oct18_ui_smoke.gd` | Tween button backgrounds from black to red on hover, including dynamically created buttons. | `8103f5e` | Hover (see Git history) |
| 7 | `scripts/game_presentation.gd`, `scripts/game_3d_manager.gd`, `tests/oct18_ui_smoke.gd` | Pulse the draw button red during the draw phase and stop after drawing or leaving the phase. | `cc4dc1c` | Draw reminder (see Git history) |
| 8 | `scripts/run_director.gd`, `scripts/game_presentation.gd`, `tests/oct18_ui_smoke.gd` | Keep HP, supplies, deck size, and composition visible during the run, including catalog inspection and coin toss. | `d04f634` | Status strip (see Git history) |
| 9 | `scripts/run_director.gd`, `tests/oct18_ui_smoke.gd`, `tests/oct16_smoke.gd` | Preserve board targeting and resource-free Esc cancellation; bind Extraction's target to its callback instead of storing a stale reference. | `c740e3a` | Target cancellation (see Git history) |
| Test maintenance | `tests/ui_interaction_smoke.gd`, `scripts/run_director.gd` | Use the menu for catalog viewport cleanup coverage after removing the log screen; wrap route text to fit the repository's line-length convention. | `01cd79a` | Maintenance (see Git history) |

## Defaults and behavior

- Hover transition: 0.14 seconds; existing press feedback remains animated.
- Draw reminder: 0.45 seconds fading in and 0.45 seconds fading out; no new saved gameplay state.
- Card indicators: two rows of ten 18-pixel icons, with numeric status stacks and an overflow counter. Hold a deployed card to inspect its rules even in overhead view. Hand inspection remains disabled in overhead view.
- Status strip: reuse the existing header with two lines. Counts cover Evac, Douse, Clearance, Brace, and utility cards, including zero counts. Affinity counts include utilities with that affinity, so the utility count overlaps those counts. These are collection counts, not remaining draw-pile counts.
- The log UI, its shortcut, and its screen-building code are removed. Bounded internal event history remains because gameplay diagnostics and saved-run compatibility use it.
- The energy-banking checkbox UI is removed. The existing `auto_save` behavior and saved preference remain unchanged.
- Response graveyard controls appear only in combat. Recovery selection remains available where needed.
- Renaming applies to player buff headings; encounter names and run actions keep their established meanings.

## Validation actually run

Godot 4.7.2 console executable, with `--headless --path <project> --script res://tests/<suite>.gd`.

Source project: all ten suites passed after the relevant changes:

- `oct18_ui_smoke`
- `notes3_smoke`
- `oct16_smoke`
- `battle_behavior_smoke`
- `oct16_cleanup_smoke`
- `plans_notes_smoke`
- `ui_interaction_smoke`
- `camera_controls_smoke`
- `expansion_smoke`
- `run_smoke`

Playable copy: all eight suites passed:

- `oct18_ui_smoke`
- `plans_notes_smoke`
- `oct16_cleanup_smoke`
- `notes3_smoke`
- `ui_interaction_smoke`
- `camera_controls_smoke`
- `oct16_smoke`
- `run_smoke`

`git diff 0a980f4 HEAD --check` passed. Source working tree was clean after commits. Tests use the project's disposable test-save path.

Initial test failures were resolved: the old inspection guard blocked board inspection from overhead; a new fixture omitted the `cards` group; an older camera test bypassed `set_view` while a tween was active; an older UI test called the removed log screen. The affected suites subsequently passed.

No rendered, viewport, or screenshot audit was run, following `github-publish/AGENTS.md`. Visual appearance and layout have not been confirmed in a rendered session.

## Playable-copy synchronization

Applied only this session's UI patch to eleven files. Preserved the playable copy's pre-existing combat implementation and styling differences. Added the source's small `UI.outline` helper because the new numeric icon badges use it. Original playable files are backed up under mirror-before (see Git history).

Combined source patch (see Git history) contains this session's source changes. Playable-copy patch (see Git history) records the exact changes applied to the playable copy. No remote push was performed.

Remaining input: local path or attachment for the new disaster encounter icon.
