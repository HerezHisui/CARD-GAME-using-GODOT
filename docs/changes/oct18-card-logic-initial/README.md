# October 18 card logic implementation

Source: `github-publish/new-game-project`.
Request: `C:/Users/0stef/Downloads/files/prompt_card_main.md`.

## 1. Card placement hitbox

Commit: `4a48662` Fix card placement to use the visible lane under the cursor.

Files: `scripts/card_3d.gd`, `scripts/game_3d_manager.gd`,
`tests/ui_interaction_smoke.gd`, `tests/oct18_card_logic_smoke.gd`.

Placement projects the cursor onto each Response slot's plane and checks its local mesh bounds.
This removes the offset caused by raycasting down from the floating, animated card.
Default: the visible slot under the cursor determines placement in either camera view.

Patch: [01-placement.patch](01-placement.patch).

Checks: new lane-center checks passed in desk and overhead views, including an outside-board rejection.
The existing interaction suite initially failed its two deployment assertions because its release position
was projected at the old drag height. That fixture now releases over the visible slot; the full suite
has not yet been rerun.

## 2. Draw-card flow

Commit: `374cb2a` Choose the normal draw from the deck for one energy.

Files: `scripts/game_3d_manager.gd`, `tests/oct18_card_logic_smoke.gd`.

The normal Draw button opens a sorted card picker using the existing deck-card UI.
Confirming transfers one unlocked card to hand and spends exactly 1 energy; cancelling spends nothing.
Extra draw buffs still draw their extra cards. Duplicate callbacks cannot charge twice.
Default: the 1-energy charge is for the normal selection. Playing the selected card retains its listed
cost. There was no separate draw surcharge in the inspected implementation. Search and Rescue's
existing utility-card cost is unchanged, so this interpretation may need clarification.

Patch: [02-draw.patch](02-draw.patch).

Checks: picker opening, cancellation, transfer, exact charge and duplicate callback checks passed.

## 3. Contingency stat display

Commit: `57f0311` Refresh Plan attack displays at the point of mutation.

Files: `scripts/card_3d.gd`, `scripts/contingency_rules.gd`, `tests/oct18_card_logic_smoke.gd`.

Plan attack bonuses now use a setter that refreshes the face synchronously on application and removal.
The existing implementation already delayed Plan bonuses until combat and refreshed their faces;
the reported hover-triggered red flash or premature application was not reproduced.
Default: preserve delayed combat activation, consistent with the existing Plan descriptions.

Patch: [03-plan-display.patch](03-plan-display.patch).

Checks: targeting hover leaves health and bonus unchanged; arming does not apply the bonus early;
combat application immediately displays ATK 3, clearing displays ATK 2, and no damage flash occurs.

## 4. Overhead board inspection: incomplete

Uncommitted changes add projected card-face picking to the manager and route clicks to board actions
or hold inspection. A new combat/overhead hold test fails to open the inspection panel.
It failed twice, including after adding a mouse-motion event to the fixture.
Work stopped under `github-publish/AGENTS.md`'s explicit two-failure rule.
The picker finds the card, but the full hold input path remains unverified and requires diagnosis.

## Remaining work

Items 5–14 have not been implemented. The playable mirror has not been synchronized.
No rendered audits were run, as required by the repository instructions.

## Validation recorded

- Before edits: `battle_behavior_smoke.gd` passed; `oct18_ui_smoke.gd` reported 0 failures.
- After each completed item: `oct18_card_logic_smoke.gd` reported 0 failures.
- After item 2: `git diff --check` passed, with line-ending warnings only.
- Current work in progress: `oct18_card_logic_smoke.gd` reports 1 failure in item 4.
- Engine used: Godot 4.7.2 console, headless.

No claim is made that all existing suites or manual gameplay pass after these changes.
