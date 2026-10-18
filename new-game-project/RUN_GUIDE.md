# Midnight DRRills

Open `project.godot` in Godot 4.7 and run the main scene. The game begins on a title screen with Singleplayer, a disabled Multiplayer placeholder, and Quit. A saved run instead offers Continue and Abandon. Start opens character selection; preview a starter deck before beginning. Future start-screen artwork can be placed at `assets/title_screen.png`; the title screen uses it automatically after Godot imports it. All card art windows remain blank.

## The run

Choose an illuminated starting room, then follow connected rooms toward the Janitor boss. Each floor has eleven stages and three branching lanes, merging at the boss. Mandatory combat rows ensure every route includes at least four normal/elite battles before the boss. Scroll upward through the map; it follows your current progress when reopened. Layouts vary by run; every room has a route forward. Normal encounters favor one disaster element, elites have tougher cards and a Hallway Guardian evolution, and bosses have more health and a Midnight Cataclysm evolution. Later floors scale difficulty.

Player health, supplies, collected cards, and upgrades persist between rooms **across sessions through automatic checkpoints**. Each battle begins with a fresh shuffled copy of the collection. Health damage and sacrifices affect those battle copies only. Unfinished runs save locally at stable player turns and room decisions. Multiplayer is a disabled placeholder.

Battle wins grant supplies and a choice of one of three cards. Workshops improve one card; infirmaries offer healing or an upgrade. Supply rooms allow multiple purchases from fixed stock and repeatable healing until you leave. Events have explicit risk/reward choices. Defeat ends the run. Each boss win offers a permanent floor buff before advancing to a harder floor.

## Controls

- Drag a hand card onto an empty lower Response slot. Right-click cancels a drag.
- Draw once during the draw phase using the lower-right draw button.
- G or the compact Graveyard button opens the Response battle graveyard. G, Esc, Close, or an outside click returns to battle.
- At encounter start, call **Heads** or **Tails** on the full-screen coin event. A matching toss gives you the first turn; otherwise the Janitor plays first. The starting side alternates each round afterward. Space or **End turn** submits your turn.
- W steps from Room → Table → Overhead; S steps back. Battles start in the central Table view. Transitions ease position, rotation, distance and field of view. Room view hides your hand to show the opponent and classroom; return to Table to play. Camera changes are blocked during combat, dragging and board targeting.
- D opens the collection, unordered remaining draw pile, hand, and deployed Response cards. Sort by Name, Type, Cost, Attack, Health, Modifier, or Recently added, in either direction. Recent sorting defaults to newest first. Sorting never changes draw order or your collection.
- M opens and closes the school map during battles. Between encounters, the full-screen map stays open and the board is hidden. Next rooms unlock after completing the encounter and reward choice. Deck and menu overlays return to this map when closed.
- Esc opens the menu. Deck, map, and menu overlays pause an active encounter. Close or Resume continues it.
- Return to starting screen saves the unfinished run. Continue resumes it; Abandon clears it after confirmation and enables a fresh Singleplayer game.
- The battle menu includes **Quit game**, which closes the game. Stable decisions and player turns are saved to disk; closing during an animation resumes the last stable checkpoint.

## Workshops and shops

Workshops have the same sorting controls as the deck browser. **Preview upgrade** shows the current card beside its upgraded version; only **Confirm upgrade** changes the collection. **Every card copy can upgrade at most twice**, shown as 0/2, 1/2, or 2/2. Evac gains attack and on-play draw, then health and a cheaper energy cost. Douse gains attack and Burn, then health and healing after each strike. Clearance gains attack and Poison, then health and +2 attack against targets with three harmful status stacks. Brace gains health and stronger armor, then health and retaliation. Spells first become cheaper; later upgrades strengthen draw, seal, tax, rally, or cleanse. Movement, tutor, and scouting upgrades refund energy instead. Zero-cost spells can improve their abilities. Duplicate cards retain their original identity when sorted, so only the selected copy changes.

Shops offer four distinct cards, each with one copy in stock. Buying one marks it sold and keeps the shop open; remaining stock does not reroll. Healing can be purchased repeatedly until health is full or supplies run out. Labels show actual healing and the supplies spent, for example **First aid · +1 HP · -15 supplies** when only one health is missing. Full-health healing is disabled. Removal shows **Destroy 1 card · -30 supplies**; infirmary removal is explicitly free. The room is completed only when you press **Leave shop**. Infirmaries also offer an exit if you prefer to skip their service.

## Cards

The twelve-card starter deck now contains three Quick Dash, three Fire Drill, two Fire Hose, two Debris Clearance, one Evacuation Route and one Shelter Brace. Existing saves retain their collections. Card illustration windows are deliberately empty. Assign future illustrations in the `ART` dictionary in `scripts/card_3d.gd`. Backs have four corner element marks and a central double ring.

