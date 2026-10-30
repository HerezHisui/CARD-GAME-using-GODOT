# HUD, rewards, and boss announcement update

## Scope and status

Existing uncommitted work was retained. No commits, pushes, installations, or original-model edits were made.

- Implemented: compact Student and enemy HP widgets, larger white dismissible boss intent, and reward noticeboards.
- Implemented after explicit approval: West's extra Echo and East's Guardian healing, as specified below.
- Deferred by request: rigging, cloth simulation, enemy placement, and synchronized character/card animation until the full character export arrives.

## Implementation

Student health is 300 × 48 logical pixels; enemy health is 244 × 52. Bars retain their original update and delayed-damage animation code. Caveat Brush captions and values remain readable, including Midnight Warden.

The existing boss-intent panel uses 26-point white wrapping text. Its dismissal script consumes both mouse press and release and hides only the announcement. A new round, changed intent, or new encounter displays the next announcement. Current intent remains available by hovering the boss name. Turn and clash banners were not changed by this task.

Card rewards, New Contingency, and permanent floor rewards share the existing suspended noticeboard skin: bronze frame, cream panels, ink text, icons, and wider choices. Reward generation and claim callbacks are unchanged. The menu skin skips 3D card previews and their viewports to preserve card colors, fonts, and rendering.

Files edited for this task:

- `scenes/hud.tscn`: health bounds and Supplies spacing.
- `scripts/ui_theme.gd`: compact health padding, captions, bars, and marks.
- `scenes/ui/ui_boss_intent.tscn` and new `scripts/boss_announcement.gd`: announcement presentation and dismissal.
- `scripts/run_director.gd`: intent updates/tooltip and reward noticeboard layout.
- `scripts/suspended_menu.gd`: exclude card preview rendering from menu styling.
- `scripts/final_boss.gd`: approved pillar support, spawn timing guard, and inspection descriptions.
- `tests/ui_shell_smoke.gd`: replace the obsolete mouse-ignore expectation with dismissal click consumption.
- New `tests/hud_rewards_boss_smoke.gd` and its UID: focused regression and optional rendered captures.
- New `tests/pillar_support_smoke.gd` and its UID: support boundaries, removal, actual effects, and Continue.
- New `docs/enemy-model-audit-2026-10-30.json`: supplied asset inspection.

## Approved and implemented pillar effects

Preserve the scripted Warden encounter, without adding an enemy deck or resource system.

- West Circuit Pillar: create one additional Static Echo at round preparation. If the hand is full, apply the existing 1 HP overflow penalty for that additional Echo.
- East Circuit Pillar: heal a living Shield Guardian by 1 HP at round preparation, capped at its maximum health. Do not revive a destroyed Guardian.

Each living, deployed pillar contributes independently, once per round. Effects start at the next preparation after the pillars spawn. Destroyed or absent pillars stop future contributions; already-created Echoes remain subject to their existing rules. The baseline Echo, shield, recoil, taunt, and phase-transition mechanics remain in place. Existing `last_prepared_round` checkpoint state prevents duplicate application after Continue. The spawn boundary also marks that round prepared, preventing effects if preparation is requested immediately after the pulse. Support uses the existing persistent pillar IDs, so saved pillars need no new fields or save migration. Both inspection dossiers state timing, amounts, and removal rules.

## Asset and tooling audit

The supplied 136,324-byte GLB has 27 transform nodes and one four-second animation (`rigify_clip`, 48 channels), but **zero meshes, skins, materials, images, or textures**. There are hand transform nodes but no finger joints. The Armature node has scale 0.01. Geometry scale, topology, weights, clothing, and hand deformation cannot be evaluated because no geometry is present. No external mesh buffer is referenced.

Original SHA-256: `5431d8e3b41dce2ee7b0c7ab42c71fe0f26296ee720b1f92e47a26859ee2b6f5`.

Godot 4.7.2 is available. Project configuration uses Forward+ with a Compatibility mobile fallback and Jolt physics. Blender was not found in PATH or the checked Program Files and local Programs locations. No substantial download was attempted. No rig, cloth simulation, character derivative, or animation integration is claimed. A cloth method requires the full mesh and topology audit first.

## Validation

Latest status: the focused HUD/reward and pillar-support fixtures pass. The HP-animation failure was traced to fixture startup timing: the first 250 ms timer expired after 3 ms of wall time during the initialization frame, before its tween had reached the endpoint. Waiting for that startup frame to finish fixed the test without changing game animation code. The fixture now verifies both bars' initial damage transition and delayed lag-bar completion.

These Godot 4.7.2 headless suites completed cleanly:

- `hud_rewards_boss_smoke.gd`: compact geometry, exact HP values, long enemy caption, white intent, real press/release dismissal, click-through prevention, unchanged boss resolution, next announcement, exact reward copies, single claims, skipping, and reward/contingency Continue.
- `hud_navigation_smoke.gd`
- `hud_menu_improvements_smoke.gd`
- `ui_shell_smoke.gd`
- `ui_theme_file_smoke.gd`
- `ui_palette_smoke.gd`
- `contingency_plans_smoke.gd`
- `coin_rewards_smoke.gd`
- `final_boss_smoke.gd`
- `ui_refinement_smoke.gd`
- `pillar_support_smoke.gd`: no spawn-round support; exact stacking with baseline Echo; Guardian healing cap and no revival; no repeat application; Continue before/after preparation; destruction and leaving play; full-hand and one-slot overflow; actual unresolved-curse damage; unchanged shield and phase transitions.
- `battle_state_smoke.gd`
- `battle_engine_smoke.gd`: 63,729 comparisons passed.

The new fixture first reproduced 11 failures in the original UI, then passed after implementation. The shell test initially failed its old mouse-ignore assertion; that assertion was updated to the requested click-consuming behavior.

Two additional suites reported success and exited 0 but were not clean:

- `collection_shop_upgrades_and_ai_smoke.gd`: out-of-bounds child access and null calls in `run_director.gd::reverse_sort`. The entire function matches HEAD and was untouched by this task.
- `map_sorting_caps_and_saves_smoke.gd`: two deferred `grab_focus` calls on controls outside the tree. No baseline determination was made for these warnings.

Headless editor scan completed without reported errors. `git diff --check` passed, with only existing CRLF normalization notices.

Rendered HUD/reward fixture checks passed with exact capture dimensions at 1280 × 800 using Compatibility and 1440 × 900 using Forward+, including the corrected animation check. Reviewed HP/name layout, wrapped boss intent, contingency and floor choices, card rewards, inspection, and card-face text. Initial narrow reward columns and menu styling of preview text were corrected during this review. The pillar fixture also passed a Forward+ run; both pillar inspection dossiers were visually reviewed, along with the two Echoes and healed Guardian on the board.

Captures: `%TEMP%/midnight-hud-rewards-1280` and `%TEMP%/midnight-hud-rewards-1440`.
Pillar captures: `%TEMP%/midnight-pillar-support-1440`.

Character deformation, cloth, placement, synchronization, interruption, and cleanup checks remain pending because the full character mesh is missing and those features are deferred by request. No claim is made that rigging or cloth simulation exists. Other resolutions and physical controller input were not tested.
