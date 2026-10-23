# UI shell as editable scenes: design

Date: 2026-10-23. Sub-project 1 of the "every UI as editable scenes" work.

## Goal
Make the persistent UI shell editable in the Godot editor: move, resize, restyle, and add or remove elements by hand. The game must look and behave exactly the same after each step. Game logic does not change.

The later sub-projects get their own spec: the ~24 modal screens, `game_presentation.gd` (coin flip, banners), and the card faces in `card_3d.gd`.

## Current state
`run_director.gd` `_build_ui()` builds the shell in code:
- On the director's `root` Control:
  - the header (top bar, which must stay `root` child 0)
  - the energy and tension gauges (`_gauge()`)
  - the modal dimmer, modal panel, modal scroll and `content`
  - the idle hint, the boss intent panel and the board prompt
  - the Plans button and the Graveyard button
- In `game_3d.tscn` `HUD/Root`: the bottom dashboard panel.

`_process()` updates text and visibility every frame, partly by looking nodes up by position: `root.get_child(0)` and `prep.get_parent().get_child(0/2)`. `_panel_layout()` sizes the modal for each screen.

Tests read node order. These must keep holding:
- `director.root.get_child(0)` is the header;
- the tension gauge box has exactly 2 children;
- the energy gauge's child 2 is the "Deck N" label.

23 test files use `director.content`, `director.modal` and `director.screen`.

## Design

### Scenes
| Scene | Nodes | Added to |
|---|---|---|
| `scenes/ui/ui_header.tscn` | PanelContainer root, HBox: brand VBox (2 Labels), `%Summary`, `%DeckButton`, `%MapButton`, `%MenuButton` | `root`, as child 0 |
| `scenes/ui/ui_gauge.tscn` | VBox root: `%Title` Label, `%Bar` ProgressBar, `%Detail` Label | `root`, twice. Tension removes `%Detail` so its box keeps 2 children. |
| `scenes/ui/ui_board_prompt.tscn` | PanelContainer, HBox: `%PromptLabel`, `%CancelButton` | `root` |
| `scenes/ui/ui_boss_intent.tscn` | PanelContainer, `%IntentLabel` | `root` |
| `scenes/hud.tscn` (existing) | add `Dashboard` PanelContainer as the first child of `Root`, plus `PlansButton` and `GraveyardButton` | already in `HUD/Root` |
| `scenes/ui/ui_modal_frame.tscn` | `%ModalDimmer` ColorRect, `%Modal` PanelContainer, with `%ModalScroll` and `%Content` inside | `root` |

Rules:
- Positions, anchors, offsets, sizes, separations, text, font sizes, label colors and tooltips are copied exactly from `_build_ui()`, `_gauge()` and `place_dashboard_button()` into the scene files.
- The idle hint gets no scene. `_process()` hides it every frame, so it is never visible. Removing it is a separate step, and only with approval.
- The idle hint, the boss intent panel, the Plans button box, the Graveyard button and the board prompt keep their order among `root`'s children.

### Theme styles (in `data/ui_theme.tres` and `build_theme()`)
| Style | Base | Value |
|---|---|---|
| `HeaderPanel` | PanelContainer | `UI.panel(UI.PANEL)` |
| `ModalPanel` | PanelContainer | `UI.panel(UI.PANEL, UI.GOLD)`, used by the modal and the boss intent panel |
| `DashboardPanel` | PanelContainer | `UI.panel(UI.INSET, UI.BRONZE)` |
| `PromptPanel` | PanelContainer | `UI.panel(UI.BACKGROUND, UI.RESPONSE)` |
| `EnergyBar` | ProgressBar | background `UI.panel(UI.INSET, UI.BRONZE, 0)`, fill `UI.bar(UI.RESPONSE)` |
| `TensionBar` | ProgressBar | background `UI.panel(UI.INSET, UI.BRONZE, 0)`, fill `UI.bar(UI.DANGER)` |
| `HeadingLabel` | Label | font `UI.font(true)`; `label()` uses it for sizes 22 and up |

Scene nodes set `theme_type_variation` to these styles. These styles are baked values, so editing the `Game` palette does not change them; they are edited on their own, as decision (a) set. Label color and size stay as per-node overrides in the scenes.

### Code (`run_director.gd`)
- `_build_ui()` instances each scene and adds it in today's order. It fills the existing variables from unique names, for example `summary = header.get_node("%Summary")`. These variables keep their names: `summary`, `map_button`, `menu_button`, `modal_dimmer`, `modal`, `modal_scroll`, `content`, `prep`, `threat`, `plans_button`, `graveyard_button`, `board_prompt`, `board_prompt_label`, `boss_intent`, `dashboard`.
- Button signals are connected in code, with the same callbacks as today. Scenes contain no game logic.
- `modal.gui_input`, `get_viewport().size_changed`, `UI.decorate()` trims and `_panel_layout()` stay in code.
- `_process()` replaces lookups by position with named nodes (`%Title`, `%Detail`). Everything else in `_process()` stays the same.
- Code that a scene replaces is deleted in the same step. `place_dashboard_button()` and `_gauge()` go away once nothing calls them.

### Errors
- A missing scene file or a wrong unique name makes `get_node("%…")` fail at startup, so every test fails at once.
- There is no fallback to code-built UI.

## Steps
Each step: tag `before-<step>`, run the full suite and the parity check, make one commit, and confirm the game runs.

0. Theme styles: add the 7 styles to `ui_theme.tres` and `build_theme()`. Nothing uses them yet.
1. `ui_gauge.tscn`.
2. `ui_header.tscn`.
3. `ui_board_prompt.tscn`.
4. `ui_boss_intent.tscn`.
5. `hud.tscn` dashboard and its 2 buttons.
6. `ui_modal_frame.tscn`. This is last because it carries the most risk.

## Testing
- **Full suite:** all headless smoke tests (35 today) pass before and after each step. No test is weakened. A test that changes needs a stated reason and approval.
- **Parity check (throwaway, never committed):** at 1440x900, in battle and on the map, record each shell node's global rect, visibility, stylebox class and colors, font size, font color, text and tooltip. Record before and after the step. The two records must match exactly.
- **Theme:** `ui_theme_file_smoke` covers the new style entries, which must match `build_theme()` in structure. `ui_palette_smoke` is unaffected.
- **Run check:** a 10-second headless run of the main scene shows no new errors or warnings.
- **Editor check:** each new scene opens in a headless editor with no errors.

## Risks
- **Node order:** tests depend on it. Every scene keeps today's order, and the parity check catches shifts.
- **Modal frame (step 6):** it touches what 23 test files use. Variables keep their names, and `_panel_layout()` stays in code.
- **Fixed per-screen offsets:** `_panel_layout()` overrides the modal's offsets on each screen. Editing the modal's size in the scene therefore only affects screens that `_panel_layout()` leaves alone. This limit is accepted for sub-project 1.
- **Baked styles:** the new styles do not follow `Game` palette edits.
