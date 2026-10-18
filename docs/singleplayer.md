# Midnight DRRills singleplayer design

Midnight DRRills is a school-themed card roguelike. Steve uses Preparedness cards to survive Disaster encounters and reach the Midnight Warden. A run combines lane combat with route choices, card rewards and limited healing. The player guide covers controls; this document explains the rules and design choices.

## Goals and scope

Keep the two sides different. Preparedness should build a steady formation and plan answers. Disasters should gain pressure through sacrifice and stronger threats, while paying for the blockers they give up. Both sides need turns where choosing between deployment, protection and disruption matters.

A normal encounter should be short enough to keep the route moving. Cheap opening cards should give the player something useful to play. Shops, events and upgrades should improve a run without replacing its starting identity. Costs and effects should be visible before a choice is confirmed.

The current mode is singleplayer against the Janitor. Steve is the only available character. Three club leaders have deck definitions but remain disabled. Multiplayer has a separate [proposal](multiplayer.md) and is not playable.

## Battle structure

Each side has four lanes and a hero health pool. A unit attacks the opposing lane. A blocker stops ordinary hero damage even when the attack exceeds its remaining HP. There is no ordinary overkill.

A coin call decides the first side, which switches each round. Both sides play before one combat phase; the first side attacks first. Upkeep and resources resolve at round start. Plans last one combat. The final boss announces a separate pattern after Steve's attacks.

Response starts with three hand cards, an eight-card hand limit and 3 energy capacity. The cap normally grows by 1 after combat to 7 before buffs. Choosing the normal draw costs 1 energy; opening or cancelling its picker is free. Extra draws obey the hand limit.

Disasters pay Tension for base units and spells. Evolution cards are drawn from a separate pile into the shared enemy hand. Playing an evolution sacrifices deployed allies; it does not charge another Tension payment. Sacrifices remove attacks and blockers, so a larger unit must justify the lost formation.

An empty draw pile does not end a battle while usable hand or board cards remain. Exhaustion is a loss when a side has no usable cards left. Hero health reaching zero also ends the battle.

## Types and damage

Type effectiveness applies to the unit hit. A strong matchup doubles damage; a weak one halves it; other pairings are neutral.

| Attacker | Strong against | Weak against |
| --- | --- | --- |
| Evac | Earthquake | Flood |
| Douse | Fire | Typhoon |
| Clearance | Flood | Earthquake |
| Brace | Typhoon | Fire |
| Earthquake | Clearance | Evac |
| Fire | Brace | Douse |
| Flood | Evac | Clearance |
| Typhoon | Douse | Brace |

A matching adjacent ally gives a unit 1 extra attack. Matching on both sides does not double that base bonus. Adaptations can change formation bonuses. Strength adds attack before effectiveness. Attack cannot fall below zero; damage prevention and minimum-hit rules are handled separately.

Piercing bypasses a blocker's armor reduction and can also hit the hero. An Armored blocker prevents that hero hit even if it dies. Barrier and Plan protection still apply. Fierce adds 2 to hero hits. Rampaging adds 1 against a card when attacking as the second side. Sluggish attacks on alternating eligible opportunities, starting with the first.

Double-strike eligibility is checked once at attack start. Each strike resolves damage, on-hit effects, healing, retaliation and Bleed. A surviving redirected blocker stays the target. If the first strike clears a lane, the next can hit the hero. A dead attacker cannot continue.

Burn deals its stacks at round start and then halves them, rounding down. Poison deals its stacks and then loses 1. Bleed deals its stacks after an attack and then loses 1. Fixed status damage bypasses Armored and Fragile. Regeneration happens afterward and cannot revive a dead unit. On-hit statuses only affect a surviving blocker.

## Cards, targeting and recovery

Base definitions are stored in [starter_deck.json](../new-game-project/data/starter_deck.json), [response_expansion.json](../new-game-project/data/response_expansion.json), [disaster_deck.json](../new-game-project/data/disaster_deck.json) and [disaster_expansion.json](../new-game-project/data/disaster_expansion.json). Use those files for exact costs, stats, effects and counts. Do not maintain a second full stat table here.

Utilities have no unit ATK or HP. Supply Cache, Emergency Exit, encounter signatures, event variants and boss entities are defined in scripts. JSON alone does not list every card the game can create.

Board effects use direct card or lane selection. Pile and hand choices use a picker. Starting a choice must not spend its card or resources. Confirming a valid choice pays once; cancelling leaves it available. A summon that offers optional relocation stays deployed when movement is skipped.

Seals and taxes target held cards, including held evolutions, rather than undealt piles. Seals expire at the indicated round. Taxes last through the current and next round and cap at 2 extra cost. Target-based status bonuses require a blocker and count the named status stacks.

Only Response has a graveyard. Recovery Detail returns an eligible destroyed unit once per battle, preserving upgrades and clearing temporary effects. Relief Crew gains up to 2 Barrier from destroyed allies still in that graveyard.

## Plans and adaptations

Unused energy can buy a delayed answer instead of another card. Automatic banking exchanges 2 energy for 1 Plan token when ending a turn, at most once per round. Hold up to two tokens and commit one tactic per round. Brace and Coordinated Response start unlocked; elite and boss rewards can teach the others.

