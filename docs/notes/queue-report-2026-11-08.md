# Queue report 2026-11-08

Worktree: wt-queue, branch queue-2026-11-08 (from main-1). Nothing pushed or merged. Flags unchanged, TYPE_CHART untouched.
The decisions doc (claude/decisions-2026-11-07-discord.md) was not on disk or in Drive; every call below is mine.
Full run at the end: 128 suites, 117 pass. The other 11 are exactly the known list (balance_synergy, disaster_draw_button,
evolution_draw_choice, evolution_draw_choice_ui, lan_title, lan_unavailable, lan_utility_effects, versus_batch2_state,
versus_deck_step exit 1; versus_smoke, versus_batch1 timeout). No new failures.
Old-chart tests that already failed on main-1 were fixed to the new numbers: expansion, mechanics, card chart cases in
collection_shop_upgrades_and_ai, character_decks_map_and_combat.

| # | Step | Files | Tests | Result |
|---|------|-------|-------|--------|
| 1 | Warden guards | final_boss.gd, game_3d_manager.gd | warden_guards (new), final_boss, warden_art | DONE (4663b50) |
| 2 | Action cap removed | game_3d_manager.gd + 5 tests | battle_behavior, expansion, explorer_mode, hover_graveyard | DONE (c712f69) |
| 3 | Toxin Hunter; Coordinated Response | response_expansion.json + tests | discord_fixes_*, card_rules (hash) | DONE (d1f6c24) |
| 4 | Heat Seeker, Lance, Last Responder | response_expansion.json | own_hit_conditions (new), balance_* | DONE (4da1dd9) |
| 5 | Adaptation numbers | battle_rules.gd + 3 tests | balance_rules, blood_pact, collection_shop | DONE (65d0b5b) |
| 6 | Sacrifice highlight | card_3d.gd, disaster_seat.gd | sacrifice_marks (new) + screenshot | DONE (484556f) |
| 7 | Evolution offer layout | evolution_choice.gd | evolution_offer_layout (new) + 2 screenshots | DONE (3f89517) |
| 8a | LAN A1 relocation | lan_utility_choice.gd, preparedness_actions.gd | lan_relocation (new) + LAN suites | DONE (32610fe) |
| 8b | LAN A8 view refresh | lan_board_3d.gd | lan_view_refresh (new) + LAN suites | DONE (14c092f) |
| 9 | Player 2 gaps | lan_view.gd, lan_board_3d.gd (reverted) | see below | BLOCKED |
| 10a | Hot-seat Crosswind drag | disaster_seat.gd, disaster_relocation.gd | crosswind_drag (new) | DONE (226912c) |
| 10b | A12 validators | lan_validators.gd (new) + 3 scripts | lan_validators (new), all LAN suites | DONE (21efa15) |

## Step 1 notes
Night Watch strikes the Response tile across from it for 1 when the Janitor takes damage. Hall Monitor strikes its tile on
every second Response card played. An empty tile takes nothing. Elements: Night Watch Earthquake (Brace counters),
Hall Monitor Typhoon (Evac counters).

## Step 2/3/4 notes
Single-player Disaster actions = tension only (Resource Surge no longer adds an action). Toxin Hunter threshold 3 to 2 in data.
Coordinated Response was already exact (adjacent, no gap); existing test covers it. Own on-hit statuses and thresholds:
Heat Seeker burn 2, threshold 1. Last Responder bleed 2, threshold 1. Containment Lance poison 3, threshold 2. Each is sized
to survive one round of decay (burn halves, poison -1) so the condition is on for the next attack.

## Step 5: old and new
| Card or adaptation | Old | New | Reason |
|---|---|---|---|
| Glass Cannon / Bold Strategy (glass) | +2 attack, -1 max health | +2 attack, -2 max health | harsher price for the big attack |
| Blood Pact | 2 Strength | 1 Strength | still die without a kill, so reward shrinks |
| Patient Formation | regen 2 | regen 1 | regen was strong for a no-cost reward |
| Close Ranks / Buddy System (formation) | +2 damage to matching neighbors | +1 | easy to trigger |
| Signal Beacon | +1 draw | +1 draw, -1 resource capacity | free permanent draw was too good |
| School Bulwark | +2 max health, -1 attack | +1 max health, -1 attack | smaller reward |
| Field School | +1 resource, +1 draw, -1 max health | same, -2 max health | two rewards, one small cost |
Unchanged: Fuel the Flames, Toxic Pressure, Deep Cuts, Hazard Manual (and every other card).

## Step 9: BLOCKED, reverted
Built: battle log, own deck list and own graveyard in the view, with L, D, G overlays on the client (13-check test saved
as docs/notes/queue-blocked-lan_lists_smoke.gd.txt, passed). Existing privacy suites then failed:
- lan_evolution_privacy: "Disaster cannot see Preparedness hidden zones" x49
- lan_utility_privacy: "idle: no deck or graveyard face in the view", "the Disaster view hides PGRAVE / s_tutor / s_recover"
- lan_prep: "disaster view hides PHAND_a"; lan_utility_picks: "the Disaster view hides s_rally"; lan_finish_full_match: no Disaster view holds ZzSecretSpell
- lan_utility_rpc: "the Disaster view over the wire is clean"
Cause: the host battle log names the other seat's private cards, so it cannot go in either view as is. The idle-view privacy
rule also forbids deck and graveyard faces outside an open choice. A fix needs per-seat filtered log lines and an on-demand
request message (new message kind), which I did not start. Not done either: Disaster draw step, inspect lines for
conditional abilities and Blood Pact (need host state in the view).

## Screenshots (wt-queue/docs/notes/queue-shots/)
sacrifice-marks.png, evolution-offer-1280x720.png, evolution-offer-1920x1080.png

## BY EYE
Sacrifice outline and tag readability from the far seat; evolution offer hover glow; Crosswind drag feel (no drag ghost, it
is press on ally, release on lane); Lane Marshal pick on a real LAN client.

## Merge commands (one per DONE step, in order, from github-publish on the target branch)
git cherry-pick 4663b50
git cherry-pick c712f69
git cherry-pick d1f6c24
git cherry-pick 4da1dd9
git cherry-pick 65d0b5b
git cherry-pick 484556f
git cherry-pick 3f89517
git cherry-pick 32610fe
git cherry-pick 14c092f
git cherry-pick 226912c
git cherry-pick 21efa15
Whole queue: git merge queue-2026-11-08
