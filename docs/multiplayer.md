<!-- Snapshot of the Google Doc on 14 October 2026. -->

[Editable Google Doc](https://docs.google.com/document/d/1lyxR52jlt4Z28vOycWLNDVeqEhnon1TOcE0jDcJ0EQo/edit)

# Midnight DRRills Multiplayer Design

Deck builder and first playable scope • Proposed rules • 14 October 2026

Multiplayer is planned as a separate mode with its own deck builder, saved decks and balance settings. The current game has a disabled Multiplayer button; the rules in this document are proposals for a future playable version, not implemented multiplayer features.

## 1 Design goals

Preparedness builds reliable formations and saves resources for Plans. Disasters trade deployed units for stronger threats. Both sides should have a viable path to victory without using identical resource systems. Multiplayer should reuse card identities and core effects while keeping roguelike progression separate.

## 2 Proposed deck construction

### Preparedness

Exactly 24 main-deck cards, combining Response units and utility spells.

A three-tactic loadout: Brace is always available, plus two chosen contingencies. All eligible tactics are available in the builder without singleplayer unlocks.

Deck feedback shows energy costs, unit versus spell count, type coverage and formation synergies.

### Disasters

Exactly 24 main-deck cards, combining base disasters and disruption spells, plus six evolution cards in a separate pile.

Deck feedback shows base units, evolution sacrifice requirements, sacrifice rewards, recovery options and deployment costs.

Evolutions must enter the hand before being played. Draw rates and reserved base-card hand space require playtesting so an evolution-heavy hand does not become unusable.

Start with a limit of two copies per card across the relevant deck, with one copy of a designated powerful finisher. Finisher designations must be explicit in the builder. These deck sizes and limits are initial test values; the extra evolution pile does not justify automatically giving Disasters fewer main-deck cards.

## 3 Access and separation from singleplayer

All multiplayer-eligible cards are available from the start. Singleplayer supplies, purchases, upgrades, floor buffs, character perks and saved runs do not transfer.

Use unupgraded cards for the first prototype. Keep eight battlefield slots: four per side.

Card names, types and effect logic remain shared. Mode-specific numbers may differ only when clearly labelled in previews.

Keep separate multiplayer deck storage and a versioned multiplayer ruleset. Singleplayer updates must not silently invalidate multiplayer decks.

## 4 Match flow

One player takes Preparedness and the other takes Disasters. A lobby prevents duplicate sides and lets players swap before confirming legal decks. A coin flip chooses the first player; the first-player role alternates each round.

- Both sides receive their round resources and resolve upkeep.

- The first player draws, plays cards and ends their playing phase.

- The second player draws, plays cards and ends their playing phase.

- Combat resolves once, with the first player attacking first. Temporary combat Plans then expire.

Preparedness banks unused energy when ending its playing phase. Drawing and playing do not trigger additional combat phases. Use the existing no-overkill, type effectiveness, Piercing, Sluggish and status rules as the initial baseline. Opening hands, draw rates, hero health, Disaster tension growth and action limits must be specified in the prototype rules before testing; enemy AI restrictions are not automatically player restrictions.

## 5 Economy baseline

Preparedness starts with 3 energy and grows toward a base cap of 7. Saving 2 unused energy grants 1 Plan, with a two-token holding limit and one armed tactic per round. Strong protection and disruption should compete with deploying units.

Disasters use tension for base deployment and spells, then deployed cards as evolution sacrifices. Avoid a large tension charge on top of multiple sacrifices. Selected sacrifice rewards and immediate value from expensive evolutions can compensate for lost attacks and blockers, but their singleplayer numbers require multiplayer testing.

Begin without battle adaptations, permanent run buffs, shops or map progression. This makes the two economies easier to compare. A later casual ruleset may add adaptations after the basic matchup is understood.

## 6 Builder and information design

Provide side selection, searchable card catalog, type and cost filters, saved deck names, clear copy counts, a rules preview and specific validation messages.

Offer at least one legal preset per side and a practice option. Show which cards belong in the main deck, evolution pile or contingency loadout.

Hide opposing hands and draw order. Scouting reveals only what its rule allows; sealing and cost disruption target held cards, not undealt piles.

Show deployed cards, public statuses, resources and separate graveyards. Live displayed stats must match the damage calculation.

## 7 Implementation stages

- Builder prototype: legal deck validation, presets and separate deck saves.

- Playable rules prototype: exercise both human-controlled sides locally with a privacy screen between turns, or another controlled test harness.

- Private online matches: create and join a room, side assignment, ready checks, synchronized actions and clear disconnect handling.

- Balance and reliability: test both sides, reconnects, surrender, invalid actions and hidden information before considering public matchmaking.

One match authority must validate costs, sacrifice targets, timing and card ownership and resolve randomness. Clients should receive only authorized information. A player-hosted prototype may suit casual testing, but ranked play requires an authority model that protects hidden information from both players.

## 8 Playtest and acceptance checklist

Compare faction wins while rotating players, decks and first-player assignments. Record match length, playable-card shortages and why games ended.

Measure whether evolving is worthwhile, whether expensive evolutions can be answered, and whether protection or disruption repeatedly prevents meaningful turns.

Verify deck limits, exact duplicate handling, separation of save data, Plan banking, sacrifice payments, effect expiry and no duplicate damage after reconnects.

Before the first release, confirm opening draws, hand limits, evolution draw schedule, action limits, hero health, finisher list, disconnect policy and whether characters confer any multiplayer perks.

Success means both decks retain their own strengths and weaknesses, each has several viable builds, and players can understand why an action or deck is legal. Equal win rates remain a playtest goal rather than a claim.
