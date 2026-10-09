# Midnight DRRills

Open `project.godot` in Godot 4.7 and run the main scene. The game begins on a title screen with Start, How to Play, and Quit. Start opens character selection; preview a starter deck before beginning. Future start-screen artwork can be placed at `assets/title_screen.png`; the title screen uses it automatically after Godot imports it. All card art windows remain blank.

## The run

Choose an illuminated starting room, then follow connected rooms toward the Janitor boss. Each floor has eleven stages and three branching lanes, merging at the boss. Mandatory combat rows ensure every route includes at least four normal/elite battles before the boss. Scroll sideways through the map; it follows your current progress when reopened. Layouts vary by run; every room has a route forward. Normal encounters favor one disaster element, elites have tougher cards and a Hallway Guardian evolution, and bosses have more health and a Midnight Cataclysm evolution. Later floors scale difficulty.

Player health, supplies, collected cards, and upgrades persist between rooms **during the current session**. Each battle begins with a fresh shuffled copy of the collection. Health damage and sacrifices affect those battle copies only. There is no save-to-disk or multiplayer implementation in this update.

Battle wins grant supplies and a choice of one of three cards. Workshops improve one card; infirmaries offer healing or an upgrade. Supply rooms allow multiple purchases from fixed stock and repeatable healing until you leave. Events have explicit risk/reward choices. Defeat ends the run. Each boss win offers a permanent floor buff before advancing to a harder floor.

## Controls

- Drag a hand card onto an empty lower Response slot. Right-click cancels a drag.
- Draw once during the draw phase using the lower-right draw button.
- Space or **End turn** submits your turn. The coin flip determines the first side, alternating each round.
- W shows the board from above; S returns to the desk.
- D opens the collection, unordered remaining draw pile, hand, and deployed Response cards. Sort by Name, Type, Cost, Attack, Health, or Modifier, in either direction. Sorting never changes draw order or your collection.
- M opens and closes the school map during battles and between encounters. When you close it between rooms, a reminder directs you back to M to choose the next room. Next rooms unlock after completing the encounter and reward choice.
- Esc opens the menu. Deck, map, and menu overlays pause an active encounter. Close or Resume continues it.
- Restart requires a second click on the restart confirmation screen.
- The battle menu includes **Quit game**, which closes the game. Runs are not saved to disk.

## Workshops and shops

Workshops have the same sorting controls as the deck browser. **Preview upgrade** shows the current card beside its upgraded version; only **Confirm upgrade** changes the collection. **Every card copy can upgrade at most twice**, shown as 0/2, 1/2, or 2/2. Evac gains attack and on-play draw, then health and a cheaper energy cost. Douse gains attack and Burn, then health and healing after each strike. Clearance gains attack and Poison, then health and +2 attack against targets with three harmful status stacks. Brace gains health and stronger armor, then health and retaliation. Spells first become cheaper; later upgrades strengthen draw, seal, tax, rally, or cleanse. Movement, tutor, and scouting upgrades refund energy instead. Zero-cost spells can improve their abilities. Duplicate cards retain their original identity when sorted, so only the selected copy changes.

Shops offer four distinct cards, each with one copy in stock. Buying one marks it sold and keeps the shop open; remaining stock does not reroll. Healing can be purchased repeatedly until health is full or supplies run out. The room is completed only when you press **Leave shop**.

## Cards

The original twelve-card starter deck and existing disaster cards are preserved. Card illustration windows are deliberately empty. Assign future illustrations in the `ART` dictionary in `scripts/card_3d.gd`. Backs have four corner element marks and a central double ring.

Evac counters Earthquake, Douse counters Fire, Clearance counters Flood, and Brace counters Typhoon at 2Ã— damage. Weak matchups deal half damage. Two adjacent deployed cards of the same element receive +1 attack (not cumulative across both neighbors). Armored reduces incoming attack damage by one (minimum one), Fragile adds one, Regenerating heals up to maximum health, Fierce adds two to hero hits, and Rampaging adds one when attacking a card as the second side of the round.

