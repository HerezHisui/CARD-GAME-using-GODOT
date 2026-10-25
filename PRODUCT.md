# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Two groups play the same game:

- Deckbuilder and roguelike card fans who want strategy depth and replayable runs.
- Students who are new to the genre and are learning disaster risk reduction (DRR).

The game has to be fun first and still easy for a newcomer to read.

## Product Purpose

Midnight DRRills is a school-themed card roguelike. The player is Steve, using Preparedness cards to hold off
Disaster encounters (fire, earthquake, flood, typhoon) and the Janitor, climbing a room map to the Midnight Warden.

Success means:

- Players learn DRR habits through play: which response fits which disaster (Evac vs Earthquake, Douse vs Fire,
  Clearance vs Flood, Brace vs Typhoon).
- Runs are fun and players want to start another one.
- The game works as a polished portfolio piece.

## Positioning

The core counters are real disaster-preparedness responses, so learning the strategy and learning DRR are the
same thing. Preparedness builds a steady formation and plans its answers. Disasters build pressure by sacrificing
units to make stronger threats.

## Operating Context

- Played on a Windows desktop with mouse and keyboard.
- One run moves through rooms on a map (battles, elites, shops, infirmaries, events) up to a floor-three boss.
- Battles use four lanes per side, a coin call for first turn, energy for Response and Tension for Disasters,
  and a single combat phase each round.
- Saves happen automatically at stable player turns and room choices.

## Capabilities and Constraints

- Godot 4.7 (tested with 4.7.2), GDScript only. A 3D table and cards with a 2D UI on top.
- The export target is Windows Desktop. Input is mouse and keyboard only: no controller, no touch.
- `web` above is only the schema value for "not native mobile". This is not a browser product.
- Colors live in `new-game-project/data/ui_theme.tres`.
- Only singleplayer with Steve is playable. Three club leaders have deck data but are disabled.
  Multiplayer appears in the menu but is not playable. See `docs/multiplayer.md`.
- Card numbers, balance and save formats must not change as a side effect of UI work.

## Brand Commitments

- Name: Midnight DRRills. Setting: a school at midnight.
- Cast and sides: Steve, the Janitor, the Midnight Warden. The two sides are Preparedness and Disaster.
- The UI must read as made by a person, never generic or AI-looking. Keep on-screen text to a minimum.
- Visual direction (set by the user): Limbus Company. Dark UI with gold accents, minimal text, hand-made feel.

## Evidence on Hand

- Card definitions: `new-game-project/data/starter_deck.json`, `response_expansion.json`, `disaster_deck.json`,
  `disaster_expansion.json`. These are the source for costs, stats and effects.
- Player guide: `new-game-project/RUN_GUIDE.md`. Design notes: `docs/singleplayer.md`.
- There are no testimonials, player numbers, press or store pages. Do not make any up.

## Product Principles

1. Fun first. The DRR lesson lives inside the mechanics, not in text on top of them.
2. Show, don't tell. Costs, effects and matchups should be visible before a choice is confirmed, with as few words as possible.
3. A newcomer can read the board. Strategy depth never needs genre knowledge to get started.
4. Hand-made over generic. Every screen should look intentional and specific to this game.
5. Keep the two sides distinct: a steady, planned Preparedness against escalating Disasters.