Coordination picks one ally and the nearest deployed ally on either side. Types can differ and empty lanes do not interrupt the search. An intervening ally ends that direction's search. Other tactics offer healing, drawing, temporary attack, Taunt avoidance, hero protection or a one-use extraction from lethal damage.

Battle adaptations appear every fifth round and expire at encounter end. Permanent floor rewards last the run. Overclock increases capacity and growth but raises incoming damage by 50%, rounded up. Blood Pact gives 2 Strength, then destroys deployed units that did not kill a card during combat. Hero hits and resting do not qualify.

## Run progression

Steve starts at 20 HP with 35 supplies. Each eleven-stage floor branches toward a boss. Every route includes at least four normal or elite battles. Connected rooms unlock after the current room and rewards finish.

Normal victories give 20 supplies, elite victories 35 and ordinary boss victories 60. Card rewards keep three fixed offers through inspection and Continue. Claiming selects one exact copy; skipping is allowed. The final encounter on floor three is the Midnight Warden, whose shielded pillar phase and announced lane attacks replace ordinary enemy deck play.

Shops offer fixed stock and repeatable healing. Infirmaries offer healing, an upgrade or removal. These services compete for supplies and route choices. Card removal stops at a five-card collection.

Each copy can upgrade twice. Sorting and previews do not change the collection. Confirmation must preserve the selected duplicate's identity.

Normal enemies use less precise placement and tighter evolution restrictions than elites and bosses. First-floor normal encounters limit the Janitor to one action through round 3, then two. Early base piles limit special-effect cards. Elite decks share one element. Sacrifice choices consider the resulting formation rather than judging the new unit alone.

## Saving and ownership

A battle uses copied collection definitions. Unit damage, statuses, seals and temporary costs do not change the permanent collection. Run HP, supplies, upgrades, rewards, map progress and tactic unlocks persist between rooms.

The save system writes stable decisions and player turns. It does not serialize animation coroutines. Continue restores pending offers and the last safe battle state. Returning to the title retains the run; confirmed abandonment or defeat clears it. Closing mid-animation resumes the previous stable checkpoint.

Battle snapshots are a separate development tool, not the current save format or live state owner. The [refactor plan](refactor-plan.md) and [refactor notes](refactor-notes.md) describe that migration. Keep behavior changes separate from extraction work.

## Design decisions

Battle adaptations and permanent floor rewards are player-only. Old saves keep any enemy buffs already stored. Normal wins intentionally heal up to 3 HP. Elite and boss wins do not grant that healing. Advancing through `next_floor` separately heals up to 5 HP. Both paths stop at maximum HP and remain part of the balance.

Drops use the visible friendly slot under the cursor. The normal draw picker costs 1 energy only when a card is chosen. Opening or cancelling it is free. Playing that card still costs its listed energy. Attacks cannot target allies, and shared effect text uses the actual upgraded amounts.

The twelve-card starter has eleven 1-cost cards and one 2-cost Evacuation Route. It keeps cheap units weak so the early game has playable blockers without free strong units.

An adaptation that reduces unit HP leaves already deployed units unchanged by all its unit effects. Held cards and later deployments receive it. These exemptions stack and survive Continue.

Containment Lance gains 2 attack against a target with 3 combined Burn, Poison and Bleed stacks. Last Responder gains 2 against a target with 2 Bleed. Hazmat Team costs 2. Venom Surge gains 2 against 3 Poison. These target conditions do not apply to open lanes.

Elite reserves share one Disaster element, repeating cards where needed to keep their reserve sizes. Basic unit upgrades add stats first and new draw, Burn, Poison or Armor effects at tier two. An existing ability can improve at tier one.

An Armored blocker stops the Piercing hero hit, even if the blocker dies. It takes full Piercing unit damage; Barrier and Plan protection still apply. Utilities have no unit ATK or HP. Support units keep their stats.

Ordinary 1-Tension units and 1-sacrifice evolutions have at most 2 printed attack including starting Strength, and 2 HP. They skip flat encounter stat scaling. Scripted boss hazards instead show a BOSS badge without a summon cost.

Card faces use effect icons; inspection holds the full rules. Player battle buffs are labelled Adaptations and permanent rewards Augmentations. The status strip counts the whole collection, not the draw pile. Utilities also count toward their affinity, so those counts overlap. The log screen and banking checkbox are removed; internal event history and the saved automatic banking setting remain.

The replacement Disaster encounter icon is still pending. Its reference image or local path has not been supplied. Keep the existing icon's dimensions and anchor when the reference arrives.

## Current limits

Balance needs repeated playtests across routes, encounter tiers and buff combinations. Regression checks establish rules, not equal win rates or a fair full run. Test strong combinations and expensive evolutions against the cost of lost lanes.

Evac rescue, Douse control, Clearance threat removal and Brace defense are design directions, not enforced card-pool restrictions. Changing access to Burn, Poison or Piercing needs a separate balance decision.

Final title art, card illustrations and player/Janitor models are unfinished. Card art windows stay blank and character positions use empty markers. Keep the supplied classroom's [asset notes](../new-game-project/assets/supplied_classroom/README.md) with its resources.

Extra characters and multiplayer need separate work. The encounter icon needs its reference before replacement. The singleplayer game does not implement multiplayer balance, reconnects or hidden-information security.