Evac counters Earthquake, Douse counters Fire, Clearance counters Flood, and Brace counters Typhoon at 2× damage. Weak matchups deal half damage. Two adjacent deployed cards of the same element receive +1 attack (not cumulative across both neighbors). Armored reduces incoming attack damage by one (minimum one), Fragile adds one, Regenerating heals up to maximum health, Fierce adds two to hero hits, and Rampaging adds one when attacking a card as the second side of the round.

**Normal attacks never deal overkill/overflow damage to the opposing hero.** Even a one-health blocker stops the entire hero hit. **Piercing** damages the blocker normally and also deals the attacker's effective attack plus adjacency bonus to the opposing health pool. Type effectiveness applies to the blocker only. Fierce adds two to this hero hit. An open lane hits the hero once, including for Piercing cards.

**Sluggish** attacks the first round it can attack, then rests the next round, repeating. Its timing is per card, rather than based on odd/even global rounds. **Strength** adds to attack before type effectiveness and lasts while the card exists. Temporary card statuses and costs do not alter the permanent collection.

**Burn** deals its stack count in damage at the start of the round, then halves its stacks, rounding down. **Poison** deals its stack count at the start of the round, then loses one stack. **Bleed** damages its card by the stack count after that card attacks, then loses one stack. Skipped attacks do not trigger Bleed. These fixed status hits bypass Armored and Fragile. Regeneration happens after status damage; dead cards cannot regenerate. On-hit status effects apply only to a surviving blocker.

Reward and shop pools include utility cards: **Supply Cache** draws two cards up to the hand limit; **Emergency Exit** lets you drag a friendly deployed card into an empty Response slot. Both spend energy and disappear after use. Emergency Exit returns to hand without spending energy if no deployed ally exists. Hover over deck previews for rules.

The expansion adds thirteen Response cards and eight Disaster cards. Response units include Needle Team (Piercing), Heavy Loader (Sluggish), Steam Team (Burn), Shard Barrier (Bleed), Hazmat Team (Poison), Supply Runner (draw one on play), and Drill Captain (two Strength). Steve retains the original twelve-card deck; themed club decks are reserved for future characters. New Response cards also appear in rewards and shops. Disaster encounters include matching status-based units, Piercing and Sluggish evolutions, and disruption spells.

Targeted Response spells are cast by dragging them onto an empty Response slot, then choosing a target:

- **Search and Rescue:** choose an unlocked card from your draw pile and put it into your hand. Displays an alphabetic list, keeping pile order hidden.
- **Safety Lock:** choose a card currently in the opposing hand, including held evolutions. It cannot be played for this round and the next. Already deployed units are unaffected.
- **Hazard Forecast:** reveal the Janitor's hand for this encounter. Reopen it through D afterward.
- **Containment Order:** raise one opposing hand card's cost, including held evolutions, by one for this round and the next. Repeated taxes cap at +2 cost. Disaster evolutions require one more sacrifice; base disasters and utility spells require one more tension. Response costs remain energy-based.
- **Rally the Team:** give a deployed ally two Strength.
- **Decontaminate:** heal a deployed ally by three and remove Burn, Poison, and Bleed.

Rally and Cleanse target allies by clicking them on the board. Emergency Exit uses direct board dragging. Hand and draw-pile selectors pause play; board targeting blocks turn submission until completed or cancelled. Cancel or Esc keeps the spell and energy. No-target casts return to hand. Disaster disruption spells can seal only Response hand cards or increase a Response hand card's energy cost. Seals expire automatically when their indicated round begins.

## Global adaptations

At the start of rounds **5, 10, 15, ...** of each encounter, choose one of three randomly offered **battle-only adaptations** for your side. The Janitor does not receive an automatic adaptation from this pool. The battle pauses until you choose. Deck viewing preserves the exact offers. Adaptations expire when the encounter ends.

There are fifteen battle adaptations. Strong options have explicit tradeoffs: Glass Cannon adds two attack but removes one maximum health; Overclock grants two capacity immediately and doubles ordinary capacity growth to two per round, but increases incoming damage by 50% (rounded up); Blood Pact adds two Strength but destroys each deployed unit that did not kill a card during combat at combat end; hero hits and resting do not count, and hand cards are exempt; Patient Formation regenerates two health but makes units Sluggish; Toxic Ward strengthens Poison while reducing attack; Close Ranks rewards matching neighbors but penalizes isolation; Piercing Formation grants Piercing while reducing attack; Bristling Defense retaliates for one fixed damage while reducing health. Smaller stat, status, and draw buffs remain available without drawbacks.

After the **first two floor bosses**, choose one of three **permanent run rewards** from an eight-option pool. The Janitor does not receive an automatic reward from this pool. These stack across later battles and floors; a new run clears them. Examples include Signal Beacon (extra draws), School Bulwark (health for reduced attack), Buddy System (adjacency bonuses with an isolation penalty), Field School (resources and draws for less health), Hazard Manual (stronger statuses for reduced resources), and Infirmary Network (hero healing for reduced unit attack).

