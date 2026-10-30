# Midnight DRRills player guide

Open `project.godot` in Godot 4.7 and run the main scene. Choose Singleplayer, then Steve. The other characters and Multiplayer are not playable yet. A saved run offers Continue or Abandon.

## Starting a run

Steve starts with 20 HP, 35 supplies and 12 cards: 3 Quick Dash, 3 Fire Drill, 2 Fire Hose, 2 Debris Clearance, 1 Evacuation Route and 1 Shelter Brace. His perk gives units 1 extra health.

Pick a connected room on the map. Follow connected rooms toward the boss. Complete each room and its rewards before moving on. Every route includes at least four normal or elite battles. HP, supplies, collected cards and upgrades carry between rooms. Each encounter uses a fresh shuffled copy of the collection. Damage to battle cards does not change their permanent copies.

## Controls

- Drag a hand card onto an empty Response slot. The slot under the cursor is the drop target. Right-click cancels a drag.
- Use Draw during the draw phase to draw one random unsealed card for free. Playing a card still pays its listed cost. Only Search and Rescue lets you pick the card.
- Space or End turn submits your turn. Finish or cancel board targeting first.
- W moves from Room to Table to Overhead. S moves back. Room view hides your hand. Camera changes are blocked during combat, dragging and board targeting.
- D opens the deck browser. Sorting changes the display, not the collection or draw order.
- G or the Graveyard button opens the Response graveyard during battle.
- M toggles the battle map. Between encounters the map stays open.
- Esc closes an overlay or cancels a pending board choice. From battle it opens the menu.
- Hold a card for 0.28 seconds without moving to inspect it. Release keeps inspection open. Click the card or backdrop, or press Esc, to close it. Hand inspection is disabled in Overhead view.

Deck, map and menu overlays pause battle. Inspect a reward, then click its enlarged face to claim it. Clicking outside returns to the same offers; Skip declines the reward.

## Rounds and resources

Call Heads or Tails at encounter start. A matching result lets Steve go first. Otherwise the Janitor goes first. The starting side switches each round.

Response starts with 3 energy capacity and three hand cards. The hand limit is eight. Resources refill each round. After combat, the energy cap normally grows by 1, up to a base ceiling of 7. Adaptations can change capacity and growth.

Draw, play units or utilities, then end the turn. Both sides finish playing before the single combat phase. The first side attacks first. A unit attacks the opposite lane; an empty lane lets it hit the opposing hero. A side that exhausts its usable cards loses.

The Janitor uses Tension for base cards and spells. Evolutions use deployed allies as sacrifices instead of paying an extra Tension cost. Evolutions must be in its shared hand before use. A sealed deployed Disaster cannot evolve or be used as sacrifice material during its affected round. Taxes can raise a held evolution's sacrifice cost.

## Combat and effects

Evac counters Earthquake, Douse counters Fire, Clearance counters Flood and Brace counters Typhoon for double damage. Weak matchups deal half damage. Matching adjacent allies give a unit 1 extra attack; having matches on both sides does not double that base bonus.

Ordinary attacks never spill excess damage from a blocker into the hero. Piercing also hits the hero, but an Armored blocker prevents that hero hit even if it dies. Piercing bypasses armor reduction against the blocker. Barrier and Plan protection still apply. An open lane receives one hero hit, not two.

Strength adds attack before type effectiveness. Armored reduces ordinary incoming damage, with a minimum of 1. Fragile adds 1 incoming damage. Regeneration heals surviving units after round-start status damage. Sluggish units attack on alternating opportunities, starting with their first eligible attack.

Burn deals its stacks at round start, then halves them, rounding down. Poison deals its stacks at round start, then loses 1. Bleed deals its stacks after the card attacks, then loses 1. Skipped attacks do not trigger Bleed. These status hits bypass Armored and Fragile. On-hit statuses require a surviving blocker.

