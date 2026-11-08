# Multiplayer

## Local Versus

Choose Versus on the title screen to start a single Preparedness versus Disaster battle.
With human Disaster, both players share one computer. The pass-the-laptop privacy cover names the next player;
pass the computer, then choose "I am ready". One Versus HUD shows HP, Energy and Tension bars of one height.
The LAN client builds the same HUD pieces as the host. A Preparedness figure stands at the player's seat;
only the Disaster seat sees it (hot-seat Disaster turn, or the Disaster side on LAN).
Matches stay separate from singleplayer saves, rewards and progression. Stored singleplayer state is restored
when the match ends.

Player 1 calls Heads or Tails. The toss winner chooses a side, and that side takes the first turn.
The starting side switches each round, with one combat after both sides finish playing.

The current flags in `new-game-project/scripts/versus_match.gd` include:

- `DISASTER_IS_HUMAN := true`: a human plays Disaster; false uses the existing AI.
- `DISASTER_SEAT_VIEW := true`: the human Disaster uses the far-seat camera and card hand.
  False uses the Disaster panel.
- `PREMATCH_COIN_FLIP := true`: the toss winner chooses a side before round 1.
- `SIDE_BY_SIDE_HUD := true`: both HP plates and resource bars share the top of the screen.
- `EVOLUTION_DRAW_CHOICE := true`: local human Versus offers an evolution draw choice and a held-evolution zone.
- `DISASTER_DRAW_BUTTON := true`: the hot-seat Disaster draws with the deck button. LAN Disaster draws stay automatic.
- `LAN_EVOLUTION_PICKS := true`: LAN evolution draws use the pick offer and held copies.
- `LAN_PREP_UTILITIES := true`: remote Preparedness plays utility cards and the delayed tactics on LAN.
- `UI_CARD_PICKER := true`: deck search, Scout and graveyard choices show card tiles.
- `BALANCE_PATCH := true` and `DISASTER_ENTRY_BARRIER_NERF := true`: the Versus balance patch and one less
  entry Barrier on a major evolution.

### Disaster controls

- Drag a Base card onto an empty Disaster lane, or click the card and then its lane.
- Play a spell onto the board. Spells that need a target open a target popup.
- Play an evolution onto a deployed Disaster, then click any further required sacrifices.
- For Crosswind, drag another Disaster ally onto an empty lane. No panel opens.
- Draw with the deck button, then choose End turn when finished.
- Esc or right-click cancels a picked, held or dragged card or a pending sacrifice choice.
  Use Cancel in a spell target popup to keep the spell in hand.

### Decks

Matches start from one preset per side in `new-game-project/scripts/versus_decks.gd`.
The validator checks 24 main cards per side, six Disaster evolutions, card identities and copy limits.
Preparedness uses Brace plus two other tactics. The finisher rule is not checked yet.
The LAN deck step supports Standard presets or saved custom decks for both players.
These deck rules and balance values still need playtesting with sides and first player rotated.

## LAN Versus

ZeL and Tssy tested LAN Versus over the network on an earlier build.
The final build passed all automated suites and a localhost run; its network re-test is pending.
It uses ENet over UDP port 24680 and protocol 6 (3, plus 1 for evolution picks, plus 2 for utilities).
Both peers need the same game build and Godot version; the handshake also checks the build markers.

Connect both computers to the same local network or the same Radmin VPN network.
On the title screen, choose LAN Versus. One player hosts; the other joins using the host's displayed
LAN IPv4 address or Radmin address. The coin and side-choice step determines which player owns each side.

On the host computer, allow the game executable through Windows Firewall for the network profile in use.
If an inbound port rule is needed, allow UDP 24680 on the host for the local or Radmin network.
Use the trusted network profile rather than opening the port on unrelated public networks.

The client uses the 3D table, a round/turn/phase indicator, live lane cards and read-only opponent lane previews.
Remote Preparedness presses Draw during its own draw phase. The host validates ownership and phase;
opponent-turn and repeated draw requests are refused. Disaster draws remain automatic.
Moves are drags on the host and the client: Crosswind, Lane Marshal, Evacuation Route and Extraction take the
ally and drop it on an empty lane. The host still checks every step. Esc skips an optional move.

Player 2 opens lists on request: L for the battle log, D for its own deck, G or the graveyard button for its
own graveyard. The host answers with the asking seat's own cards only. Log lines that name the other seat's
private cards (Preparedness hand, Plan unlocks, saved tokens, armed Plans) show public words instead.

### LAN limits

- LAN Disaster draws stay automatic. The manual draw step is hot-seat only.
- With `LAN_PREP_UTILITIES` off, utilities and Supply Line, Emergency Shelter and Emergency Extraction show
  "Not available in LAN". With it on (the default) they all work.
- Hidden hands and draw piles are redacted from the opponent's view. A player-hosted match cannot protect
  private information from the host itself.
- Disconnect ends the match. Do not assume reconnection or mid-match recovery is supported.
- The final build network re-test must cover both seat assignments, firewall/Radmin setup, targeting
  and match completion.

## Validation notes

The repo has 134 smoke suites. No suites were run for this documentation update.
Some tests intentionally read malformed save/config files, including `deck_builder_smoke.gd` and
`lan_room_smoke.gd`. Their expected parse-error diagnostics are fixture behavior, not proof of a gameplay fault.
Check each suite's result and unexpected errors; an exit code alone does not establish a clean run.