Battle adaptations and permanent rewards combine during a fight. Health stays at least one; attack stays at least zero; resource capacity stays at least one. Negative draw bonuses can reduce normal draws to zero, but spell and unit-triggered draws still work. Response resource bonuses increase starting capacity, its upper limit, and positive cap growth. Disaster bonuses alter tension and the action limit, between one and five actions. Menu summaries distinguish **Battle** buffs from **Run** buffs for both sides.

## New units and smarter encounters

Six more Response units and six more disasters join the pools. Lane Marshal and Rescue Crane optionally move another deployed ally after being played: drag the ally directly onto an empty lane. The played card stays where it was summoned. Skipping movement keeps the summon and its energy payment. Crosswind lets the Janitor relocate an ally if a better lane is available. Field Medic and Warm Front heal other allies by two; Drill Leader and Aftershock Choir grant other allies one Strength. Recovery Team and Drain Vortex heal after attacking. Cutting Crew, Black Squall, and Worldbreaker add stronger Piercing/status combinations.

Major original evolutions now need **two sacrifices**; Inferno, Tsunami, Sleeping Fault, Drain Vortex, Black Squall, and the boss's Midnight Cataclysm need **three**. Worldbreaker needs **four**. Needle Gale remains a smaller one-sacrifice evolution. Elite Guardian needs two. Sealing and cost disruption still apply to evolutions.

Elite and boss AI compares cards and lanes using effectiveness, survival before counterattack, immediate hero lethals, defensive coverage, and synergies. It evaluates sacrifice combinations and declines evolutions that discard more board value than they gain or expose lethal lanes. Disruption targets and buff choices are ranked rather than random. All encounters use board-aware sacrifice decisions. Regular enemies act at most twice per turn before buffs (four-action buff cap), use less precise placement, and only consider evolutions from round three when their board is full. They do not gain the free round 4–6 spawn modifiers. Elite/boss tactical placement and three-action base/five-action buff cap remain unchanged. Evolution planning compares the entire formation before and after sacrificing, including lost blockers and matching-neighbor bonuses. It penalizes losing a numerical advantage and compares filling an empty lane against evolving. A valuable field advantage can be kept without sacrificing; a winning Piercing evolution can still be chosen. AI uses the public board and its own available cards for battle planning; it does not inspect draw-pile order.

Empty draw piles do not immediately end a match while cards remain in hand or on board. A side with no usable cards left loses. Preparedness begins at three and its cap grows each round; Disaster evolutions retain the sacrifice mechanic and separate evolution deck.

## Verification

Run Godot with `--headless --path . --script` and each of `res://tests/run_smoke.gd`, `res://tests/mechanics_smoke.gd`, `res://tests/expansion_smoke.gd`, `res://tests/improvements_smoke.gd`, `res://tests/variety_smoke.gd`, `res://tests/hover_graveyard_smoke.gd`, `res://tests/final_boss_smoke.gd`, `res://tests/plans_notes_smoke.gd`, and `res://tests/notes3_smoke.gd` for integration checks. Graphical runs also capture previews in `tests/artifacts`. Checks cover connectivity, combat, statuses, cancellation, restart, sorting without reordering, duplicate-specific upgrades, before/after previews, shop stock and multiple purchases, summon movement, buff expiry and persistence, stronger sacrifices, tactical decisions, and the actual menu Quit button. Balance still needs playtesting with final artwork and content.


## Starter characters

Steve (Student) is available with the original 12-card deck and +1 unit health. His perk lasts the run and stacks with floor rewards. Three themed club leaders are disabled and marked Available soon; their deck definitions remain ready for future development. Older character selections safely reset to Steve.

- **Steve, Student:** original mixed Response deck; +1 unit health.
- **Evacuation Club Leader (Available soon):** Evac formations, movement, draw and tutoring.
- **Science Club Leader (Available soon):** Douse/Clearance status combinations.
- **Safety Club Leader (Available soon):** armored Brace formations, Strength and healing.

## Encounter and shop balance

First-floor normal/elite/boss health is **18 / 24 / 28**. Normal health increases by two each additional floor; elite/boss health increases by three. Base-card reserves are capped at **18 / 21 / 22**; evolution reserves at **8 / 14 / 15**, including elite/boss signature cards. Regular encounters only use evolutions requiring one or two sacrifices. Encounters still favor a disaster element and retain varied cards.

Shop cards cost **20, 30, 40, or 50 supplies** based on cost, stats, modifiers and abilities. Stronger cards cost more; Sluggish reduces the price score. Prices and affordability appear on each card. Stock stays fixed, sold cards cannot be bought again, and first aid remains repeatable at 15 supplies.

## Conditional cards

