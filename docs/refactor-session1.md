# Session 1: battle behavior fixtures

Date: 2026-10-17

Added `new-game-project/tests/battle_behavior_smoke.gd` against the existing scene-backed rules.
No production rules, scenes, card data, or save formats were changed. Session 2 has not started.

The fixtures use small explicit card dictionaries and reset battle state between cases. They cover:

- Damage effectiveness and rounding, defenses, no immediate counterattack, no overkill, and Piercing.
- Burn/Poison upkeep before regeneration and Bleed after attacking.
- Last-unlocked-first drawing, sealed cards, hand capacity, and equal duplicate dictionaries.
- Tutor cancellation/confirmation, payment, graveyard recording, and temporary tax expiry.
- Actual End Turn, round/first-side progression, resource refill, drawing, and Floor 1 action limits.
- Actual sacrifice removal, draw/Burn rewards, major evolution entry, and insufficient sacrifices.

One existing draw behavior is deliberately pinned: Disaster drawing selects the last unlocked dictionary,
but `Array.erase` removes the first equal dictionary. The selected last dictionary can therefore remain
in the pile when equal copies exist. This session records that behavior without changing it.

## Headless validation

Run from `new-game-project` with Godot 4.7.2:

```powershell
godot --headless --path . --script res://tests/battle_behavior_smoke.gd
```

The eight Session 1 guard suites were run before and after adding the fixtures:

| Suite | Before | After |
|---|---|---|
| mechanics_smoke.gd | PASS | PASS |
| expansion_smoke.gd | PASS | PASS |
| plans_notes_smoke.gd | PASS | PASS |
| notes3_smoke.gd | PASS | PASS |
| notes4_smoke.gd | PASS | PASS |
| explorer_mode_smoke.gd | PASS | PASS |
| final_boss_smoke.gd | PASS | PASS |
| hover_graveyard_smoke.gd | PASS | PASS |

The new behavior suite passed. No baseline failures were observed in the eight guard suites.
Each test runs in its own headless process; the new suite has no capture or simulation output.

Validation used the current working tree, which already contained unrelated uncommitted game changes.
Those changes are excluded from the Session 1 commit. Results do not claim that the older committed
game revision alone supports these fixtures.

Only `github-publish` was modified. Mirror comparison and synchronization were skipped as requested.
No rendered viewport checks were run.
