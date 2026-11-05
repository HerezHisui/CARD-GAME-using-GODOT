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
  The side-by-side HUD shows Energy and Tension bars. Human Crosswind play chooses an ally and destination.
  Matches start from preset decks; the LAN deck step also supports saved custom decks.
- LAN Versus is **EXPERIMENTAL**. It uses ENet UDP 24680, protocol 3, over the same network or Radmin VPN.
  Validation so far is limited to localhost and automated suites. A two-laptop test is still required.
  Remote Preparedness utilities, Supply, Shelter and Extraction show "Not available in LAN".
  Evolution draw choice is local only and off by default (`EVOLUTION_DRAW_CHOICE := false`).

The repo has 75 smoke suites. This is a file count, not a claim that they were run for this documentation update.

## Docs

- [Player guide](new-game-project/RUN_GUIDE.md)
- [Singleplayer design notes](docs/singleplayer.md): rules, card lists and balance changes
- [Multiplayer guide](docs/multiplayer.md): local controls, experimental LAN setup and limitations

For development: [refactor plan](docs/refactor-plan.md) and [refactor notes](docs/refactor-notes.md).
