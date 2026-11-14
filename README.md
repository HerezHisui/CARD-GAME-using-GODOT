# Midnight DRRills

A school-themed card roguelike made in Godot 4.7. Build a Preparedness deck, survive Disaster encounters, and reach the Warden at the end of the school map.

## Modes

- **Singleplayer:** battle through the school map, earn rewards, upgrade your deck.
- **Versus:** Preparedness vs. Disaster on one laptop (hot-seat) or against an AI Disaster. Matches start from preset decks.
- **LAN Versus:** two players over a local network or a VPN overlay such as Radmin VPN. One player hosts. Port 24680 (UDP). The network test of the latest build is still pending.

## Run it

1. Install [Godot 4.7](https://godotengine.org/download) (developed on 4.7.2).
2. Open `new-game-project/project.godot`.
3. Press Play.

A Windows build will be published on itch.io.

## Docs

- [Player guide](new-game-project/RUN_GUIDE.md)
- [Singleplayer design](docs/singleplayer.md)
- [Multiplayer guide](docs/multiplayer.md)

## Tests

143 headless smoke suites live in `new-game-project/tests/`. Run one with:

    godot --headless --path new-game-project -s tests/<name>_smoke.gd

## Credits

Team Catacomb Coders, Notre Dame of Marbel University (SPAWN entry).

- Stefan Zuri F. Modelo: programmer, game designer, card art
- Ezekiel Gabriel Lopez (team leader): programmer, game designer, title screen, 3D board and Preparedness figure
- Jade Kayne Tan: programmer, sound designer, game designer, audio

The logos were made by the team.

Third-party assets:

- 3D models made with Meshy.
- "Classroom" by Pino_156 on Sketchfab, CC BY 4.0: https://sketchfab.com/3d-models/classroom-d4553cc2008242849214e4cbf8ad8551
- Caveat Brush font, SIL Open Font License 1.1.