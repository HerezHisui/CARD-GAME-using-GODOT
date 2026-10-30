# Menu redesign progress

Active goal: redesign every untouched/inconsistent menu while preserving established designs, gameplay, card art/fonts, and cumulative uncommitted work. No commit/push. Rendered checks at 1280x800 and 1440x900 authorized.

## Evidence gathered
- Read current run_director screen routes, run_shop, suspended_menu, Godot UI skill, scene inventory, and Git status.
- Added tests/menu_redesign_review.gd, a save-disabled baseline capture fixture.
- Fixture completed with exit 0 using Compatibility at 1280x800; captured characters, character preview, rest, shop, upgrade, deck, graveyard, menu, settings, battle log, debug access, and victory.
- Baselines: C:/Users/0stef/Downloads/midnight-menu-review/baseline.
- Inspected characters, rest, shop, and deck images. Rest/shop use sparse full-width button rows; characters have weak hierarchy; deck needs a catalog header and deliberate framing.

## Next work, full scope retained
1. Inspect remaining captured screens. Extend baseline fixture to six events, upgrade preview, removal/confirmation, defeat, intel, targeting choices, and existing approved screens as references.
2. Implement cohesive menu presentation through narrowly scoped scene/layout changes and a shared style helper where useful. Preserve existing map, title, battle HUD, reward noticeboards and adaptation layouts when already consistent.
3. Rest/events: centered room dossiers, meaningful room icon, grouped choices with visible costs/outcomes; shop: stock shelf and compact service row; catalogs: clear header/toolbars and usable scrolling; character selection: school identity dossiers; terminal screens: polished result panels. Keep actionable content and remove duplicated instructions.
4. Audit hover/focus/disabled states and non-card Caveat Brush typography. Avoid touching card SubViewports.
5. Run navigation and affected behavior suites. Render every changed screen at both requested resolutions, including empty/disabled/long-content states. Inspect artifacts and fix issues.
6. Document validation and perform a requirement-by-requirement completion audit before marking goal complete.

No product styling changes have been made for this goal yet. Earlier board/crash work remains intact. Goal is active, not complete.

## Implementation pass 1
- Added scripts/room_menu_style.gd: pixel-icon room headings, bounded dark bronze dossiers, consistent button hover/pressed/focus/disabled styles, separate right-aligned exit.
- run_director applies this narrowly to event/shop. Event Box fixed minimum width removed to fit the bounded frame. run_shop duplicate supply counter removed; main HUD count remains.
- Revised captures generated at both target sizes under Downloads/midnight-menu-review/revised. Rest and shop visually inspected at both sizes; no clipping observed.
- hud_navigation_smoke and board_targeting_plans_and_events_smoke passed. Scoped diff check passed with line-ending notices only.
- Remaining: six event renders (shared styling changed), shop transactions, catalogs, character screens, terminal screens, confirmation/debug/choice consistency, all navigation and final audit. Rest/shop layout may still be refined during final cohesive review.
- The opening note saying no product styling changes is superseded by this entry. Goal remains active.

## Implementation pass 2
- Added catalog framing/headings for deck, graveyard, workshop, character preview, removal and intel via room_menu_style.catalog. Character selection now uses cream identity dossiers with larger, darker descriptions and clear unavailable cards.
- Fixed capture fixture battle_active setup: earlier graveyard baseline was actually the map, so it was NOT valid graveyard evidence. Actual empty graveyard now captured. Extended fixture with all six events.
- One render attempt failed due a newly introduced CP1252 middle-dot byte in run_director. Replaced it with ASCII, validated UTF-8, reran successfully. Captured/inspected character, deck, empty graveyard at 1280. Source files should be read/written explicitly UTF-8 going forward.
- Science capture revealed centered_screen moves headings into Center/Box, preventing the room style hook. Fixed helper to use that nested content and bound its width. This last event fix still needs new rendered verification.
- hud_navigation and board_targeting_plans_and_events smoke passed after final changes; diff check passed.
- Next: rerender at both sizes (especially six events after helper fix), inspect workshop/character preview and remaining captures; add populated graveyard, upgrade preview/removal/confirmation/defeat/intel/targeting cases. Polish any remaining inconsistent screens and complete navigation/hover/focus checks. Goal remains incomplete.

## Pass 3 / final (Claude, plan docs/superpowers/plans/2026-10-30-menu-redesign-finish.md)
Changed:
- scripts/room_menu_style.gd: stale-screen guard (`current`, uses `style_kind` meta set in reset_panel), event heading
  left-aligned, readable 19 px note under headings, catalog buttons get bronze plates, `compact` style for confirm /
  choice / remove_confirm / log, `result` cream notice for victory and defeat, hover_pressed + focus font colors,
  `focus_button` (confirm focuses the safe answer, end screens focus their first action).
- scripts/run_director.gd: victory/result sized as a centered 760x460 notice; event room height 600 -> 560;
  defeat shows "Run ended on floor N · X cards in deck"; upgrade_preview added to catalog styling.
  Fixed deck order toggle (`reverse_sort`): it removed `content.get_child(3)`, which became the card grid once the
  heading was added (and was out of range before). It now updates SortRow/OrderButton text by name.
- scripts/run_shop.gd: removed "Need N supplies" tooltip; the disabled button already shows the price.
- tests/menu_redesign_review.gd: 14 more states (full deck/graveyard, upgrade preview, removal + confirm, broke shop,
  intel, adaptation, floor reward, card and lane pickers, both confirmations, defeat). 32 captures per size.
- tests/menu_style_smoke.gd (new): heading/plate/focus/hover_pressed checks, stale-style guard, order toggle,
  disabled shop button without tooltip, rest exit returns to map, victory/defeat notices.
Left as-is (already fit): map, title, battle HUD, pause menu and settings (cream noticeboard), adaptation and floor
reward noticeboards, contingency rewards. Debug screens are developer tools, not restyled.

Verification:
- Headless pass: menu_style, hud_navigation, board_targeting_plans_and_events, collection_shop_upgrades_and_ai (its
  reverse_sort runtime error is now gone), ui_interaction, ui_shell, menu_navigation_and_camera, hover_graveyard,
  ui_palette, ui_refinement, run, run_routes, route_style, character_decks_map_and_combat, coin_rewards,
  hud_rewards_boss, contingency_plans.
- Failing before and after this pass, battle HUD only, not menus: ui_consistency (gauge readout, compact width 420
  at 1440) and hud_menu_improvements (hub tooltips). hud_menu_improvements wants hub tooltips while
  board_asset_smoke wants them empty: the two tests conflict and need an owner decision.
- hud_navigation "reminder visibly pulses" failed once in 5 runs: timing flake.
- Rendered Compatibility captures at 1280x800 and 1440x900, exit 0, 32 each, in Downloads/midnight-menu-review/revised.
  Inspected events, rest, shop, broke shop, workshop, upgrade preview, deck (full), graveyard, removal, intel,
  pickers, confirmations, battle log, characters, character preview, victory, defeat. No clipping or overlap found.
- UTF-8 validated on edited scripts; diff --check clean (CRLF notices only). Nothing committed or pushed.