Conditional attacks use the named subject and stack threshold. Venom Surge gains 2 attack against 3+ Poison on its target. Last Responder gains 2 against a target with 2+ Bleed. A double strike checks eligibility once, but each strike resolves its own damage, effects and Bleed. If the blocker dies, the follow-up can hit the open lane.

## Plans and utilities

Ending a turn automatically banks 2 unused energy into 1 Plan token, at most once per round. Hold up to two tokens and arm one tactic per round. Tactics take effect during combat and expire afterward. Unlocks last the run; tokens reset between encounters.

Brace protects one ally from up to 2 damage on its next attack hit. Coordinated Response gives the selected ally and its nearest ally on each side 1 temporary attack. Empty lanes and different types do not prevent coordination. Elite and boss rewards can unlock other tactics, including healing, extraction and temporary hero protection.

Cast utilities by dropping them on an empty Response lane, then choosing a target if needed. Utilities have no unit ATK or HP. Cancelling a target choice keeps the card and energy. Rally and healing use board clicks; relocation uses board dragging. Response seals target deployed Disaster cards. The restriction lasts this round when Response plays first, or next round when Response plays second. Sealed units can still attack. Enemy seals and all taxes continue to target held cards. Tax lasts for the current and next round and caps at 2 extra cost.

Recovery Detail costs 2 energy and returns one eligible destroyed Response unit to hand. It keeps permanent upgrades and clears temporary effects. Each unit can be recovered once per battle. Relief Crew costs 3 and gains up to 2 Barrier from destroyed allies still in the graveyard. Only Response has a graveyard.

## Rooms and progression

Normal wins give 20 supplies and heal up to 3 HP. Elite wins give 35 supplies; ordinary boss wins give 60. Elite and boss wins do not grant normal-win healing. Advancing a floor separately heals up to 5 HP. Healing stops at the hero's maximum.

Shops keep fixed stock and allow several purchases before leaving. Each offered copy can be bought once. First aid costs 15 supplies and heals up to 5 HP. Shop card removal costs 30 supplies. Supplies show a coin icon. Infirmaries offer healing, an upgrade or free removal; their healing restores up to 7 HP. Removal cannot reduce the collection below five cards.

Each copy can upgrade twice. Previewing is free; confirmation changes only that copy. Basic units gain stats first and new draw, Burn, Poison or Armor at tier two. Existing abilities may improve at tier one. Utilities can become cheaper or improve their effect.

Battle adaptations are offered every fifth round and expire after the encounter. Permanent floor rewards carry through the run. Both are player-only. Overclock trades more capacity for increased incoming damage. Blood Pact gives 2 Strength, but deployed units that fail to kill a card die at combat end. Hero hits and resting do not count.

The floor-three Midnight Warden uses announced patterns instead of the usual random deck. Its middle phase shields the boss behind pillars and a guardian. Read the intent and plan around the targeted lanes.

## Saving and leaving

Stable player turns and room choices save automatically. Continue restores the unfinished run, including fixed reward offers. Returning to the title keeps it; Abandon clears it after confirmation. Defeat ends the run. Closing during an animation resumes the last stable checkpoint rather than the middle of that animation.

## Debug controls

Press F3 during a player turn, or choose Menu > Debug values, and enter exactly `*****` each time.
Choose a live hand or board card to edit its cost, base ATK, current HP or statuses. Utilities only expose cost.
Card edits apply at once. HP stays at least 1; raising it can also raise the card's healing limit.
These edits affect that battle copy, not the collection, and are included in normal checkpoints.

The unlocked debug panel also offers a floor-boss picker. Enter boss starts that floor's encounter immediately with the current collection and restored player HP. Floor three initializes the Midnight Warden.

Game Settings controls attack/status effects and boss fog. Preferences are saved locally. Boss fog covers the distant arena and map edges while keeping card information and route controls readable. Alarm Sweep costs 4 energy.

For base costs and stats, see the [card data](data/).
