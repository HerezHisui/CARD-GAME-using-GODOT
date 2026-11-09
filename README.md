# Midnight DRRills

A school-themed card roguelike made in Godot 4.7 (GDScript). Build a Preparedness deck and face Disaster
encounters and the Janitor while climbing the school map. Current work is on the `lan-prototype` branch.

## How to run

1. Install Godot 4.7. The project uses Godot 4.7.2 for development.
2. Open `new-game-project/project.godot`.
3. Run the main scene.

## Modes

- Singleplayer follows the school map, with battles, rewards and deck upgrades.
- Versus starts one Preparedness versus Disaster battle from the title screen. Human Disaster uses hot-seat
  play with a pass-the-laptop privacy cover. `DISASTER_IS_HUMAN` selects human or AI Disaster.
  One Versus HUD is used on every seat, the LAN client included: HP, Energy and Tension bars of one height.
  Moving an ally (Crosswind, Evacuation Route, Lane Marshal, Extraction) is a drag onto an empty lane.
  The hot-seat Disaster draws with the deck button. A Preparedness figure stands at the player's seat;
  only the Disaster seat sees it, and singleplayer never shows it.
  Matches start from preset decks; the LAN deck step also supports saved custom decks.
- LAN Versus uses ENet UDP 24680, protocol 6, over the same network or Radmin VPN.
  ZeL and Tssy tested LAN Versus over the network on an earlier build. The network re-test of this build is pending.
  Remote Preparedness plays its utility cards and every tactic (`LAN_PREP_UTILITIES`). LAN evolution draws
  use the pick offer (`LAN_EVOLUTION_PICKS`). LAN Disaster draws stay automatic.
  Player 2 opens the battle log (L), its own deck (D) and its own graveyard (G) on request.
  Local human Versus uses the evolution draw choice (`EVOLUTION_DRAW_CHOICE := true`).

The repo has 135 smoke suites (`tests/*_smoke.gd`). This is a file count, not a claim that they were run for this
documentation update.

## Docs

- [Player guide](new-game-project/RUN_GUIDE.md)
- [Singleplayer design notes](docs/singleplayer.md): rules, card lists and balance changes
- [Multiplayer guide](docs/multiplayer.md): local controls, LAN setup and limitations

## AI assistance

Parts of the code, tests and docs were written with AI coding assistants. The card art, card frames and UI icons were
made with AI tools under the team's direction, and the game board, Preparedness figure and janitor 3D models were
made with Meshy. Design decisions and playtesting are the team's.

## Credits

Team: Stefan Zuri F. Modelo (design, code, card art), Ezekiel Gabriel Lopez (team leader; title screen, 3D board and
Preparedness figure), Jade Tan (audio). The logos were made by the team.

3D models:

- Game board, Preparedness figure and janitor: model created with Meshy (free plan), CC BY 4.0 License.
- Classroom: "Classroom" by Pino_156 on Sketchfab, CC BY 4.0,
  https://sketchfab.com/3d-models/classroom-d4553cc2008242849214e4cbf8ad8551

Font: Caveat Brush, SIL Open Font License 1.1 (see `new-game-project/assets/fonts/CaveatBrush-OFL.txt`).
