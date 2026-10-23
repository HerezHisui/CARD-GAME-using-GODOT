# UI Shell Scenes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the code-built UI shell (header, gauges, board prompt, boss intent, dashboard, modal frame) into editable `.tscn` scenes with zero visual or behavior change.

**Architecture:** Each shell piece becomes a small scene under `scenes/ui/`, styled by named theme styles in `data/ui_theme.tres`. `run_director.gd` `_build_ui()` instances the scenes in today's order and binds the existing variables by unique name (`%Name`). All text, visibility, signals, `decorate()` trims and `_panel_layout()` sizing stay in code.

**Tech Stack:** Godot 4.7.2, GDScript, headless smoke tests (`extends SceneTree`).

**Spec:** `docs/superpowers/specs/2026-10-23-ui-shell-scenes-design.md`

## Global Constraints
- Work in `github-publish/new-game-project`. The mirror is synced separately, later.
- No game logic changes. No color, size, text or position changes.
- One task = one tag `before-<task>` + one commit, staged by name. Never use `git add -A`.
- The full suite (`tests/*_smoke.gd`, 35 today plus the new `ui_shell_smoke`) passes before and after each task. No existing test is weakened or edited without a stated reason and approval.
- The parity check (below) must report zero differences after tasks 2–7.
- These variable names stay and must point at the scene nodes: `summary`, `map_button`, `menu_button`, `modal_dimmer`, `modal`, `modal_scroll`, `content`, `prep`, `threat`, `plans_button`, `graveyard_button`, `board_prompt`, `board_prompt_label`, `boss_intent`, `dashboard`.
- Node order must hold:
  - `director.root.get_child(0)` is the header;
  - the tension gauge box has exactly 2 children;
  - the energy gauge box's child 2 is the "Deck N" label.
- Each scene root sets `theme = res://data/ui_theme.tres`, so the editor shows the real look. This is the same resource as `UI.get_theme()`.
- Every scene button gets what `button()` gives it today: `mouse_default_cursor_shape = 2` (pointing hand), `custom_minimum_size = Vector2(130, 42)`, and `game.presentation.button_feedback(b)` called from code.
- A label at size 22 or above uses `theme_type_variation = "HeadingLabel"` and upper-case text. Smaller labels use the theme's default font. Each label sets `font_size` and `font_color` overrides.
- Style: typed GDScript, lines under 120 characters, plain comments.

## Shared tooling (Task 0, never committed)
- `<scratchpad>/shell_parity.gd` (`extends SceneTree`). It runs with `-- <out.json>`, loads `res://scenes/game_3d.tscn`, sets `director.persistence.enabled = false`, sets `root.size = Vector2i(1440, 900)` and calls `director.new_run()`. It then records two states, `map` (`director.show_map()`) and `battle` (`game.start_encounter(director.collection, "battle", 1, 0)`, after the player turn begins).
- For each of these nodes it records:
  - the 15 variables above, plus `root.get_child(0)`, `prep.get_parent()`, `threat.get_parent()`, `boss_intent.get_parent()` and the `prep`/`threat` boxes' child 0 and 2;
  - `get_global_rect()`, `is_visible_in_tree()`, `text`, `tooltip_text`, `mouse_filter`, `theme_type_variation`, `get_theme_font_size("font_size")`, `get_theme_color("font_color")` and `get_theme_font("font").font_names`;
  - for each of `panel`, `normal`, `background` and `fill`, the stylebox's `bg_color`, `border_color`, its 4 border widths, 4 corner radii and 4 content margins.
- Compare with `diff before.json after.json`. Empty output means pass.

## Review Focus
1. **Window resize while a modal is open:** `size_changed` must still call `_panel_layout(screen)` on the new modal. Covered in Task 7: `ui_shell_smoke` resizes the window and checks the modal rect.
2. **Compact screens** (menu, debug at 560px, plans, confirm): `_panel_layout()` reparents `content` into `modal_scroll`. Covered in Task 7: the test opens the debug and menu screens and checks `content.get_parent() == modal_scroll` and the modal width is 560 / 420.
3. **The title screen hides the header** (`root.get_child(0).visible == false` on `title`). Covered in Task 3: the test opens the title screen.
4. **Mouse input across layers once Plans/Graveyard move into `HUD/Root`:** a click on the Plans button must still open plans and must not reach the board. Covered in Task 6: the test emits `pressed` and checks `director.screen == "plans"`, and checks `mouse_filter` stays `STOP`.
5. **Hover and press feedback on scene buttons:** each one must carry the `hover_feedback` meta. Covered in Tasks 3, 4 and 6: the tests check `has_meta("hover_feedback")` on every scene button.