**Normal attacks never deal overkill/overflow damage to the opposing hero.** Even a one-health blocker stops the entire hero hit. **Piercing** damages the blocker normally and also deals the attacker's effective attack plus adjacency bonus to the opposing health pool. Type effectiveness applies to the blocker only. Fierce adds two to this hero hit. An open lane hits the hero once, including for Piercing cards.

**Sluggish** attacks the first round it can attack, then rests the next round, repeating. Its timing is per card, rather than based on odd/even global rounds. **Strength** adds to attack before type effectiveness and lasts while the card exists. Temporary card statuses and costs do not alter the permanent collection.

**Burn** deals its stack count in damage at the start of the round, then halves its stacks, rounding down. **Poison** deals its stack count at the start of the round, then loses one stack. **Bleed** damages its card by the stack count after that card attacks, then loses one stack. Skipped attacks do not trigger Bleed. These fixed status hits bypass Armored and Fragile. Regeneration happens after status damage; dead cards cannot regenerate. On-hit status effects apply only to a surviving blocker.

Reward and shop pools include utility cards: **Supply Cache** draws two cards up to the hand limit; **Emergency Exit** moves the nearest friendly deployed card into the empty slot you target. Both spend energy and disappear after use. Emergency Exit returns to hand without spending energy if no deployed ally exists. Hover over deck previews for rules.

The expansion adds thirteen Response cards and eight Disaster cards. Response units include Needle Team (Piercing), Heavy Loader (Sluggish), Steam Team (Burn), Shard Barrier (Bleed), Hazmat Team (Poison), Supply Runner (draw one on play), and Drill Captain (two Strength). The Cadet retains the original twelve-card deck; themed characters start with different cards. New Response cards also appear in rewards and shops. Disaster encounters include matching status-based units, Piercing and Sluggish evolutions, and disruption spells.

Targeted Response spells are cast by dragging them onto an empty Response slot, then choosing a target:

- **Search and Rescue:** choose an unlocked card from your draw pile and put it into your hand. Displays an alphabetic list, keeping pile order hidden.
- **Safety Lock:** choose a card from the opposing draw pile, evolution pile, or hand. It cannot be drawn or played for this round and the next. Already deployed units are unaffected.
- **Hazard Forecast:** reveal the Janitor's hand for this encounter. Reopen it through D afterward.
- **Containment Order:** raise one opposing hand or evolution card's cost by one for this encounter. Disaster evolutions require one more sacrifice; base disasters and utility spells require one more tension. Response costs remain energy-based.
- **Rally the Team:** give a deployed ally two Strength.
- **Decontaminate:** heal a deployed ally by three and remove Burn, Poison, and Bleed.

Target selectors pause play. Cancel or Esc keeps the spell and energy. No-target casts return to hand. Disaster disruption spells can seal Response hand/draw-pile cards or increase a Response hand card's energy cost. Seals expire automatically when their indicated round begins.

## Global adaptations

At the start of rounds **5, 10, 15, ...** of each encounter, both sides receive a **battle-only adaptation**. You choose one of three randomly offered buffs; the Janitor chooses one of the same three, shown on screen. The battle pauses until you choose. Deck viewing preserves the exact offers. Adaptations expire when the encounter ends.

There are fifteen battle adaptations. Strong options have explicit tradeoffs: Glass Cannon adds two attack but removes one maximum health; Overclock adds two resources but removes one normal draw; Blood Pact adds three attack but applies two Bleed on selection and entry; Patient Formation regenerates two health but makes units Sluggish; Toxic Ward strengthens Poison while reducing attack; Close Ranks rewards matching neighbors but penalizes isolation; Piercing Formation grants Piercing while reducing attack; Bristling Defense retaliates for one fixed damage while reducing health. Smaller stat, status, and draw buffs remain available without drawbacks.

After **every floor boss**, choose one of three **permanent run rewards** from an eight-option pool. The Janitor also chooses a permanent reward. These stack across later battles and floors; a new run clears them. Examples include Signal Beacon (extra draws), School Bulwark (health for reduced attack), Buddy System (adjacency bonuses with an isolation penalty), Field School (resources and draws for less health), Hazard Manual (stronger statuses for reduced resources), and Infirmary Network (hero healing for reduced unit attack).

