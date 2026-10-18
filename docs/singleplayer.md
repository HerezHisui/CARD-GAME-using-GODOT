<!-- Local singleplayer reference updated 16 October 2026. -->

[Editable Google Doc](https://docs.google.com/document/d/10zsNwhLedizfDTOK4vlviINSWIs5Ac2iJCXESA2Og0c/edit)

The linked Google Doc is a separate copy. This local revision includes the October 15 and 16 work.

# Midnight DRRills Singleplayer Design and Development History

Rules and development record updated 16 October 2026

Midnight DRRills is a school-themed card roguelike where Steve uses Preparedness cards against Disaster encounters and the Janitor. This reference covers the current singleplayer rules, development changes, card and buff catalogs, and unfinished work. It includes notes /5, the October 15 presentation updates and the October 16 resource cleanup.

Status language: Implemented means present in the current project. Playtest means implemented but still requiring balance feedback. Planned means recorded for future development. The Multiplayer button is currently a placeholder; the multiplayer proposal belongs in its separate document.

## Document contents

- Original vision and scope

- Development history

- Current singleplayer rulebook

- Current status and remaining work

- Card catalog

- Buff and contingency catalogs

- Verification and source record

## Original vision and scope

The initial design established two asymmetric sides rather than two identical decks. Preparedness, also called Response, uses growing energy to deploy units and utility cards. Disasters use a separate evolution pile and sacrifice deployed cards to summon stronger threats. The run gives the player a static starter deck, then expands it through battles, events and shops.

- A procedural board-like map leads through normal battles, elite battles, upgrades, events, shops and bosses. Every route should involve combat before reaching a boss.

- Each side has four battlefield slots, a separate hero health pool, and clear resource bars. Preparedness is displayed on the right and Disaster tension on the left. An End Turn button sits at the bottom right.

- Response types are Evac, Douse, Clearance and Brace. Disaster types are Earthquake, Fire, Flood and Typhoon. Each matchup has strong, weak and neutral effectiveness.

- A coin flip determines the initial first player. The first-player role alternates each round. Playing and drawing phases lead to ordered combat.

- Cards can have modifiers, latent abilities, status effects and adjacency synergies. Utility cards resolve an effect and leave play.

- Cards use empty illustration windows until final art is provided. Card backs use four corner element symbols and a ring motif.

- The original multiplayer idea lets one player choose Response and the other Disasters with access to the full card pool. Multiplayer implementation remains separate from the current singleplayer run.

### Complete type effectiveness

| Attacker | Strong against 2x | Weak against 0.5x | Neutral against 1x |
| --- | --- | --- | --- |
| Evac | Earthquake | Flood | Fire, Typhoon |
| Douse | Fire | Typhoon | Earthquake, Flood |
| Clearance | Flood | Earthquake | Fire, Typhoon |
| Brace | Typhoon | Fire | Earthquake, Flood |
| Earthquake | Clearance | Evac | Douse, Brace |
| Fire | Brace | Douse | Evac, Clearance |
| Flood | Evac | Clearance | Douse, Brace |
| Typhoon | Douse | Brace | Clearance, Evac |

## Development history

The milestones below follow the development requests in order. Later rules replace earlier versions where the design changed.

### Foundation

Procedural run map, battle nodes, elite and boss encounters, card rewards, deck viewing, upgrades, events, shops, board health and resource UI, empty art windows and smoother presentation.

### Combat expansion

Removed ordinary overkill damage so Piercing has a distinct role. Added Sluggish, Burn, Poison, Bleed, Strength, draw, tutoring, scouting, sealing and cost disruption. Fixed map-key toggling and post-defeat starting flow.

### Economy and encounters

Added sorting and upgrade previews, multiple shop purchases, smarter elite and boss AI, battle-only adaptations, permanent floor rewards, tradeoffs, more cards, stronger sacrifice costs, relocation effects and a battle Quit option.

### Run and deck variety

Lengthened floors to 11 stages, guaranteed at least four battles per route, capped upgrades at two per copy, added conditional damage and double strikes, unique upgrades, tiered shop prices and formation-aware sacrifice decisions. Reduced enemy health and reserves.

### Regular encounters and usability

Nerfed regular enemy actions and precision, restricted their evolutions, added separate graveyards and stabilized hand hover. Other cards do not rise while a card is being dragged.

### Notes section 1

Added the school environment, preparation cards and a predictable three-phase final boss. Steve Student became the available starter character; the three club leaders remain unavailable.

### Notes section 2

Reworked Overclock, board inspection and combat logging; improved Evacuation Route; repaired repeated Sealed labels; added exact-copy removal in shops and rests; introduced the playable Plans prototype and return-to-title route.

### Notes section 3

Added six unlockable contingencies, direct board dragging and clicking, five additional events, actual enemy hands and hand-only sealing. Removed direct restart shortcuts in favor of the starting screen.

### Notes section 4

Removed the floating Janitor hand count, broadened Coordinated Response, added newest-card sorting, a full-screen starting menu, a disabled Multiplayer entry, saved-run continuation and abandonment, a vertical map and live card stat updates.

### Economy balance pass

Lowered Preparedness base energy ceiling to seven, capped Barrier stacking, increased several utility costs, made taxes temporary and capped, removed extra evolution tension payment, and added selected sacrifice refunds and expensive-evolution entry value.

### Notes section 5

Implemented battle-only graveyard access, explicit HP and supplies labels, visible card-removal costs, a full-screen map outside combat, four help categories and three eased camera views. Rest removal remains free; shop removal displays its supplies cost.

### October 15 presentation

Added a full-screen Heads/Tails call and animated toss, centered card rewards, enlarged card inspection with outside-click dismissal, card and menu transitions, turn and victory banners, and a framed slate board without zone labels. Continue preserves pending coin choices and outcomes.

### Supplied classroom

Adapted the supplied classroom around the marked rear play area and a dedicated table. The active room retains 59 mesh instances, including the table, and 12 chairs outside the cleared strip. Player and Janitor positions are empty markers. Forward+ lighting, bloom, anti-aliasing and clarity grading remain active.

### October 16 optimization

Removed unused environments and duplicate resources, shared repeated classroom materials, bounded fallback card-face checks and avoided rebuilding identical enemy backs. The active project source is about 7.82 MB. A separate whole-folder cleanup reduced the local workspace from 5.64 GB to about 345 MB, including retained Git history.

The October 15 presentation work was pushed to main at commit 605b6b5401416906e330f4d1bfb502fb34cba9fe. Resource cleanup and runtime optimization were pushed at commit 04d88c77eb58049dec813bab83eac2dd74355ed6.

## Current singleplayer rulebook

Open project.godot in Godot 4.7 and run the main scene. The game begins on a title screen with Singleplayer, a disabled Multiplayer placeholder, How to Play, and Quit. A saved run instead offers Continue and Abandon. Start opens character selection; preview a starter deck before beginning. Future start-screen artwork can be placed at assets/title_screen.png; the title screen uses it automatically after Godot imports it. All card art windows remain blank.

### The run

Choose an illuminated starting room, then follow connected rooms toward the Janitor boss. Each floor has eleven stages and three branching lanes, merging at the boss. Mandatory combat rows ensure every route includes at least four normal/elite battles before the boss. Scroll upward through the map; it follows your current progress when reopened. Layouts vary by run; every room has a route forward. Normal encounters favor one disaster element, elites have tougher cards and a Hallway Guardian evolution, and bosses have more health and a Midnight Cataclysm evolution. Later floors scale difficulty.

Player health, supplies, collected cards, and upgrades persist between rooms across sessions through automatic checkpoints. Each battle begins with a fresh shuffled copy of the collection. Health damage and sacrifices affect those battle copies only. Unfinished runs save locally at stable player turns and room decisions. Multiplayer is a disabled placeholder.

Battle wins grant supplies and a choice of one of three cards. Workshops improve one card; infirmaries offer healing or an upgrade. Supply rooms allow multiple purchases from fixed stock and repeatable healing until you leave. Events have explicit risk/reward choices. Defeat ends the run. Each boss win offers a permanent floor buff before advancing to a harder floor.

### Controls

- Drag a hand card onto an empty lower Response slot. Right-click cancels a drag.

- Draw once during the draw phase using the lower-right draw button.

- At encounter start, call Heads or Tails on the full-screen coin event. A matching toss gives you the first turn; otherwise the Janitor plays first. The starting side alternates each round afterward. Space or End turn submits your turn.

- W steps from Room to Table to Overhead; S steps back. Battles start in the central Table view. Transitions ease position, rotation, distance and field of view. Room view hides your hand to show the opponent and classroom; return to Table to play. Camera changes are blocked during combat, dragging and board targeting.

- D opens the collection, unordered remaining draw pile, hand, and deployed Response cards. Sort by Name, Type, Cost, Attack, Health, Modifier, or Recently added, in either direction. Recent sorting defaults to newest first. Sorting never changes draw order or your collection.

- M opens and closes the school map during battles. Between encounters, the full-screen map stays open and the board is hidden. Next rooms unlock after completing the encounter and reward choice. Deck and menu overlays return to this map when closed.

- Esc opens the menu. Deck, map, and menu overlays pause an active encounter. Close or Resume continues it.

- Return to starting screen saves the unfinished run. Continue resumes it; Abandon clears it after confirmation and enables a fresh Singleplayer game.

- The battle menu includes Quit game, which closes the game. Stable decisions and player turns are saved to disk; closing during an animation resumes the last stable checkpoint.

### Workshops and shops

Workshops have the same sorting controls as the deck browser. Preview upgrade shows the current card beside its upgraded version; only Confirm upgrade changes the collection. Every card copy can upgrade at most twice, shown as 0/2, 1/2, or 2/2. Evac gains attack and on-play draw, then health and a cheaper energy cost. Douse gains attack and Burn, then health and healing after each strike. Clearance gains attack and Poison, then health and +2 attack against targets with three harmful status stacks. Brace gains health and stronger armor, then health and retaliation. Spells first become cheaper; later upgrades strengthen draw, seal, tax, rally, or cleanse. Movement, tutor, and scouting upgrades refund energy instead. Zero-cost spells can improve their abilities. Duplicate cards retain their original identity when sorted, so only the selected copy changes.

Shops offer four distinct cards, each with one copy in stock. Buying one marks it sold and keeps the shop open; remaining stock does not reroll. Healing can be purchased repeatedly until health is full or supplies run out. Labels show actual healing and the supplies spent, for example First aid · +1 HP · -15 supplies when only one health is missing. Full-health healing is disabled. Removal shows Destroy 1 card · -30 supplies; infirmary removal is explicitly free. The room is completed only when you press Leave shop. Infirmaries also offer an exit if you prefer to skip their service.

### Cards

The original twelve-card starter deck and existing disaster cards are preserved. Card illustration windows are deliberately empty. Assign future illustrations in the ART dictionary in scripts/card_3d.gd. Backs have four corner element marks and a central double ring.

Evac counters Earthquake, Douse counters Fire, Clearance counters Flood, and Brace counters Typhoon at 2x damage. Weak matchups deal half damage. Two adjacent deployed cards of the same element receive +1 attack (not cumulative across both neighbors). Armored reduces incoming attack damage by one (minimum one), Fragile adds one, Regenerating heals up to maximum health, Fierce adds two to hero hits, and Rampaging adds one when attacking a card as the second side of the round.

Normal attacks never deal overkill/overflow damage to the opposing hero. Even a one-health blocker stops the entire hero hit. Piercing damages the blocker normally and also deals the attacker's effective attack plus adjacency bonus to the opposing health pool. Type effectiveness applies to the blocker only. Fierce adds two to this hero hit. An open lane hits the hero once, including for Piercing cards.

Sluggish attacks the first round it can attack, then rests the next round, repeating. Its timing is per card, rather than based on odd/even global rounds. Strength adds to attack before type effectiveness and lasts while the card exists. Temporary card statuses and costs do not alter the permanent collection.

Burn deals its stack count in damage at the start of the round, then halves its stacks, rounding down. Poison deals its stack count at the start of the round, then loses one stack. Bleed damages its card by the stack count after that card attacks, then loses one stack. Skipped attacks do not trigger Bleed. These fixed status hits bypass Armored and Fragile. Regeneration happens after status damage; dead cards cannot regenerate. On-hit status effects apply only to a surviving blocker.

Reward and shop pools include utility cards: Supply Cache draws two cards up to the hand limit; Emergency Exit lets you drag a friendly deployed card into an empty Response slot. Both spend energy and disappear after use. Emergency Exit returns to hand without spending energy if no deployed ally exists. Hover over deck previews for rules.

The first expansion added thirteen Response cards and eight Disaster cards; further additions are included in the current catalog. Response units include Needle Team (Piercing), Heavy Loader (Sluggish), Steam Team (Burn), Shard Barrier (Bleed), Hazmat Team (Poison), Supply Runner (draw one on play), and Drill Captain (two Strength). Steve retains the original twelve-card deck; themed club decks are reserved for future characters. New Response cards also appear in rewards and shops. Disaster encounters include matching status-based units, Piercing and Sluggish evolutions, and disruption spells.

Targeted Response spells are cast by dragging them onto an empty Response slot, then choosing a target:

- Search and Rescue: choose an unlocked card from your draw pile and put it into your hand. Displays an alphabetic list, keeping pile order hidden.

- Safety Lock: choose a card currently in the opposing hand, including held evolutions. It cannot be played for this round and the next. Already deployed units are unaffected.

- Hazard Forecast: reveal the Janitor's hand for this encounter. Reopen it through D afterward.

- Containment Order: raise one opposing hand card's cost, including held evolutions, by one for this round and the next. Repeated taxes cap at +2 cost. Disaster evolutions require one more sacrifice; base disasters and utility spells require one more tension. Response costs remain energy-based.

- Rally the Team: give a deployed ally two Strength.

- Decontaminate: heal a deployed ally by three and remove Burn, Poison, and Bleed.

Rally and Cleanse target allies by clicking them on the board. Emergency Exit uses direct board dragging. Hand and draw-pile selectors pause play; board targeting blocks turn submission until completed or cancelled. Cancel or Esc keeps the spell and energy. No-target casts return to hand. Disaster disruption spells can seal only Response hand cards or increase a Response hand card's energy cost. Seals expire automatically when their indicated round begins.

### Global adaptations

At the start of rounds 5, 10, 15, ... of each encounter, choose one of three randomly offered battle-only adaptations for your side. The Janitor does not receive an automatic adaptation from this pool. The battle pauses until you choose. Deck viewing preserves the exact offers. Adaptations expire when the encounter ends.

There are fifteen battle adaptations. Strong options have explicit tradeoffs: Glass Cannon adds two attack but removes one maximum health; Overclock grants two capacity immediately and doubles ordinary capacity growth to two per round, but increases incoming damage by 50% (rounded up); Blood Pact adds three attack but applies two Bleed on selection and entry; Patient Formation regenerates two health but makes units Sluggish; Toxic Ward strengthens Poison while reducing attack; Close Ranks rewards matching neighbors but penalizes isolation; Piercing Formation grants Piercing while reducing attack; Bristling Defense retaliates for one fixed damage while reducing health. Smaller stat, status, and draw buffs remain available without drawbacks.

After the first two floor bosses, choose one of three permanent run rewards from an eight-option pool. The Janitor does not receive an automatic reward from this pool. These stack across later battles and floors; a new run clears them. Examples include Signal Beacon (extra draws), School Bulwark (health for reduced attack), Buddy System (adjacency bonuses with an isolation penalty), Field School (resources and draws for less health), Hazard Manual (stronger statuses for reduced resources), and Infirmary Network (hero healing for reduced unit attack).

Battle adaptations and permanent rewards combine during a fight. Health stays at least one; attack stays at least zero; resource capacity stays at least one. Negative draw bonuses can reduce normal draws to zero, but spell and unit-triggered draws still work. Response resource bonuses increase starting capacity, its upper limit, and positive cap growth. Disaster bonuses alter tension and the action limit, between one and five actions. Menu summaries distinguish Battle buffs from Run buffs for both sides.

### New units and smarter encounters

Six more Response units and six more disasters join the pools. Lane Marshal and Rescue Crane optionally move another deployed ally after being played: drag the ally directly onto an empty lane. The played card stays where it was summoned. Skipping movement keeps the summon and its energy payment. Crosswind lets the Janitor relocate an ally if a better lane is available. Field Medic and Warm Front heal other allies by two; Drill Leader and Aftershock Choir grant other allies one Strength. Recovery Team and Drain Vortex heal after attacking. Cutting Crew, Black Squall, and Worldbreaker add stronger Piercing/status combinations.

Major original evolutions now need two sacrifices; Inferno, Tsunami, Sleeping Fault, Drain Vortex, Black Squall, and the boss's Midnight Cataclysm need three. Worldbreaker needs four. Needle Gale remains a smaller one-sacrifice evolution. Elite Guardian needs two. Sealing and cost disruption still apply to evolutions.

Elite and boss AI compares cards and lanes using effectiveness, survival before counterattack, immediate hero lethals, defensive coverage, and synergies. It evaluates sacrifice combinations and declines evolutions that discard more board value than they gain or expose lethal lanes. Disruption targets and buff choices are ranked rather than random. All encounters use board-aware sacrifice decisions. Regular enemies act at most twice per turn before buffs (four-action buff cap), use less precise placement, and only consider evolutions from round three when their board is full. They do not gain the free round 4-6 spawn modifiers. Elite/boss tactical placement and three-action base/five-action buff cap remain unchanged. Evolution planning compares the entire formation before and after sacrificing, including lost blockers and matching-neighbor bonuses. It penalizes losing a numerical advantage and compares filling an empty lane against evolving. A valuable field advantage can be kept without sacrificing; a winning Piercing evolution can still be chosen. AI uses the public board and its own available cards for battle planning; it does not inspect draw-pile order.

Empty draw piles do not immediately end a match while cards remain in hand or on board. A side with no usable cards left loses. Preparedness begins at three and its cap grows each round; Disaster evolutions retain the sacrifice mechanic and separate evolution deck.

### Starter characters

Steve (Student) is available with the original 12-card deck and +1 unit health. His perk lasts the run and stacks with floor rewards. Three themed club leaders are disabled and marked Available soon; their deck definitions remain ready for future development. Older character selections safely reset to Steve.

- Steve, Student: original mixed Response deck; +1 unit health.

- Evacuation Club Leader (Available soon): Evac formations, movement, draw and tutoring.

- Science Club Leader (Available soon): Douse/Clearance status combinations.

- Safety Club Leader (Available soon): armored Brace formations, Strength and healing.

### Encounter and shop balance

First-floor normal/elite/boss health is 18 / 24 / 28. Normal health increases by two each additional floor; elite/boss health increases by three. Base-card reserves are capped at 18 / 21 / 22; evolution reserves at 8 / 14 / 15, including elite/boss signature cards. Regular encounters only use evolutions requiring one or two sacrifices. Encounters still favor a disaster element and retain varied cards.

Shop cards cost 20, 30, 40, or 50 supplies based on cost, stats, modifiers and abilities. Stronger cards cost more; Sluggish reduces the price score. Prices and affordability appear on each card. Stock stays fixed, sold cards cannot be bought again, and first aid remains repeatable at 15 supplies.

### Conditional cards

Four new cards join each side. Conditional effects count stacks, not the number of different statuses. "Harmful status" means total Burn + Poison + Bleed; Strength is counted only when explicitly named. Effects require at least the stated threshold.

- Heat Seeker: +3 attack against a target with 3+ Burn.

- Toxin Hunter: attacks twice against a target with 3+ total harmful stacks.

- Momentum Team: attacks twice with 2+ own Strength.

- Last Responder: +2 attack while carrying 3+ harmful stacks.

- Ash Predator: attacks twice against a target with 3+ Burn.

- Venom Surge: +3 attack against a target with 2+ Poison.

- Pressure Break: attacks twice with 3+ own Strength.

- Fracture Hunter: +2 attack against a target with 3+ harmful stacks.

Bonus attack is applied before type effectiveness. Target conditions require a blocker. Double-strike eligibility is checked at the start of the attack; each strike applies hit effects, healing, retaliation and Bleed independently. If the first strike removes a blocker, the second can hit opposing health through the now-open lane. A card killed by Bleed or retaliation cannot make its second strike. Sluggish still limits the rounds on which it attacks.

### School setting and final boss

The classroom uses the supplied rear play-area model with its original PBR materials, windows, lockers, desks and chairs. A dedicated table occupies the marked area. The playable room has 59 mesh instances, including that table, and retains 12 chairs outside the cleared strip. The eight card lanes sit on a framed slate board. Camera paths stay inside the finished room, with a dark exterior behind the windows. Desktop Forward+ rendering uses contact shadows, indirect lighting, light haze, 4x MSAA and temporal anti-aliasing at full rendering resolution. Bloom and restrained clarity grading affect the world beneath the HUD. The optimization preserves all geometry and 33 original textures without resizing. Player and Janitor positions are empty markers; card illustration windows remain blank.

The Midnight Warden is the final encounter on floor three, with 34 HP. Floors one and two provide preparation and still award permanent floor buffs. Steve plays and attacks before the final boss's announced special pattern resolves. The boss uses a fixed pattern instead of random enemy decks.

- Phase 1: odd rounds use Blade Rush (1 damage and 1 Bleed in Response lanes 1 and 3), then Punishment in lane 2. Even rounds summon a Shackle and use Punishment. Punishment deals 3, or 4 while a Shackle is present, and applies Healing Reduced for two rounds. An empty targeted lane takes at most 2 hero damage.

- Phase 2: reaching half health clamps damage at 17 HP and shields the boss. Shield Pulse (1 to deployed units) and two circuit pillars appear on the following round, providing a warning turn. Destroy both pillars to remove the shield. A guardian redirects ordinary attacks against pillars; Ignore Taunt and area damage bypass it. Each pillar destroyed discards at most one hand card. While pillars stand, one temporary Static Echo enters the hand each round: casting pays 1 HP and draws 1; leaving it uncast pays 1 HP and discards it at round end. A full hand pays the same penalty without adding a card. Curse payment bypasses Barrier.

- Phase 3: temporarily seal one hand card (skip sealing if the hand is empty) for two rounds, apply 1 Bleed to all deployed allies, and strike lanes 1 and 3 for 2. A newly entered phase gives a response turn before its special attack.

New preparation cards: First Aid Herb removes Bleed and heals 1 across deployed allies; Restoration Tablet restores healing and heals 2; Barrier Generator grants 2 attack-damage protection to deployed allies and the player health pool; Alarm Sweep deals 2 fixed damage to all enemy units. Containment Lance and Silent Runner ignore guardian Taunt. Later shops reliably stock Barrier Generator and Alarm Sweep. These abilities support the two-upgrade system.

Healing Reduced halves healing (minimum 1) until it expires or is removed. Barrier absorbs attack damage and is consumed; periodic Burn, Poison and Bleed bypass it. Generic Cleanse also removes Healing Reduced. The reference's large HP/damage numbers, speed system and party-wide card deletion have been adapted to this game's scale.

Victory opens Dawn at Last. Return to the starting screen or choose Keep exploring to receive the floor reward and continue into endless floors. Graveyards can be inspected only during an active battle.

### Preparedness playtest and notes 2

The latest notes /2 (https://docs.google.com/document/d/17LhbrulIVWbfTn7mcwgJ0ZM8OXo5ZEPA-1WGeAwMo2M/edit) are implemented alongside the first playable Contingency prototype.

Plans: end a turn with at least 2 unused energy to automatically spend 2 and save 1 Plan token. Save at most once per round and hold at most 2. Press P or the Plans button before ending a later turn to arm one contingency for its listed token cost. Draw first if still in the draw phase. Automatic saving can be disabled in this panel.

- Brace: select one deployed ally; prevent up to 2 incoming damage from its next attack hit this combat. Periodic status damage bypasses it. Unused protection expires after combat.

- Coordinated Response: select two nearest deployed allies on either side, including mixed types and gaps with no intervening ally; each gets +1 attack for this combat. The boost is temporary and does not add Strength stacks. If the formation is changed before combat, the contingency expires without its bonus.

One contingency may be armed each round. Tokens, armed plans and temporary boosts reset between encounters. Start with Brace and Coordinated Response; elite and boss victories offer three locked tactics to choose from. Unlock one for the rest of the run. Unlocks reset on a new run. The resource saving and temporary effects are recorded in the combat log.

Overclock: gain 2 capacity immediately; ordinary Response growth becomes 2 per round instead of 1. Other resource bonuses still stack. Disaster tension also grows one additional capacity per round. Hero and unit damage increases by 50%, rounded up, after armor but before barriers. This includes periodic status damage, but fixed HP payments such as Static Echo remain fixed. The old draw penalty is removed.

Evacuation Route: still costs 4 energy, now has 3 attack / 5 health. On play, optionally move another deployed ally to an empty lane and heal that ally by 2. The unit stays in its original slot; skipping movement does not undo its summon.

Inspection and log: click a deployed card on either board to inspect its current stats, effects and statuses while combat pauses. Press L, use the Log button, or choose Combat log in the menu for a chronological backlog of up to 300 encounter events. The log resets with the next encounter. Sealed labels are rebuilt on refresh and disappear when the seal expires.

Deck removal: shops can destroy an exact selected card copy for 30 supplies and remain open afterward. Rest nodes can retire one card for free instead of healing or training; this completes that node. Removal previews require confirmation, preserve other duplicates and keep at least 5 cards in the collection. These run edits do not add a card to a battle graveyard.

Starting screen: the battle menu offers Return to starting screen with confirmation and preserves the unfinished run. Defeat and victory screens also offer this action. It reloads the title, where an unfinished run can be continued or abandoned. Defeat and completed victory clear the save; endless exploration can begin a new floor. There is no direct restart shortcut.

### Hovering and graveyards

Hand selection follows the visible stacking order using each card's resting footprint. Only one card rises at a time. Lifting a card does not remove its resting hover region, preventing repeated pop-up/reset behavior. Its raised face stays clickable. While dragging, all other hover lifts are suppressed. Right-click cancels a drag; failed placement also restores the hand. Opening a modal clears hover.

During battle, open Deck [D] to Graveyards to inspect separate Response and Janitor graveyards. Destroyed units, sacrificed disasters and successfully cast spells appear with their reason and round, including separate copies of the same card. Failed/cancelled spells remain in hand. Entries are battle snapshots with maximum health displayed; battlefield status changes do not rewrite them. The viewer supports sorting and pauses combat. Graveyard access disappears outside battle, including results, shops, events and the map; the next encounter or new run resets its entries. Clearing the battlefield between rooms does not count as a death. Graveyard cards are not automatically reshuffled or playable again.

### Notes 3 contingencies targeting and encounters

Elite and boss wins unlock one new contingency before the usual card or floor reward. Six additional tactics join the two starters: Field Medicine heals an ally 3 and clears Bleed; Supply Line draws one at combat start; Flanking Route ignores guardian Taunt; Emergency Shelter protects your health pool against 3 attack damage; Precision Team gives an ally +2 attack for one combat and costs 2 Plans; Emergency Extraction saves an ally from one lethal attack by moving it into a chosen empty lane. All others cost 1 Plan. Extraction requires that lane to remain empty, and cannot prevent periodic status damage. Temporary effects expire after combat; unlocked tactics last the run.

Click board cards for allied spell and contingency targets. Coordinated Response uses two neighboring allies of any type; an empty lane between them is allowed, but another ally between them is not. Extraction uses an ally and then an empty lane. Movement effects use a direct drag; invalid drops, right-click, or Esc restore the ally's original position. Cancelling Emergency Exit keeps its energy and card. Cancelling a summoned unit's optional relocation keeps the summon.

The Janitor holds an actual shared hand of base cards, spells and drawn evolutions. Card backs appear above the board; the floating Janitor hand-count caption is removed. Evolutions must be drawn before being played; hand space is reserved for playable base cards. Seal and cost disruption select only cards held in hand. Opposing hand choices stay face down until Hazard Forecast reveals them. Neither side can seal undealt cards.

Six event variants populate the map: the locked room, radio station, rooftop training, science lab, infirmary, and lost and found. Radio trades 20 supplies for scouting and tutoring spells. Rooftop preparation gives a permanent starting Plan at the cost of 1 energy capacity. Science experiments trade 3 HP for stronger status cards. Full infirmary treatment heals 8 but adds a Paperwork deadweight spell; modest treatment heals 3 without that downside. Lost and found trades an exact removed card for 25 supplies while retaining at least five cards. Event previews stay fixed when reopened.

### Notes 4 and economy playtest

The title uses a full-screen layout inspired by the supplied reference, with temporary native school scenery until final artwork is supplied. Multiplayer is visible but disabled. Continue restores the map, collection, exact draw-pile order, supplies, health, units, statuses, Plans, boss state and pending offers. Abandon requires confirmation. Save writes use a temporary file and replace the previous checkpoint only after writing it. During combat or a drag, the last stable player-turn checkpoint is kept. Unfinished runs created by older versions cannot be recovered retroactively.

Recently added sorting tracks each acquired card copy independently, including shop and event acquisitions. Upgrading a card preserves its acquisition order. Sorting affects only display order. Live card faces refresh when relevant values change, so Strength, temporary Plans, costs, health and statuses stay current without rerendering unchanged faces every frame.

Preparedness begins at 3 energy and has a base ceiling of 7; resource buffs may raise that ceiling. Barrier stacks cap at 3 on each unit and the player. Plans retain their two-token limit and one contingency per round. Supply Cache, tutoring, scouting, sealing and cost disruption now cost at least 2 energy before upgrades, making them compete with deploying units. Cost disruption expires after the current and next round and cannot accumulate beyond +2. Formation damage bonuses still reward matching types, while Coordinated Response supports mixed formations.

Disaster evolutions pay sacrifices without an additional tension payment. Cinder Cloud applies 2 Burn to its opposing lane card when sacrificed; Glass Quake draws one from the finite Disaster base pile. These rewards do not trigger on ordinary destruction. Evolutions requiring three sacrifices gain 2 Barrier and draw one on entry. Four-sacrifice evolutions gain 3 Barrier, draw one and deal 1 fixed damage to each opposing deployed unit. They still lose the other blockers and attacks sacrificed to create them. The AI includes entry and sacrifice rewards when judging whether an evolution is worth its lost formation. Regular encounters retain their action and evolution restrictions.

This is a balance playtest, not a guarantee of equal win rates. Track how often each side runs out of playable cards, whether keeping a formation beats evolving, and whether a major evolution leaves a reasonable response turn. No existing card or core deck mechanic was removed.

### Notes 5 map clarity and three camera views

Outside battle, an opaque full-screen map replaces the idle board. Shops, events and the collection also hide battle geometry. M still toggles the map during a battle, while Esc closes the between-room menu back to the map. Graveyards are accessible only in active encounters. Shop, healing, event and removal choices show explicit gains and costs; healing labels account for missing health.

How to Play now has four scrollable categories: Start a run, Battle and Plans, Cards and effects, and Controls. The board and deployed cards share matching lane and collider proportions. Hand hover footprints match the visible card scale. The supplied classroom and dedicated rear table replace the earlier modular room; character positions are empty markers and illustration windows stay blank.

The three camera states are Room (S), normal Table, and Overhead (W). W and S move one step at a time, ignoring key repeats and clamping at either end. An interrupted transition continues smoothly from its current transform. Combat uses Overhead and restores your chosen view afterward; Continue retains all three view states and accepts older two-view checkpoints. The classroom integration checks camera paths inside the finished room and screens for visible void at 16:10, 16:9 and ultrawide sizes.

### October 15 notes 1 and 2 presentation and game feel

The existing bloom, anti-aliasing, clarity, sharpness, anisotropic filtering and lighting remain active with the current supplied classroom. Source textures and models have not been downsized as part of this update.

Each encounter begins with an interactive full-screen Heads/Tails call. The toss animates and shows the landed side before the first turn starts. Calls lock immediately to reject double clicks. Both an unresolved call and a toss already underway can be continued from a checkpoint; the saved outcome and chosen side are retained. The coin outcome is recorded in the combat log. Returning from an older stable battle checkpoint does not replay its opening toss.

Normal battle rewards display three native card faces centered on a darkened, frozen battlefield. Click a face or Take card to acquire that exact card once, or Skip card reward to continue. Background shortcuts, card interaction and camera raycasts are blocked while choosing. Offers remain fixed through saves. Preview cards render once, stay out of gameplay groups and collisions, and are freed with their modal.

Click a deployed card to inspect its current face, enlarged at its native aspect ratio. Current attack, health, modifiers and status stacks are available in the scrollable details below it. Click outside the card, use Return to battle or press Esc to dismiss. Combat pauses during inspection. Opening the deck and closing it restores the same inspection and backdrop.

Short menu/shop fades, button press/hover feedback and reward-card hover states complement the existing stable hand hover. Cards follow eased curves into the hand. Cast utility cards fly to the discard pile; defeated cards burn away with an ember dissolve. Slots, costs, graveyards and rewards update immediately, independently of cosmetic cleanup. Existing attack lunges, impact shakes, damage and status pop-ups remain. Turn/clash and victory banners clarify combat; node entry, map scrolling and floor changes have brief transitions. These effects use event-driven, short-lived tweens rather than new continuously running UI animation loops.

The board is now the reusable native 3D asset scenes/school_drill_board.tscn: a worn school slate in a dark wood frame with brass corner caps and faint lane registration marks. It fits the current table and existing slot colliders. It has no Threat Zone or Response Zone labels and leaves card illustration windows blank. Unlike the previous mat, it does not generate a large image pixel by pixel when an encounter scene loads.

### October 16 smaller project and runtime cleanup

Unused environments, duplicate model/textures, obsolete scripts and generated previews are removed from the active project. The current classroom and its 33 original textures retain their geometry and image quality; the model references the existing texture files to avoid storing each image twice. Material instances are shared, fallback card-face checks are bounded, and identical enemy backs are not unnecessarily rebuilt. Card effects, animated dragging, lighting and anti-aliasing remain enabled.

Run python tools/asset_audit.py to check dependencies and original texture/geometry integrity. The Windows export preset excludes development-only files and explicitly includes card JSON data. Test captures stay ignored by both Git and Godot.

### Current balance direction

Preparedness should excel at steady deployment, rescue, protection and planned answers, while having limited sudden damage and an opportunity cost for utility cards. Disasters should excel at stronger individual threats, sacrifice combos and sudden pressure, while losing board coverage and needing time to rebuild. Equal win rates have not been established by the regression tests.

### Round flow and starting resources

Steve begins a run with 20 hero HP, 35 supplies and a 12-card starter deck. Response starts an encounter with three hand cards and an eight-card hand limit. The Janitor draws three base cards and one evolution at opening, subject to its six-card shared hand limit. Held evolutions are limited to two, with space reserved for base draws. Further evolution draws occur on even rounds when there is room.

At round start, resources refill and upkeep resolves. The first side plays before the second, then attacks first during the single combat phase. Plans resolve at combat start and expire after combat. After a surviving round, the Response cap grows, first-player order switches, and the next round begins. The fixed final boss is an exception: Steve plays and attacks before the announced special pattern.

Battle victories grant 20 supplies, elite victories 35, and ordinary boss victories 60. Rest heals 7 instead of upgrading or removing a card. Advancing a floor heals 5 up to the 20 HP maximum. The locked-room event trades 3 HP for one card and 30 supplies, or gives 10 supplies safely.

The economy pass keeps all existing cards and core mechanics. A one- or two-sacrifice evolution is the normal development path; three-sacrifice cards are major threats and four-sacrifice cards are exceptional commitments. More graveyard recovery and sacrifice-value cards were discussed but are not yet implemented beyond the specific Cinder Cloud and Glass Quake effects.

Type identity remains a design direction: Evac for rescue and movement, Douse for pressure reduction and cleansing, Clearance for removing threats and breaking defenses, and Brace for holding lanes and retaliation. This is not yet an enforced restriction on the existing card pool. Reducing how widely Response gains strong Burn, Poison and Piercing is a future balance decision, not a completed removal.

## Current status and remaining work

### Completed interface and classroom work

- Graveyards are available during battle. HP, supplies and card-removal costs are explicit; shop removal costs supplies while rest removal remains free.

- The map fills the screen outside combat. How to Play has four categories, and three camera views use smooth transitions within the room.

- Each encounter waits for a Heads/Tails call. Rewards show three centered cards, and deployed-card inspection preserves the native card proportions.

- The active classroom uses the supplied rear play area and dedicated table. The framed board has eight working lanes and no Threat Zone or Response Zone labels.

- The optimized model references 33 byte-identical PNG textures instead of storing a second embedded copy. Geometry, UVs, materials and texture dimensions were preserved.

### Remaining artwork and balance work

- Final title artwork and card illustrations have not been supplied. Card illustration windows remain blank, and the title uses native school scenery.

- Player and Janitor character models have not been added to the current classroom. Their positions are reserved by empty markers.

- Balance still needs repeated playtests across both economies, encounter tiers and buff combinations. Regression tests check rules and state changes, not equal win rates.

### Other planned systems

The three themed club leaders have deck definitions but remain disabled. Multiplayer requires a separate builder and match implementation. Additional draw, recovery, protection and sacrifice interactions need real gameplay testing before expansion. No exact PvP win-rate target has been verified.

## Card catalog

These are base card definitions in the current project, before upgrades, character health bonuses, global buffs or live status changes. Steve adds one unit health on deployment. The starter deck contains two copies of each of its six named cards. Cost zero on a base Disaster means its deployment normally uses one tension; evolution costs are sacrifices. Encounter scaling can change Disaster stats. Event variants and scripted boss entities are listed separately.

### Preparedness

| Card and type | Cost | ATK / HP | Abilities |
| --- | --- | --- | --- |
| Quick Dash<br>Evac | 1 energy | 2 / 1 | No special ability |
| Fire Drill<br>Evac | 2 energy | 2 / 3 | No special ability |
| Evacuation Route<br>Evac | 4 energy | 3 / 5 | Relocate another ally; Relocated ally heals 2 |
| Fire Hose<br>Douse | 2 energy | 3 / 2 | No special ability |
| Debris Clearance<br>Clearance | 1 energy | 2 / 2 | No special ability |
| Shelter Brace<br>Brace | 3 energy | 1 / 5 | armored |
| Needle Team<br>Evac | 3 energy | 2 / 3 | piercing |
| Heavy Loader<br>Clearance | 3 energy | 5 / 5 | sluggish |
| Steam Team<br>Douse | 3 energy | 2 / 4 | On hit burn 3 |
| Shard Barrier<br>Brace | 2 energy | 1 / 4 | On hit bleed 2 |
| Hazmat Team<br>Clearance | 3 energy | 2 / 3 | On hit poison 2 |
| Supply Runner<br>Evac | 2 energy | 1 / 2 | On play draw 1 |
| Drill Captain<br>Brace | 3 energy | 1 / 4 | Starting Strength 2 |
| Search and Rescue<br>Evac | 2 energy | 0 / 1 | Utility; Search draw pile |
| Safety Lock<br>Brace | 2 energy | 0 / 1 | Utility; Seal held card |
| Hazard Forecast<br>Evac | 2 energy | 0 / 1 | Utility; Reveal enemy hand |
| Containment Order<br>Clearance | 2 energy | 0 / 1 | Utility; Temporarily raise held-card cost |
| Rally the Team<br>Brace | 1 energy | 0 / 1 | Utility; Give ally 2 Strength |
| Decontaminate<br>Douse | 1 energy | 0 / 1 | Utility; Heal ally 3 and cleanse |
| Lane Marshal<br>Evac | 2 energy | 1 / 3 | Relocate another ally |
| Rescue Crane<br>Clearance | 4 energy | 3 / 5 | sluggish; Relocate another ally |
| Field Medic<br>Douse | 3 energy | 1 / 3 | Heal other allies 2 |
| Drill Leader<br>Brace | 4 energy | 1 / 4 | Other allies gain 1 Strength |
| Recovery Team<br>Douse | 3 energy | 2 / 4 | Heal after attack 2 |
| Cutting Crew<br>Clearance | 4 energy | 3 / 3 | piercing; On hit bleed 1 |
| Heat Seeker<br>Douse | 3 energy | 2 / 4 | target burn stacks >= 3: +3 attack |
| Toxin Hunter<br>Clearance | 4 energy | 2 / 4 | target any stacks >= 3: attack twice |
| Momentum Team<br>Brace | 3 energy | 1 / 4 | self strength stacks >= 2: attack twice |
| Last Responder<br>Evac | 2 energy | 2 / 3 | self any stacks >= 3: +2 attack |
| First Aid Herb<br>Douse | 0 energy | 0 / 1 | Utility; Clear Bleed and heal allies 1 |
| Restoration Tablet<br>Douse | 1 energy | 0 / 1 | Utility; Clear Healing Reduced and heal allies 2 |
| Barrier Generator<br>Brace | 2 energy | 0 / 1 | Utility; Formation and hero gain 2 Barrier |
| Alarm Sweep<br>Clearance | 2 energy | 0 / 1 | Utility; Damage all enemy units 2 |
| Containment Lance<br>Clearance | 3 energy | 2 / 4 | Ignore guardian Taunt |
| Silent Runner<br>Evac | 3 energy | 2 / 3 | On play draw 1; Ignore guardian Taunt |
| Supply Cache<br>Clearance | 2 energy | 0 / 1 | Utility; On play draw 2 |
| Emergency Exit<br>Evac | 1 energy | 0 / 1 | Utility; Drag ally to empty lane |

### Disasters

| Card and type | Cost | ATK / HP | Abilities |
| --- | --- | --- | --- |
| Ember<br>Fire | 1 tension | 2 / 2 | No special ability |
| Tremor<br>Earthquake | 1 tension | 2 / 3 | No special ability |
| Rising Tide<br>Flood | 1 tension | 2 / 2 | No special ability |
| Gust<br>Typhoon | 1 tension | 2 / 2 | No special ability |
| Wildfire<br>Fire | 2 sac. | 4 / 3 | fierce |
| Fissure<br>Earthquake | 2 sac. | 4 / 4 | rampaging |
| Flash Flood<br>Flood | 2 sac. | 3 / 4 | regenerating |
| Gale Force<br>Typhoon | 2 sac. | 4 / 3 | armored |
| Inferno<br>Fire | 3 sac. | 7 / 5 | fierce; Major evolution entry protection and draw |
| Tsunami<br>Flood | 3 sac. | 6 / 6 | regenerating; Major evolution entry protection and draw |
| Cinder Cloud<br>Fire | 1 tension | 1 / 3 | On hit burn 2; On sacrifice: opposing lane gains 2 Burn |
| Glass Quake<br>Earthquake | 1 tension | 1 / 3 | On hit bleed 2; On sacrifice: draw 1 |
| Toxic Runoff<br>Flood | 1 tension | 1 / 3 | On hit poison 2 |
| Needle Gale<br>Typhoon | 1 sac. | 3 / 3 | piercing |
| Sleeping Fault<br>Earthquake | 3 sac. | 6 / 6 | sluggish; Major evolution entry protection and draw |
| Pressure Front<br>Typhoon | 1 tension | 1 / 3 | On play draw 1; Starting Strength 1 |
| Blocked Exit<br>Earthquake | 1 tension | 0 / 1 | Utility; Seal held card |
| Red Tape<br>Flood | 1 tension | 0 / 1 | Utility; Temporarily raise held-card cost |
| Crosswind<br>Typhoon | 1 tension | 1 / 3 | Relocate another ally |
| Warm Front<br>Fire | 1 tension | 1 / 3 | Heal other allies 2 |
| Aftershock Choir<br>Earthquake | 2 sac. | 3 / 4 | Other allies gain 1 Strength |
| Drain Vortex<br>Flood | 3 sac. | 4 / 7 | Heal after attack 2; Major evolution entry protection and draw |
| Black Squall<br>Typhoon | 3 sac. | 5 / 5 | piercing; On hit poison 2; Major evolution entry protection and draw |
| Worldbreaker<br>Earthquake | 4 sac. | 8 / 9 | sluggish; On hit bleed 3; Major evolution entry protection and draw |
| Ash Predator<br>Fire | 2 sac. | 3 / 4 | target burn stacks >= 3: attack twice |
| Venom Surge<br>Flood | 1 sac. | 2 / 4 | target poison stacks >= 2: +3 attack |
| Pressure Break<br>Typhoon | 2 sac. | 2 / 4 | Starting Strength 2; self strength stacks >= 3: attack twice |
| Fracture Hunter<br>Earthquake | 1 tension | 1 / 3 | target any stacks >= 3: +2 attack |

### Encounter and event cards

| Card | Source | Base rule |
| --- | --- | --- |
| Hallway Guardian | Elite signature | 2 sacrifices; ATK 4 + floor; HP 5; Armored; favored encounter element. |
| Midnight Cataclysm | Ordinary boss signature | 3 sacrifices; ATK 6 + floor; HP 8; Fierce; favored encounter element. |
| Experimental Steam Team | Science lab | Steam Team variant with Burn increased by 2; current on-hit Burn 5. Costs 3 hero HP to obtain. |
| Experimental Hazmat Team | Science lab | Hazmat Team variant with Poison increased by 1; current on-hit Poison 3. Costs 3 hero HP to obtain. |
| Paperwork | Infirmary tradeoff | 1-energy Clearance utility; ATK 0 / HP 1; paying its cost only discards it. |
| Static Echo | Final boss curse | Temporary hand card. Cast to pay 1 HP and draw 1, or pay 1 HP and discard at round end. Not a permanent reward card. |
| Night Watch and Hall Monitor | Final boss | Scripted guard units; Shackle, guardian and pillars follow the three-phase boss rules rather than the ordinary deck economy. |

## Buff and contingency catalogs

### Battle adaptations

| Buff | Effect and tradeoff |
| --- | --- |
| Stronger Together | All your units gain +1 attack for this battle. |
| Reinforced Formation | All your units gain +1 maximum health and heal 1. Future units also benefit. |
| Resource Surge | Response: extra energy cap and growth. Disaster: extra tension and one extra action (max 5). |
| Fuel the Flames | Your cards apply 2 extra Burn stacks whenever they inflict Burn. |
| Toxic Pressure | Your cards apply 1 extra Poison stack whenever they inflict Poison. |
| Deep Cuts | Your cards apply 1 extra Bleed stack whenever they inflict Bleed. |
| Rapid Logistics | Draw 1 extra card in each normal draw phase, up to the hand limit. |
| Glass Cannon | +2 attack to all units, but -1 maximum health. This battle only. |
| Overclock | Gain 2 capacity now and +1 extra capacity growth each round (2 total normally), but take 50% more damage (rounded up). |
| Blood Pact | +3 attack, but all units gain 2 Bleed when you choose this and when they enter. |
| Patient Formation | All units regenerate 2 each round, but become Sluggish. |
| Toxic Ward | Apply 2 extra Poison stacks, but all your units lose 1 attack. |
| Close Ranks | Matching adjacent units deal 2 extra damage. Isolated deployed units lose 1 attack. |
| Bristling Defense | Surviving blockers retaliate for 1 fixed damage, but all units lose 1 maximum health. |
| Piercing Formation | All units gain Piercing, but lose 1 attack. |

### Permanent floor rewards

| Buff | Effect and tradeoff |
| --- | --- |
| Signal Beacon | PERMANENT: draw 1 extra card in normal draw phases. |
| School Bulwark | PERMANENT: units gain 2 maximum health, but lose 1 attack. |
| Bold Strategy | PERMANENT: units gain 2 attack, but lose 1 maximum health. |
| Field School | PERMANENT: +1 resources and +1 normal draw, but units lose 1 maximum health. |
| Hazard Manual | PERMANENT: apply +2 Burn, +1 Poison, +1 Bleed, but lose 1 resource capacity. |
| Buddy System | PERMANENT: matching neighbors deal 2 extra damage; isolated deployed units lose 1 attack. |
| Infirmary Network | PERMANENT: heal your side's health by 1 each round, but units lose 1 attack. |
| Jagged Barricades | PERMANENT: surviving blockers retaliate for 1 fixed damage, but units lose 1 maximum health. |

### Contingencies

| Tactic | Plans | Access | Effect |
| --- | --- | --- | --- |
| Brace | 1 | Starter | One ally blocks up to 2 damage from its next attack hit this combat. |
| Coordinated Response | 1 | Starter | Two neighboring allies gain +1 attack this combat. |
| Field Medicine | 1 | Elite or boss unlock | At combat start, heal one ally 3 and remove its Bleed. |
| Supply Line | 1 | Elite or boss unlock | Draw 1 card at combat start to prepare your next turn. |
| Flanking Route | 1 | Elite or boss unlock | One ally ignores guardian Taunt for this combat. |
| Emergency Shelter | 1 | Elite or boss unlock | Your health pool gains 3 temporary attack protection this combat. |
| Precision Team | 2 | Elite or boss unlock | One ally gains +2 attack for this combat. |
| Emergency Extraction | 1 | Elite or boss unlock | Move an ally to a chosen empty lane instead of taking one lethal attack. |

Coordinated Response selects the nearest allies on either side, including different types and empty-lane gaps. An intervening ally prevents that pair. Temporary Plan effects expire after combat. Tactic unlocks last the run; tokens and armed effects reset between battles.

### Character and event buffs

| Buff | Availability | Implemented effect |
| --- | --- | --- |
| Student Training | Steve | Units gain 1 health. |
| Route Formation | Disabled Evacuation leader | Matching-neighbor synergy bonus +1. |
| Chemical Expertise | Disabled Science leader | Burn bonus counter +1 and Poison +1; unit health -1. Burn scaling converts that counter to +2 applied stacks. |
| Barricade Doctrine | Disabled Safety leader | Surviving blockers retaliate for 1. |
| Rooftop Preparation | Rooftop event | Start each battle with 1 Plan, but lose 1 energy capacity. |

## Verification and source record

The October 16 optimization checks passed ten suites: run, mechanics, hover_graveyard, notes4, notes5, final_boss, coin_rewards, optimization, visual_quality and classroom_integration. They cover combat rules, saves, targeting, hover, graveyards, camera paths, coin calls, rewards, card inspection, classroom materials and bounded display updates. Graphical checks used Forward+. The exported game-data pack also passed the mechanics suite. Earlier expansion, improvements, variety, plans_notes and notes3 suites passed during their respective updates; they were not all rerun for the cleanup.

The asset audit checks 63 runtime files, verifies the geometry checksum and all 33 original texture hashes and dimensions, and fails on missing or unreferenced runtime resources. After the whole-folder cleanup, both project copies passed the audit and the optimization suite passed again. These results do not establish balance, multiplayer reliability or final artwork quality.

- tests/run_smoke.gd

- tests/mechanics_smoke.gd

- tests/hover_graveyard_smoke.gd

- tests/map_sorting_caps_and_saves_smoke.gd

- tests/menu_navigation_and_camera_smoke.gd

- tests/final_boss_smoke.gd

- tests/coin_rewards_smoke.gd

- tests/card_refresh_performance_smoke.gd

- tests/visual_quality_smoke.gd

- tests/classroom_integration_smoke.gd

### Project and source references

- Original design and subsequent requests in the development conversation, including the original card types, board layout, roguelike map, upgrade limits, shop behavior, AI and balance discussions.

- Original design link: https://docs.google.com/document/d/1-KlECZGbR6mEqf_iEX5SWBKgSJCcioDR/mobilebasic

- Development notes: https://docs.google.com/document/d/17LhbrulIVWbfTn7mcwgJ0ZM8OXo5ZEPA-1WGeAwMo2M/edit

- Supplied Word notes: notes for Drr card game (1).docx, including /5 and the classroom references. Completed items are recorded above; final artwork and multiplayer remain unfinished.

- Current project reference: RUN_GUIDE.md; card data in starter_deck.json, response_expansion.json, disaster_deck.json and disaster_expansion.json; runtime rules in battle_rules.gd, contingency_rules.gd, game_3d_manager.gd, run_director.gd, final_boss.gd and run_save.gd.

- GitHub repository: https://github.com/HerezHisui/CARD-GAME-using-GODOT

- Multiplayer Design and Deck Builder proposal: https://docs.google.com/document/d/1lyxR52jlt4Z28vOycWLNDVeqEhnon1TOcE0jDcJ0EQo/edit

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