---

### Task 1: Theme styles

**Files:**
- Modify: `scripts/ui_theme.gd` (`build_theme()`, before `return theme`)
- Modify: `data/ui_theme.tres`: insert 7 type blocks and their `[sub_resource]` StyleBoxFlat blocks by editing the text. Do not regenerate the file.
- Create: `tests/ui_shell_smoke.gd` (+ `.gd.uid`)

**Interfaces:**
- Produces: these theme styles (base, items):
  - `HeaderPanel` (PanelContainer, `panel`)
  - `ModalPanel` (PanelContainer, `panel`)
  - `DashboardPanel` (PanelContainer, `panel`)
  - `PromptPanel` (PanelContainer, `panel`)
  - `EnergyBar` (ProgressBar, `background`, `fill`)
  - `TensionBar` (ProgressBar, `background`, `fill`)
  - `HeadingLabel` (Label, `font`)

- [ ] **Step 1: Write `tests/ui_shell_smoke.gd`** in the same style as `ui_palette_smoke.gd`, with `check()` and `quit(failures)`. Test `theme_styles()` runs on both `load(UI.THEME_PATH)` and `UI.build_theme()`:
  - `get_type_variation_base(name)` matches the base above;
  - each stylebox matches `UI.panel(...)` / `UI.bar(...)` on `bg_color`, `border_color`, border widths, corner radii and content margins;
  - expected values: `HeaderPanel` = `UI.panel(UI.PANEL)`; `ModalPanel` = `UI.panel(UI.PANEL, UI.GOLD)`; `DashboardPanel` = `UI.panel(UI.INSET, UI.BRONZE)`; `PromptPanel` = `UI.panel(UI.BACKGROUND, UI.RESPONSE)`; `EnergyBar` = background `UI.panel(UI.INSET, UI.BRONZE, 0)` and fill `UI.bar(UI.RESPONSE)`; `TensionBar` = the same with fill `UI.bar(UI.DANGER)`;
  - `HeadingLabel` font `font_names` == `UI.font(true).font_names` and `font_weight == 700`.
- [ ] **Step 2: Run it** with `"$GODOT" --headless --path . -s tests/ui_shell_smoke.gd`. Expected: FAIL, "HeaderPanel variation base".
- [ ] **Step 3: In `build_theme()`, add the 7 styles** using `set_type_variation` + `set_stylebox` / `set_font`, with the values above.
- [ ] **Step 4: In `data/ui_theme.tres`, add the same.**
  - Add one new `[sub_resource type="StyleBoxFlat"]` per stylebox. Copy the field lines from an existing equal block and adjust only the colors, using `var_to_str()` output from a throwaway print.
  - Add `<Type>/base_type = &"<Base>"` and `<Type>/styles/<item> = SubResource(...)` lines in alphabetical type order.
  - `HeadingLabel/fonts/font` reuses the existing heading SystemFont sub-resource id that `Button/fonts/font` uses.
- [ ] **Step 5: Run** `ui_shell_smoke`, `ui_theme_file_smoke`, `ui_palette_smoke` and `ui_consistency_smoke`. Expected: all PASS. `git diff data/ui_theme.tres` shows additions only.
- [ ] **Step 6: Run the full suite.** Expected: 36/36. Commit: "Add shell theme styles to the UI theme".

### Task 2: `ui_gauge.tscn`

**Files:**
- Create: `scenes/ui/ui_gauge.tscn`
- Modify: `scripts/run_director.gd`: `_build_ui()` lines that call `_gauge()`; delete `_gauge()`; in `_process()`, the `get_child(0/2)` lookups
- Test: `tests/ui_shell_smoke.gd` (add `gauges()`)