Four new cards join each side. Conditional effects count **stacks**, not the number of different statuses. “Harmful status” means total Burn + Poison + Bleed; Strength is counted only when explicitly named. Effects require at least the stated threshold.

- **Heat Seeker:** +3 attack against a target with 3+ Burn.
- **Toxin Hunter:** attacks twice against a target with 3+ total harmful stacks.
- **Momentum Team:** attacks twice with 2+ own Strength.
- **Last Responder:** +2 attack while carrying 3+ harmful stacks.
- **Ash Predator:** attacks twice against a target with 3+ Burn.
- **Venom Surge:** +3 attack against a target with 2+ Poison.
- **Pressure Break:** attacks twice with 3+ own Strength.
- **Fracture Hunter:** +2 attack against a target with 3+ harmful stacks.

Bonus attack is applied before type effectiveness. Target conditions require a blocker. Double-strike eligibility is checked at the start of the attack; each strike applies hit effects, healing, retaliation and Bleed independently. If the first strike removes a blocker, the second can hit opposing health through the now-open lane. A card killed by Bleed or retaliation cannot make its second strike. Sluggish still limits the rounds on which it attacks.


## School setting and final boss

The classroom uses the supplied rear play-area model with its original PBR materials, windows, lockers, desks and chairs. A dedicated table occupies the marked area. The playable room has 59 mesh instances, including that table, and retains 12 chairs outside the cleared strip. The eight card lanes sit on a framed slate board. Camera paths stay inside the finished room, with a dark exterior behind the windows. Desktop Forward+ rendering uses contact shadows, indirect lighting, light haze, 4x MSAA and temporal anti-aliasing at full rendering resolution. Bloom and restrained clarity grading affect the world beneath the HUD. The optimization preserves all geometry and 33 original textures without resizing. Player and Janitor positions are empty markers; card illustration windows remain blank.

The **Midnight Warden** is the final encounter on **floor three**, with 34 HP. Floors one and two provide preparation and still award permanent floor buffs. Steve plays and attacks before the final boss's announced special pattern resolves. The boss uses a fixed pattern instead of random enemy decks.

- **Phase 1:** odd rounds use Blade Rush (1 damage and 1 Bleed in Response lanes 1 and 3), then Punishment in lane 2. Even rounds summon a Shackle and use Punishment. Punishment deals 3, or 4 while a Shackle is present, and applies Healing Reduced for two rounds. An empty targeted lane takes at most 2 hero damage.
- **Phase 2:** reaching half health clamps damage at 17 HP and shields the boss. Shield Pulse (1 to deployed units) and two circuit pillars appear on the following round, providing a warning turn. Destroy both pillars to remove the shield. A guardian redirects ordinary attacks against pillars; Ignore Taunt and area damage bypass it. Each pillar destroyed discards at most one hand card. While pillars stand, one temporary Static Echo enters the hand each round: casting pays 1 HP and draws 1; leaving it uncast pays 1 HP and discards it at round end. A full hand pays the same penalty without adding a card. Curse payment bypasses Barrier.
- **Phase 3:** temporarily seal one hand card (skip sealing if the hand is empty) for two rounds, apply 1 Bleed to all deployed allies, and strike lanes 1 and 3 for 2. A newly entered phase gives a response turn before its special attack.

New preparation cards: **First Aid Herb** removes Bleed and heals 1 across deployed allies; **Restoration Tablet** restores healing and heals 2; **Barrier Generator** grants 2 attack-damage protection to deployed allies and the player health pool; **Alarm Sweep** deals 2 fixed damage to all enemy units. **Containment Lance** and **Silent Runner** ignore guardian Taunt. Later shops reliably stock Barrier Generator and Alarm Sweep. These abilities support the two-upgrade system.

Healing Reduced halves healing (minimum 1) until it expires or is removed. Barrier absorbs attack damage and is consumed; periodic Burn, Poison and Bleed bypass it. Generic Cleanse also removes Healing Reduced. The reference's large HP/damage numbers, speed system and party-wide card deletion have been adapted to this game's scale.

Victory opens **Dawn at Last**. Return to the starting screen or choose **Keep exploring** to receive the floor reward and continue into endless floors. Graveyards can be inspected only during an active battle.

`res://tests/final_boss_smoke.gd` adds checks for locked clubs, the 3D classroom, preparation cards, boss phases, shields, taunt, barriers, healing, curses, recoil, sealing, victory and the actual final encounter startup.

## Preparedness playtest and notes /2