Battle adaptations and permanent rewards combine during a fight. Health stays at least one; attack stays at least zero; resource capacity stays at least one. Negative draw bonuses can reduce normal draws to zero, but spell and unit-triggered draws still work. Response resource bonuses increase starting capacity, its upper limit, and positive cap growth. Disaster bonuses alter tension and the action limit, between one and five actions. Menu summaries distinguish **Battle** buffs from **Run** buffs for both sides.

## New units and smarter encounters

Six more Response units and six more disasters join the pools. Lane Marshal and Rescue Crane optionally move another deployed ally after being played: choose the ally, then an empty lane. The played card stays where it was summoned. Skipping movement keeps the summon and its energy payment. Crosswind lets the Janitor relocate an ally if a better lane is available. Field Medic and Warm Front heal other allies by two; Drill Leader and Aftershock Choir grant other allies one Strength. Recovery Team and Drain Vortex heal after attacking. Cutting Crew, Black Squall, and Worldbreaker add stronger Piercing/status combinations.

Major original evolutions now need **two sacrifices**; Inferno, Tsunami, Sleeping Fault, Drain Vortex, Black Squall, and the boss's Midnight Cataclysm need **three**. Worldbreaker needs **four**. Needle Gale remains a smaller one-sacrifice evolution. Elite Guardian needs two. Sealing and cost disruption still apply to evolutions.

Elite and boss AI compares cards and lanes using effectiveness, survival before counterattack, immediate hero lethals, defensive coverage, and synergies. It evaluates sacrifice combinations and declines evolutions that discard more board value than they gain or expose lethal lanes. Disruption targets and buff choices are ranked rather than random. All encounters use board-aware sacrifice decisions; normal placement and buff choices retain more variety. Evolution planning compares the entire formation before and after sacrificing, including lost blockers and matching-neighbor bonuses. It penalizes losing a numerical advantage and compares filling an empty lane against evolving. A valuable field advantage can be kept without sacrificing; a winning Piercing evolution can still be chosen. AI uses the public board and its own available cards for battle planning; it does not inspect draw-pile order.

Empty draw piles do not immediately end a match while cards remain in hand or on board. A side with no usable cards left loses. Preparedness begins at three and its cap grows each round; Disaster evolutions retain the sacrifice mechanic and separate evolution deck.

## Verification

Run Godot with `--headless --path . --script` and each of `res://tests/run_smoke.gd`, `res://tests/mechanics_smoke.gd`, `res://tests/expansion_smoke.gd`, `res://tests/improvements_smoke.gd`, and `res://tests/variety_smoke.gd` for integration checks. Graphical runs also capture previews in `tests/artifacts`. Checks cover connectivity, combat, statuses, cancellation, restart, sorting without reordering, duplicate-specific upgrades, before/after previews, shop stock and multiple purchases, summon movement, buff expiry and persistence, stronger sacrifices, tactical decisions, and the actual menu Quit button. Balance still needs playtesting with final artwork and content.


## Starter characters

All characters begin with 12 cards. Their starting perk lasts the run and stacks with floor rewards. Restarting keeps your chosen character; the title screen lets you choose a different one.

- **Alex, Cadet:** original mixed Response deck; +1 unit health.
- **Mika, Route Marshal:** Evac neighbors, movement, draw and tutoring; matching neighbors deal one additional damage.
- **Sam, Hazmat Specialist:** Douse/Clearance status units and hunters; +2 applied Burn and +1 applied Poison, with -1 unit health (minimum 1).
- **Jo, Barricade Captain:** armored Brace units, Strength and healing; surviving blockers retaliate for one fixed damage.

## Encounter and shop balance

First-floor normal/elite/boss health is **20 / 24 / 28**, increasing by three each additional floor. Base-card reserves are capped at **20 / 21 / 22**; evolution reserves at **12 / 14 / 15**, including elite/boss signature cards. Encounters still favor a disaster element and retain varied cards.

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