**Interfaces:**
- Produces: a gauge scene with root `VBoxContainer` (`separation` 4), children `Title` (Label), `Bar` (ProgressBar, `%Bar`) and `Detail` (Label), in that order. `func _make_gauge(title: String, color: Color, variation: String, keep_detail: bool) -> ProgressBar` in `run_director.gd` returns `%Bar`.

- [ ] **Step 1: Add `gauges()` to `ui_shell_smoke`.** It instances `game_3d.tscn`, calls `new_run()`, then checks:
  - `director.prep.get_parent().scene_file_path == "res://scenes/ui/ui_gauge.tscn"` (same for `threat`);
  - the prep box has 3 children and the threat box 2;
  - `prep.theme_type_variation == "EnergyBar"` and `threat`'s is `"TensionBar"`;
  - `prep.custom_minimum_size == Vector2(195, 20)` and `show_percentage == false`.
- [ ] **Step 2: Run.** Expected: FAIL on `scene_file_path`.
- [ ] **Step 3: Capture parity before** with `shell_parity.gd -- before.json` (Task 0 tooling).
- [ ] **Step 4: Create the scene.**
  - Bar: `custom_minimum_size (195, 20)`, `show_percentage = false`.
  - Title: font size 14. Detail: text "", font size 13, color `MUTED` (`8c867e`).
- [ ] **Step 5: Write `_make_gauge()`.** It instances the scene, adds it to `root` and sets the anchors and offsets per side:
  - energy: `PRESET_BOTTOM_LEFT`, left 24, right 240, top -78, bottom -12. Title "PREPAREDNESS ENERGY", color `RESPONSE`, `EnergyBar`; keep `Detail`.
  - tension: `PRESET_TOP_RIGHT`, left -240, right -24, top 158, bottom 215. Title "TENSION", color `DANGER`, `TensionBar`; free `Detail` with `free()`, not `queue_free()`, so the child count is 2 at once.
- [ ] **Step 6: Replace the 2 `_gauge()` calls in `_build_ui()`,** keeping their position, and delete `_gauge()`. In `_process()`, use `get_node("Title")` / `get_node("Detail")` on the box instead of `get_child(0/2)`.
- [ ] **Step 7: Run** `ui_shell_smoke` (expected PASS), then the parity check against `before.json` (expected: empty diff).
- [ ] **Step 8: Run the full suite** (36/36) and a 10-second headless run of the main scene with no new errors. Commit: "Build the energy and tension gauges from ui_gauge.tscn".

### Task 3: `ui_header.tscn`

**Files:**
- Create: `scenes/ui/ui_header.tscn`
- Modify: `run_director.gd` `_build_ui()` (the header block, today lines 278–299)
- Test: `ui_shell_smoke.gd` (add `header()`)

**Interfaces:**
- Produces: a header scene with root `PanelContainer` (`HeaderPanel`), unique names `%Summary`, `%DeckButton`, `%MapButton` and `%MenuButton`.

- [ ] **Step 1: Add `header()`.** It checks:
  - `director.root.get_child(0).scene_file_path == "res://scenes/ui/ui_header.tscn"`;
  - `director.summary`, `map_button` and `menu_button` are the scene's unique nodes;
  - each of the 3 buttons has `has_meta("hover_feedback")`;
  - after `show_title()`, `root.get_child(0).visible == false` (Review Focus 3).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Capture parity before.**
- [ ] **Step 4: Create the scene.**
  - Root: `PRESET_TOP_WIDE`, `offset_bottom = 78`, `HeaderPanel`.
  - HBox `separation` 14.
  - Brand VBox `custom_minimum_size.x = 225`, with Label "MIDNIGHT DRRILLS" (`HeadingLabel`, size 22, color `GOLD`) and Label "THE SCHOOL AFTER DARK" (size 11, `MUTED`).
  - `%Summary`: text "", size 14, `autowrap_mode = 3`, `size_flags_horizontal = 3`, `horizontal_alignment = 1`.
  - Buttons: "Deck  [D]", "School map  [M]", "Menu  [Esc]", with two spaces before each bracket.
