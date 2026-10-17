# Midnight DRRills

A school-themed card roguelike made in Godot 4.7 (GDScript). You play Steve, using Preparedness cards to hold off Disaster encounters and the Janitor. Fires, earthquakes, floods and typhoons come at you, and you build up a deck as you climb the map.

Multiplayer is in the menu but not playable yet.

## How to run

1. Install Godot 4.7.
2. Open `new-game-project/project.godot`.
3. Run the main scene.

## Docs

- [Player guide](new-game-project/RUN_GUIDE.md)
- [Singleplayer design notes](docs/singleplayer.md): rules, card lists and balance changes
- [Multiplayer plan](docs/multiplayer.md): ideas for a future mode

## Tests

Each test is a script in `new-game-project/tests/` that ends in `_smoke.gd`. Run one from the `new-game-project` folder:

```
godot --headless --path . --script res://tests/run_smoke.gd
```

The graphical ones (`classroom_integration`, `camera_controls`, `visual_quality`) need a normal renderer instead of `--headless`.