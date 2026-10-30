# Menu Redesign Finish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the paused Codex menu redesign: verify passes 1–2, restyle the remaining inconsistent screens, and close with a requirement-by-requirement audit.

**Architecture:** All styling goes through the existing `scripts/room_menu_style.gd` helper (`apply`, `style_actions`,
`catalog`, `identity`), hooked from `run_director.gd:204` and `:600-602`. New screens get a hook in the same place, not
a new helper. Visual evidence comes from `tests/menu_redesign_review.gd` (rendered, Compatibility, 1280×800 and `--large`
1440×900) writing to `C:/Users/0stef/Downloads/midnight-menu-review/revised`.

**Tech Stack:** Godot 4.7.2, typed GDScript.

**Spec:** The /goal text in the Codex handoff + `docs/menu-redesign-progress-2026-10-30.md` (Codex's log).

## Global Constraints

- Repo: `github-publish/new-game-project` only. Never edit the outer `new-game-project` copy.
- **Do not commit or push** (goal rule overrides CLAUDE.md "commit per step").
- Do not touch card SubViewports, card art, card fonts, gameplay, balance, save format.
- Preserve already-approved designs: map, title/splash, battle HUD, reward noticeboards, adaptation layout.
- Non-card UI text uses Caveat Brush; palette from `data/ui_theme.tres`. New hard-coded colors only inside `room_menu_style.gd`.
- Write source files as UTF-8, ASCII punctuation only (Codex hit a CP1252 middle-dot crash).
- Lines < 120 chars, typed GDScript, short functions; narrow edits, no reformatting.
- Rendered checks: only the fixture above, only for changed screens.
- Stop and report if any step fails twice.

## Commands

```bash
GODOT="C:/Users/0stef/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
# headless suite (from github-publish/)
$GODOT --headless --path new-game-project --script res://tests/<suite>.gd
# captures
$GODOT --path new-game-project --rendering-method gl_compatibility --script res://tests/menu_redesign_review.gd
$GODOT --path new-game-project --rendering-method gl_compatibility --script res://tests/menu_redesign_review.gd -- --large
```

Core suites (the "UI set"): `hud_navigation_smoke`, `board_targeting_plans_and_events_smoke`,
`collection_shop_upgrades_and_ai_smoke`, `ui_consistency_smoke`, `ui_interaction_smoke`, `ui_shell_smoke`,
`menu_navigation_and_camera_smoke`, `hover_graveyard_smoke`, `ui_palette_smoke`.

## Review Focus

1. Long content (many cards in deck/graveyard/removal, long event text) must scroll inside the frame, not clip or push the exit button off-screen.
2. Disabled choices (can't afford shop item, event cost unpayable) must look disabled and still be readable.
3. Keyboard/controller focus must be visible on every restyled button and land on a sensible first button.
4. Back/Escape from every restyled modal returns to the same screen as before the redesign.
5. 1440×900 must not leave tiny centered dossiers floating in empty space (bounded width, but not cramped).

---

### Task 1: Baseline and verify Codex's last unverified fix

**Files:** none modified unless a defect is found (then `scripts/room_menu_style.gd`, `scripts/run_director.gd`).

- [ ] Run the UI set headless. Record pass/fail per suite in the progress doc. Known stale failures (graveyard/compact-width, deck sort, per handoff) are noted, not fixed.
- [ ] Generate missing `.uid` files for `scripts/room_menu_style.gd` and `tests/menu_redesign_review.gd` with `$GODOT --headless --editor --path new-game-project --quit`. Expected: both `.uid` files appear.
- [ ] Run both capture commands. Expected: exit 0, `CAPTURE` line per screen, 6 events × 2 sizes present.
- [ ] Inspect all six event captures at both sizes (the `centered_screen` nested-Box fix at `run_director.gd:999` was never rendered). Pass = pixel icon heading, bounded bronze dossier, no clipping, exit separate.
- [ ] Inspect workshop (`upgrade-*`) and `character-preview-*`, which Codex styled but never viewed.
- [ ] Known suspect from transcript review: `identity()` sets unavailable pick text `b7a68a` on unavailable paper `b3a58b`
  (near-invisible). Check `characters-*`; if unreadable, darken the disabled font color (e.g. `5c5244`).
- [ ] All 1440 captures except rest/shop predate pass 2 (catalog/identity styling) and no 1440 event captures exist;
  treat every old 1440 image as stale.
- [ ] Fix any defect in the helper, rerun captures for that screen only.

### Task 2: Extend the capture fixture to the uncovered states

**Files:** Modify `tests/menu_redesign_review.gd` (after the event loop, before `game.queue_free()`).

Add captures, each preceded by `director.close_modal()` and the same `battle_active` handling as the existing loop:

- [ ] `graveyard-full`: fill the graveyard with ~15 cards from the starting deck before `show_graveyard()` (read `show_graveyard` at `run_director.gd:1302` for the field it reads).
- [ ] `deck-full`: same idea, deck with ~30 cards.
- [ ] `upgrade-preview`: `show_upgrade()` then `show_upgrade_preview(0)`.
- [ ] `remove`: `show_remove_cards("shop")`; `remove-confirm`: then `confirm_remove()`.
- [ ] `shop-broke`: `coins = 0`, `show_shop()` (disabled state).
- [ ] `intel`: `show_intel()` with `battle_active = true`.
- [ ] `buffs`: `show_buff_choices()`; `floor-buffs`: `show_floor_buffs()`.
- [ ] `confirm-title`: `confirm_title()`; `confirm-abandon`: `confirm_abandon()`.
- [ ] `defeat`: find the defeat screen from `game_3d_manager.gd:1848 _check_game_over`; call the director method it uses.
- [ ] Run both captures. Expected: exit 0, all new names present. If a call needs state it lacks, set the minimal field; don't change game code to suit the fixture.

### Task 3: Restyle confirmations, choice modals and terminal screens

**Files:** `scripts/room_menu_style.gd`, `scripts/run_director.gd` (hook sites only: `confirm_buttons:1838`, `show_buff_choices:1924`,
`show_floor_buffs:1968`, `show_run_victory:902`, the defeat screen), and if needed the matching `scenes/ui/ui_confirm.tscn`,
`ui_buff_choices.tscn`, `ui_choose_cards.tscn`, `ui_choose_slot.tscn`.

Decisions:
- Confirmations: small cream noticeboard, one-line question, two buttons; the destructive option on the right in rust/red, Back on the left focused by default.
- Buff/slot/card choices: reuse `apply(modal, content, kind)` with new kinds `"choice"`; options as equal-width tiles via `style_actions`.
- Victory/defeat: `"result"` kind — large Caveat Brush title, short run stats row, single primary action. Remove any instruction text that just repeats the button label.

- [ ] Add the new `kind` branches to `apply()`; hook them at the listed sites with the same `call_deferred` pattern as `:602`.
- [ ] Run UI set headless. Expected: same results as Task 1 baseline.
- [ ] Capture both sizes; inspect every Task 2/3 screen. Fix clipping/overlap.

### Task 4: Menu, settings, battle log, debug consistency pass

**Files:** `scripts/run_director.gd` (`show_menu:1664`, `show_settings:621`, `show_battle_log:1231`, `show_debug:1697`),
`scripts/suspended_menu.gd`, `scripts/room_menu_style.gd`.

- [ ] Compare `menu/settings/battle_log/debug` captures against rest/shop. Restyle only those that don't match (likely: settings and battle log get `catalog` framing; debug keeps function, gets `style_actions`).
- [ ] Run UI set + `run_debug_smoke`, `debug_card_smoke`. Expected: baseline results.
- [ ] Capture both sizes and inspect.

### Task 5: Hover/focus/disabled audit and redundant copy

**Files:** `scripts/room_menu_style.gd`, hook sites only.

- [ ] Grep every screen in this plan for `tooltip_text` and instruction labels; remove the ones that restate visible info, keep costs/outcomes/rules.
- [ ] Confirm `style_actions` sets `focus` stylebox and `grab_focus()` on a sensible first button for each modal (Review Focus 3); add a check to `tests/ui_interaction_smoke.gd`: each restyled modal has a focus-owner Button after open.
- [ ] Check Escape/Back on every restyled modal returns to the prior screen (Review Focus 4); add assertions to `tests/hud_navigation_smoke.gd` for any not already covered.
- [ ] Run UI set. Expected: baseline + new assertions pass.

### Task 6: Final verification and completion audit

- [ ] Run full UI set + `run_smoke`, `run_routes_smoke`, `route_style_smoke`, `character_decks_map_and_combat_smoke`. Compare with Task 1 baseline; any new failure stops the plan.
- [ ] Final captures at both sizes; inspect every changed screen once more.
- [ ] `git -C github-publish diff --check` on touched files.
- [ ] Append "Implementation pass 3 / Final" to `docs/menu-redesign-progress-2026-10-30.md`: files changed, suites run with results, captures inspected, and a checklist mapping each goal sentence to evidence. Nothing committed.