The latest [notes /2](https://docs.google.com/document/d/17LhbrulIVWbfTn7mcwgJ0ZM8OXo5ZEPA-1WGeAwMo2M/edit) are implemented alongside the first playable Contingency prototype.

**Plans:** end a turn with at least 2 unused energy to automatically spend 2 and save 1 Plan token. Save at most once per round and hold at most 2. Press **P** or the Plans button before ending a later turn to arm one contingency for its listed token cost. Draw first if still in the draw phase. Automatic saving can be disabled in this panel.

- **Brace:** select one deployed ally; prevent up to 2 incoming damage from its next attack hit this combat. Periodic status damage bypasses it. Unused protection expires after combat.
- **Coordinated Response:** select one deployed ally. At combat start, it and the nearest ally on each side gain +1 attack for that combat, including across empty lanes. It costs one Plan and does not add Strength stacks. If the chosen ally is no longer deployed, the contingency expires.

One contingency may be armed each round. Tokens, armed plans and temporary boosts reset between encounters. Start with Brace and Coordinated Response; elite and boss victories offer three locked tactics to choose from. Unlock one for the rest of the run. Unlocks reset on a new run. The resource saving and temporary effects are recorded in the combat log.

**Overclock:** gain 2 capacity immediately; ordinary Response growth becomes 2 per round instead of 1. Other resource bonuses still stack. Disaster tension also grows one additional capacity per round. Hero and unit damage increases by 50%, rounded up, after armor but before barriers. This includes periodic status damage, but fixed HP payments such as Static Echo remain fixed. The old draw penalty is removed.

**Evacuation Route:** still costs 4 energy, now has 3 attack / 5 health. On play, optionally move another deployed ally to an empty lane and heal that ally by 2. The unit stays in its original slot; skipping movement does not undo its summon.

**Inspection and log:** hold the left mouse button on a deployed card for 0.35 seconds to inspect its current stats, effects and statuses beside the enlarged card. Release to return to battle. Targeting actions retain their direct clicks. Press **L**, use the Log button, or choose Combat log in the menu for a chronological backlog of up to 300 encounter events. The log resets with the next encounter. Sealed labels are rebuilt on refresh and disappear when the seal expires.

**Deck removal:** shops can destroy an exact selected card copy for 30 supplies and remain open afterward. Rest nodes can retire one card for free instead of healing or training; this completes that node. Removal previews require confirmation, preserve other duplicates and keep at least 5 cards in the collection. These run edits do not add a card to a battle graveyard.

**Starting screen:** the battle menu offers Return to starting screen with a confirmation because it ends the current run. Defeat and victory screens also offer this action. It reloads the title, where an unfinished run can be continued or abandoned. Defeat and completed victory clear the save; endless exploration can begin a new floor. There is no direct restart shortcut.

`res://tests/plans_notes_smoke.gd` checks token limits, real End Turn banking, actual tactic selection, temporary expiry, Overclock, inspection, log bounds, repeated seal refresh, rescue healing, exact-copy shop/rest removal and the actual return-to-title button.

## Hovering and graveyards

Hand selection follows the visible stacking order using each card’s resting footprint. Only one card rises at a time. Lifting a card does not remove its resting hover region, preventing repeated pop-up/reset behavior. Its raised face stays clickable. While dragging, all other hover lifts are suppressed. Right-click cancels a drag; failed placement also restores the hand. Opening a modal clears hover.

During battle, open **Graveyard [G]** to inspect the Response graveyard. Enemy deaths, sacrifices and spells remain in the combat log. Destroyed Response units and successfully cast Response spells appear with their reason and round, including separate copies of the same card. Failed/cancelled spells remain in hand. Entries are battle snapshots with maximum health displayed; battlefield status changes do not rewrite them. The viewer supports sorting and pauses combat. Graveyard access disappears outside battle, including results, shops, events and the map; the next encounter or new run resets its entries. Clearing the battlefield between rooms does not count as a death. Graveyard cards are not automatically reshuffled; returning them requires an effect such as Recovery Detail.


## Notes /3: contingencies, targeting and encounters

Elite and boss wins unlock one new contingency before the usual card or floor reward. Six additional tactics join the two starters: Field Medicine heals an ally 3 and clears Bleed; Supply Drop draws one at combat start; Flanking Route ignores guardian Taunt; Emergency Shelter protects your health pool against 3 attack damage; Precision Drill gives an ally +2 attack for one combat and costs 2 Plans; Emergency Extraction saves an ally from one lethal attack by moving it into a chosen empty lane. All others cost 1 Plan. Extraction requires that lane to remain empty, and cannot prevent periodic status damage. Temporary effects expire after combat; unlocked tactics last the run.

Click board cards for allied spell and contingency targets. Coordinated Response uses two neighboring allies of any type; an empty lane between them is allowed, but another ally between them is not. Extraction uses an ally and then an empty lane. Movement effects use a direct drag; invalid drops, right-click, or Esc restore the ally's original position. Cancelling Emergency Exit keeps its energy and card. Cancelling a summoned unit's optional relocation keeps the summon.

The Janitor holds an actual shared hand of base cards, spells and drawn evolutions. Card backs appear above the board; the floating Janitor hand-count caption is removed. Evolutions must be drawn before being played; hand space is reserved for playable base cards. Seal and cost disruption select only cards held in hand. Opposing hand choices stay face down until Hazard Forecast reveals them. Neither side can seal undealt cards.

Six event variants populate the map: the locked room, radio station, rooftop training, science lab, infirmary, and lost and found. Radio trades 20 supplies for scouting and tutoring spells. Rooftop preparation gives a permanent starting Plan at the cost of 1 energy capacity. Science experiments trade 3 HP for stronger status cards. Full infirmary treatment heals 8 but adds a Paperwork deadweight spell; modest treatment heals 3 without that downside. Lost and found trades an exact removed card for 25 supplies while retaining at least five cards. Event previews stay fixed when reopened.

`res://tests/notes3_smoke.gd` checks physical relocation and cancellation, direct board targeting, tactic unlocks and expiry, masked enemy hands, hand-only sealing, encounter exhaustion, event trades, fixed previews and starting-screen flow.


## Notes /4 and economy playtest

The title uses a full-screen layout inspired by the supplied reference, with temporary native school scenery until final artwork is supplied. Multiplayer is visible but disabled. Continue restores the map, collection, exact draw-pile order, supplies, health, units, statuses, Plans, boss state and pending offers. Abandon requires confirmation. Save writes use a temporary file and replace the previous checkpoint only after writing it. During combat or a drag, the last stable player-turn checkpoint is kept. Unfinished runs created by older versions cannot be recovered retroactively.

Recently added sorting tracks each acquired card copy independently, including shop and event acquisitions. Upgrading a card preserves its acquisition order. Sorting affects only display order. Live card faces refresh when relevant values change, so Strength, temporary Plans, costs, health and statuses stay current without rerendering unchanged faces every frame.

Preparedness begins at 3 energy and has a base ceiling of **7**; resource buffs may raise that ceiling. Barrier stacks cap at **3** on each unit and the player. Plans retain their two-token limit and one contingency per round. Supply Cache, tutoring, scouting, sealing and cost disruption now cost at least 2 energy before upgrades, making them compete with deploying units. Cost disruption expires after the current and next round and cannot accumulate beyond +2. Formation damage bonuses still reward matching types, while Coordinated Response supports mixed formations.

Disaster evolutions pay sacrifices without an additional tension payment. Cinder Cloud applies 2 Burn to its opposing lane card when sacrificed; Glass Quake draws one from the finite Disaster base pile. These rewards do not trigger on ordinary destruction. Evolutions requiring three sacrifices gain 2 Barrier and draw one on entry. Four-sacrifice evolutions gain 3 Barrier, draw one and deal 1 fixed damage to each opposing deployed unit. They still lose the other blockers and attacks sacrificed to create them. The AI includes entry and sacrifice rewards when judging whether an evolution is worth its lost formation. Regular encounters retain their action and evolution restrictions.

This is a balance playtest, not a guarantee of equal win rates. Track how often each side runs out of playable cards, whether keeping a formation beats evolving, and whether a major evolution leaves a reasonable response turn. No existing card or core deck mechanic was removed.

`res://tests/notes4_smoke.gd` checks upward routes, newest-copy sorting, mixed and gapped coordination, live card values, protection and tax limits, sacrifice rewards, major evolution entry effects, atomic save replacement, scene-reload continuation, fixed card/tactic/floor/adaptation offers, boss persistence and confirmed abandonment.

## Notes /5: map, clarity and three camera views

Outside battle, an opaque full-screen map replaces the idle board. Shops, events and the collection also hide battle geometry. M still toggles the map during a battle, while Esc closes the between-room menu back to the map. Graveyards are accessible only in active encounters. Shop, healing, event and removal choices show explicit gains and costs; healing labels account for missing health.

How to Play now has four scrollable categories: Start a run, Battle and Plans, Cards and effects, and Controls. The board and deployed cards share matching lane and collider proportions. Hand hover footprints match the visible card scale. The supplied classroom and dedicated rear table replace the earlier modular room; character positions are empty markers and illustration windows stay blank.

The three camera states are Room (S), normal Table, and Overhead (W). W and S move one step at a time, ignoring key repeats and clamping at either end. An interrupted transition continues smoothly from its current transform. Combat uses Overhead and restores your chosen view afterward; Continue retains all three view states and accepts older two-view checkpoints. The classroom integration checks camera paths inside the finished room and screens for visible void at 16:10, 16:9 and ultrawide sizes.

`res://tests/notes5_smoke.gd` checks map coverage and navigation, battle-only graveyard access, actual healing and removal prices, full-health rest exit, help categories, camera blending/interruption/limits, saved views and deployed scale. A graphical run also captures each help page, the map, shop, three views and a live encounter for visual review. The classroom lighting correction enables desktop anti-aliasing; texture downsizing remains later work.


## October 15 notes /1 and /2: presentation and game feel

The existing bloom, anti-aliasing, clarity, sharpness, anisotropic filtering and lighting remain active with the current supplied classroom. Source textures and models have not been downsized as part of this update.

Each encounter begins with an interactive full-screen Heads/Tails call. The toss animates and shows the landed side before the first turn starts. Calls lock immediately to reject double clicks. Both an unresolved call and a toss already underway can be continued from a checkpoint; the saved outcome and chosen side are retained. The coin outcome is recorded in the combat log. Returning from an older stable battle checkpoint does not replay its opening toss.

Normal battle rewards display three native card faces centered on a darkened, frozen battlefield. Click a face to inspect it, then click the enlarged face again to acquire that exact card once. Clicking outside returns to the same three offers. Skip card reward remains available in the three-card view. Background shortcuts, card interaction and camera raycasts are blocked while choosing. Offers remain fixed through saves. Preview cards render once, stay out of gameplay groups and collisions, and are freed with their modal.

Hold a deployed card, or hold a hand card without moving the pointer, to inspect its face at its native aspect ratio. Moving a hand card starts normal dragging. The side dossier separates permanent upgrades, current statuses, combat effects and full rules. Release to close the inspection and resume. Catalog previews in the deck, shop and workshop use the same hold gesture. Reward cards retain their separate two-press inspection and claim flow.

Short menu/shop fades, button press/hover feedback and reward-card hover states complement the existing stable hand hover. Cards follow eased curves into the hand. Cast utility cards fly to the discard pile; defeated cards burn away with an ember dissolve. Slots, costs, graveyards and rewards update immediately, independently of cosmetic cleanup. Existing attack lunges, impact shakes, damage and status pop-ups remain. Turn/clash and victory banners clarify combat; node entry, map scrolling and floor changes have brief transitions. These effects use event-driven, short-lived tweens rather than new continuously running UI animation loops.

The board is now the reusable native 3D asset `scenes/school_drill_board.tscn`: a worn school slate in a dark wood frame with brass corner caps and faint lane registration marks. It fits the current table and existing slot colliders. It has no Threat Zone or Response Zone labels and leaves card illustration windows blank. Unlike the previous mat, it does not generate a large image pixel by pixel when an encounter scene loads.

`res://tests/coin_rewards_smoke.gd` checks manual calls, matching and losing calls, duplicate prevention, mid-toss and unresolved Continue, overlay cleanup, native card proportions, outside-click dismissal, centered exclusive rewards, exact single-copy acquisition, saved offers, shop animation completion, board labels and defeat cleanup. Existing regression fixtures explicitly select a coin side through the same action; normal play always waits for the player's selection.

## October 16: smaller project and runtime cleanup

Unused environments, duplicate model/textures, obsolete scripts and generated previews are removed from the active project. The current classroom and its 33 original textures retain their geometry and image quality; the model references the existing texture files to avoid storing each image twice. Material instances are shared, fallback card-face checks are bounded, and identical enemy backs are not unnecessarily rebuilt. Card effects, animated dragging, lighting and anti-aliasing remain enabled.

Run `python tools/asset_audit.py` to check dependencies and original texture/geometry integrity. The Windows export preset excludes development-only files and explicitly includes card JSON data. Test captures stay ignored by both Git and Godot.


## October 16 notes 1

The Graveyard button beside the battle controls, or G, opens a compact sortable list with Response cards only. Enemy cards are not stored in a graveyard. It is hidden outside encounters. Select an entry for its snapshot stats and full rules; close the panel or click outside to resume.

The default Table camera now keeps the eight lanes above the resting hand. Hand cards are smaller and fully visible; the dedicated table is 6% smaller horizontally, with its surface still aligned to the board. Room and Overhead views remain available. Dragged hand cards and relocation targets stay within a small boundary around the board. Invalid drops and right-click cancellation still restore the card.

Coordinated Response requires one board click. At combat start it grants +1 attack to the selected ally and the nearest deployed ally on each side. Empty lanes do not block this search; an intervening ally does. All bonuses expire after combat.

Early normal encounters retain their original health and reserve sizes. Their base piles contain at most two special-effect cards on floor one and four on floor two. Basic disasters fill the remaining reserve slots. Normal encounters from floor three onward, elites, bosses and the existing evolution restrictions retain their previous generation rules.

Two Response cards join rewards and shops. Recovery Detail costs 2 energy and returns one destroyed Response unit to hand at its normal replay cost. It consumes that graveyard entry, clears temporary statuses and taxes, and preserves permanent upgrades. Each unit can be recovered once per battle; cancelled or unavailable targets spend nothing. The spell itself is recorded as Cast. Relief Crew costs 3 energy, has base 2 attack and 4 health, and gains one Barrier per destroyed allied unit still in the graveyard, up to two, when played. Neither changes the starter deck.

Card rewards use inspect, cancel and confirm. The first click enlarges a card and shows its full rules. Clicking outside restores the same three offers. Clicking the enlarged face confirms that exact reward once. There are no Take card buttons. Continue restores unclaimed offers without rerolling them or silently granting a reward.

`tests/recovery_coordination_smoke.gd` covers the compact graveyard, recovery limits and full hands, temporary-state cleanup, Continue, one-click coordination, hand clearance, drag limits and cancellation, real reward input, and early-floor-only deck tuning. Existing save loading also resets the opponent-hand display with its current numeric state value.


## October 16 notes 2

The graveyard belongs to Response only. Enemy deaths, sacrifices and spells still resolve normally and stay in the combat log, but no longer allocate graveyard snapshots. New checkpoints omit enemy history; older checkpoints ignore that field while retaining Response entries and recovery limits. The enemy pile counts below Tension are removed; the Tension bar and its current value remain visible.

Threat Zone and Response Zone text is absent from the current slate. The editor HUD now stores the current health, turn, draw and end-turn layout and shares its theme with the runtime menus. Obsolete orb gauges, the old enemy deck plaque, deck shadow and draw caption are removed together with their unused update code. The hidden prototype table and disabled spotlight are also removed. The supplied classroom and its textures are unchanged.

Opening `scenes/card_3d.tscn` in the editor now previews the current Quick Dash card face, with its art window left empty. This preview uses the existing card renderer, disables gameplay processing, and does not require a running battle. At runtime cards continue to use their actual definitions.

Run `tests/graveyard_save_compatibility_smoke.gd` to check the Response-only graveyard, HUD cleanup, event logging and compatibility with older saves. The card preview can also be checked in Godot's editor; the normal editor startup check closes cleanly.

## October 16, section 3

The default camera is closer and the hand sits lower to leave the board visible. Overhead view keeps the hand tucked even when the cursor reaches the bottom edge. New battles animate from the wide view into the table before the coin selection.

Press F3 during a player turn, or use Menu > Debug values, then enter `*****` (five asterisks) in the masked dialog to edit player/enemy HP, energy and tension capacities, current resources, supplies and Plans. Apply values clamps energy and tension to their capacities. The live-card status row edits the selected card immediately; amount 0 removes that status. Cancel closes the panel without applying unsubmitted resource fields. Applied edits belong to the current run and are included in normal autosaves.

Menus, the HUD and card previews share the obsidian/gunmetal, crimson and burnished brass theme in `scripts/ui_theme.gd`. Hazard trim marks unavailable identities and sealed cards. Affinity accents distinguish all eight elements alongside their text labels. The bottom dashboard contains energy, Plans/Contingency, Combat Log, the Response Graveyard, Draw and End Turn. Card art remains intentionally blank.

## Early encounters and recovery

Steve starts each run at 20 HP, with a maximum of 20. Floor 1 normal encounters allow the Janitor one action per round through round 3, then up to two from round 4. Available tension still limits those actions. Later floors, Elites and Bosses retain their existing action rules.

For Floor 1 normal encounters, the opening hand includes a 1-cost Quick Dash or Debris Clearance when an eligible copy remains in the deck. This reorders an existing card without adding copies or changing the collection. Every normal combat victory restores up to 3 HP, capped at 20; Elite and Boss victories do not grant this triage. Older saves resume with HP capped at 20. F3 debug values remain available during stable player turns.

Run `tests/balance_simulation.gd` to compare the previous rules with opening smoothing, the action ramp, triage and their combination across the same 20 seeds. Results are written to `tests/artifacts/`. Add `-- --triage-paths` for carried-HP route comparisons.


## Card inspection and compact menus

Hold the left mouse button on a card for 0.28 seconds without moving to open its inspection and side dossier. The overlay stays open after release. Click the enlarged card or the surrounding backdrop, or press Esc, to close it. The dossier shows the selected card's effects, upgrades and any active statuses or Plan bonuses. Quick clicks and drags keep their normal behavior; reward cards still require inspection followed by a second click to claim.

Hand hover stays below the board slots. The Deck Browser contains the main Deck and Response Graveyard views; effects that ask you to select a held or deployed card still use their own pickers. Pause, utility choices, Plans, the log and debug dialogs use centered compact panels with scrolling. Deck, map, shop, workshop, rewards and card inspection keep their wider layouts.

The debug password is required each time debug opens, including from F3 and the Pause menu. Enter exactly five asterisks; extra characters or spaces are rejected. Esc or Cancel closes the password prompt without changing the run. Card faces show the corner cost badge, ATK, HP and active statuses below the element banner. The center window is reserved for artwork. Upgrade levels appear below grid previews and in the side dossier, which also explains exact resource costs. Disaster units with a positive sacrifice cost consume that many allies; base units and Disaster utilities show their Tension cost instead.
