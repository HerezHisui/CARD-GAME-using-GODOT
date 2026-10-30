# UI refinement validation, 30 October 2026

Changed only this project. No commits or pushes were made.

## Completed checklist

- [x] Remove the tactic-unlock count from the live Plans heading without changing unlock mechanics.
- [x] Style both health widgets and Tension with charcoal panels, bronze fills and live values.
- [x] Use pale, elongated wind particles for Evac without changing affinity or combat rules.
- [x] Widen adaptation choices, add effect icons, increase heading and description sizes, and retain the noticeboard.
- [x] Reproduce the black-button bug and remove the style mutation that caused it.
- [x] Use Caveat Brush for UI and popups, with a separate helper preserving original card-face fonts.
- [x] Unify turn and clash presentation using thin gold rules and a translucent dark band.
- [x] Style the existing title in cream and gold and strengthen peripheral background blur.

The hover regression test failed before the fix: normal, hover and pressed styles were replaced,
and the cream normal fill became black. It now checks repeated enter/press/release/exit cycles,
disabled state preservation, bundled UI fonts and actual card viewport fonts.

## Checks run

Godot 4.7.2, using `--headless --path <project> --script res://tests/<name>_smoke.gd`:

| Suite | Result |
| --- | --- |
| ui_refinement | Passed |
| ui_theme_file | Passed |
| ui_shell | Passed |
| hud_navigation | Passed |
| menu_navigation_and_camera | Passed |
| card_symbols | Passed |
| battle_vfx | Passed |
| vfx_gameplay_integration | Passed |
| contingency_plans | Passed |
| coin_rewards | Passed |
| ui_palette | Passed |

The existing shell, navigation and banner tests were updated where their old visual expectations
conflicted with the requested appearance. Gameplay assertions remain in place.

Headless editor import completed without reported errors or warnings. `git diff --check` passed.

## Targeted visual review

The `ui_refinement_smoke.gd` fixture also ran with a rendered backend:

- Compatibility at 1280 × 800, with exact capture dimensions checked.
- Forward+ at 1440 × 900, with exact capture dimensions checked.

Reviewed title text and blur boundaries, low/full health and Tension, Plans, long adaptation
descriptions, populated current adaptations, focus/selected/disabled styles, enlarged card
typography, turn/clash overlays, and Evac wind bursts. Automated checks verify announcement
and particle cleanup. The fixture disables persistence before creating its run.

Screenshots are in `%TEMP%/midnight-ui-review-1280` and `%TEMP%/midnight-ui-review-1440`.
The populated current-adaptations check was additionally captured at 1280 × 800.

## Existing failure and limits

Before implementation, `ui_consistency_smoke.gd` completed 78 headless audit cases with six
failures. All six expected a 420-pixel compact panel for pause, menu, Plans or adaptations,
although the existing code already specified wider panels. That broad audit was not rerun or
rewritten; the new targeted fixture covers the changed layout instead.

Physical controller input and resolutions beyond the two targeted sizes were not visually
verified. This was a targeted review, not a visual audit of every menu or every card.