- [ ] **Step 5: Instance the header as `root` child 0** in `_build_ui()`, bind the variables, and connect `pressed` to `show_deck`, `toggle_map` and `show_menu`. Call `button_feedback` on each button, then `UI.decorate(header)`. Delete the old block.
- [ ] **Step 6: Run** `ui_shell_smoke` and the parity check (expected: empty diff), then the full suite and the 10-second run. Commit: "Build the top bar from ui_header.tscn".

### Task 4: `ui_board_prompt.tscn`

**Files:**
- Create: `scenes/ui/ui_board_prompt.tscn`
- Modify: `run_director.gd` `_build_ui()` (the board prompt block)
- Test: `ui_shell_smoke.gd` (add `board_prompt()`)

**Interfaces:**
- Produces: a board prompt scene with root `PanelContainer` (`PromptPanel`), `%PromptLabel` and `%CancelButton`.

- [ ] **Step 1: Add `board_prompt()`.** It checks:
  - `director.board_prompt.scene_file_path` is the new scene;
  - `board_prompt_label` is `%PromptLabel`;
  - `%CancelButton` has `hover_feedback`;
  - opening a board pick shows the prompt with its title, and pressing `%CancelButton` clears `game.board_input.action`.
- [ ] **Step 2: Run.** Expected: FAIL. Then capture parity before.
- [ ] **Step 3: Create the scene.**
  - Root: `PRESET_TOP_WIDE`, left 240, right -240, top 178, bottom 257, `visible = false`.
  - HBox containing `%PromptLabel` (size 17, `RESPONSE`, `autowrap_mode = 3`, `size_flags_horizontal = 3`) and `%CancelButton` ("Cancel [Esc]").
- [ ] **Step 4: Bind the scene in `_build_ui()`** at today's position (last `root` child) and connect `%CancelButton.pressed` to `func(): game.board_input.cancel()`. Delete the old block.
- [ ] **Step 5: Run** `ui_shell_smoke`, the parity check (empty), the full suite and the 10-second run. Commit: "Build the board prompt from ui_board_prompt.tscn".

### Task 5: `ui_boss_intent.tscn`

**Files:**
- Create: `scenes/ui/ui_boss_intent.tscn`
- Modify: `run_director.gd` `_build_ui()` (the intent panel block)
- Test: `ui_shell_smoke.gd` (add `boss_intent()`)

**Interfaces:**
- Produces: a boss intent scene with root `PanelContainer` (`ModalPanel`) and `%IntentLabel`. `boss_intent` stays bound to `%IntentLabel`.

- [ ] **Step 1: Add `boss_intent()`.** It checks that `director.boss_intent.get_parent().scene_file_path` is the new scene and that both nodes have `mouse_filter == 2` (ignore). Run: expected FAIL. Capture parity before.
- [ ] **Step 2: Create the scene.**
  - Root: `PRESET_TOP_WIDE`, left 245, right -245, top 182, bottom 254, `mouse_filter = 2`, `visible = false`.
  - `%IntentLabel`: size 16, `GOLD`, centered, `autowrap_mode = 3`, `mouse_filter = 2`.
- [ ] **Step 3: Bind the scene in `_build_ui()`** at today's position (after the idle hint) and delete the old block.
- [ ] **Step 4: Run** `ui_shell_smoke`, the parity check (empty), the full suite (also covered by `final_boss_smoke`) and the 10-second run. Commit: "Build the boss intent panel from ui_boss_intent.tscn".

### Task 6: Dashboard, Plans and Graveyard in `hud.tscn`

**Files:**
- Modify: `scenes/hud.tscn`: add `Dashboard` as the first child of `Root`, plus `PlansBox/PlansButton` and `GraveyardButton`
- Modify: `run_director.gd`: remove the dashboard, `plans_box` and `graveyard_button` blocks and `place_dashboard_button()`; bind the variables from `game.get_node("HUD/Root/...")`
- Test: `ui_shell_smoke.gd` (add `dashboard()`)

**Interfaces:**
- Produces: `HUD/Root/Dashboard`, `HUD/Root/PlansBox/PlansButton` and `HUD/Root/GraveyardButton` (that node name is kept).

- [ ] **Step 1: Add `dashboard()`.** It checks:
  - `director.dashboard == game.get_node("HUD/Root/Dashboard")` and it is child 0 of `HUD/Root`;
  - `plans_button` and `graveyard_button` resolve to the HUD nodes and have `hover_feedback` and `mouse_filter == 0` (stop);
  - in battle, `plans_button.pressed.emit()` leads to `director.screen == "plans"` (Review Focus 4).
- [ ] **Step 2: Run.** Expected: FAIL. Capture parity before.
- [ ] **Step 3: Add the nodes to `hud.tscn`.**
  - `Dashboard`: `PRESET_BOTTOM_WIDE`, `offset_top = -90`, `mouse_filter = 2`, `DashboardPanel`.
  - `PlansBox` VBox: `PRESET_BOTTOM_LEFT`, left 260, right 450, top -78, bottom -15, holding `PlansButton` ("Contingency 0/2  [P]", with today's tooltip).
  - `GraveyardButton`: `PRESET_BOTTOM_RIGHT`, left -560, right -394, top -73, bottom -17, with today's tooltip.
- [ ] **Step 4: Bind them in `_build_ui()`,** connect `show_plans` and `show_graveyard`, and call `UI.decorate(dashboard)`. `button_feedback` already reaches HUD buttons through `game_presentation.gd` `setup()`; check the meta in the test. Delete `place_dashboard_button()`.
- [ ] **Step 5: Run** `ui_shell_smoke`, then the parity check. The global rects must match. Parent and layer changes are expected and are not part of the record. Then run the full suite and the 10-second run. Commit: "Move the dashboard, Plans and Graveyard buttons into hud.tscn".

### Task 7: `ui_modal_frame.tscn`

**Files:**
- Create: `scenes/ui/ui_modal_frame.tscn`
- Modify: `run_director.gd` `_build_ui()` (the dimmer, modal, scroll and content block)
- Test: `ui_shell_smoke.gd` (add `modal_frame()`)

**Interfaces:**
- Produces: a modal frame scene with root `Control` named `ModalFrame` (full rect, `mouse_filter = 2`). It holds `%ModalDimmer` (ColorRect) and `%Modal` (PanelContainer, `ModalPanel`), and inside `%Modal`, `%ModalScroll` then `%Content`.

- [ ] **Step 1: Before writing anything,** run `grep -rn "root.get_child_count\|root.get_child(" tests scripts`. The wrapper turns 2 root children into 1. If anything counts root children or uses an index above 0, stop and report it.
- [ ] **Step 2: Add `modal_frame()`.** It checks:
  - `director.modal.owner.scene_file_path` is the new scene;
  - opening the debug screen gives `content.get_parent() == modal_scroll` and a modal width of 560 (Review Focus 2);
  - opening the menu gives a width of 420;
  - `root.size = Vector2i(1280, 800)` followed by `await process_frame` keeps the modal centred with the same size (Review Focus 1);
  - `modal.get_child(0).name == "IndustrialTrim"`.
- [ ] **Step 3: Run.** Expected: FAIL. Capture parity before.
- [ ] **Step 4: Create the scene.**
  - `%ModalDimmer`: full rect, `offset_top = 78`, color `Color(0.043137256, 0.043137256, 0.050980393, 0.86)`, `mouse_filter = 0`, hidden.
  - `%Modal`: full rect, offsets 45 / 94 / -45 / -28, `mouse_filter = 0`, hidden.
  - `%ModalScroll`: `follow_focus = true`, `horizontal_scroll_mode = 3`, hidden.
  - `%Content`: VBox, `separation` 14.
- [ ] **Step 5: Bind the scene in `_build_ui()`** at the dimmer's old position. Then:
  - call `UI.decorate(modal)` followed by `modal.move_child(modal.get_node("IndustrialTrim"), 0)`, so the trim stays child 0 as today;
  - connect `modal.gui_input` to `_modal_input`;
  - keep the `size_changed` connection.
  
  Delete the old block.
- [ ] **Step 6: Run** `ui_shell_smoke` and the parity check (empty), then the full suite. The 23 tests that use `content`/`modal` must pass unchanged. Then the 10-second run, and open every new scene in a headless editor with `--editor --path . <scene> --quit-after 300`, expecting no errors. Commit: "Build the modal frame from ui_modal_frame.tscn".
