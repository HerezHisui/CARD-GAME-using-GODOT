# Multiplayer

## Local Versus

Choose Versus on the title screen to start a single Preparedness versus Disaster battle.
With human Disaster, both players share one computer. The pass-the-laptop privacy cover names the next player;
pass the computer, then choose "I am ready". The side-by-side HUD shows Energy and Tension bars.
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
- `EVOLUTION_DRAW_CHOICE := false`: the optional offer and held-evolution zone are disabled by default.
  This feature is local human Versus only. LAN retains the existing evolution draw behavior even if enabled.

### Disaster controls

- Drag a Base card onto an empty Disaster lane, or click the card and then its lane.
- Play a spell onto the board. Spells that need a target open a target popup.
- Play an evolution onto a deployed Disaster, then click any further required sacrifices.
- For human Crosswind play, choose another Disaster ally and then an empty destination lane.
- Choose End turn when finished. Disaster turn draws remain automatic.
- Esc or right-click cancels a picked, held or dragged card or a pending sacrifice choice.
  Use Cancel in a spell target popup to keep the spell in hand.

### Decks

Matches start from one preset per side in `new-game-project/scripts/versus_decks.gd`.
The validator checks 24 main cards per side, six Disaster evolutions, card identities and copy limits.
Preparedness uses Brace plus two other tactics. The finisher rule is not checked yet.
The LAN deck step supports Standard presets or saved custom decks for both players.
These deck rules and balance values still need playtesting with sides and first player rotated.

## Experimental LAN Versus

LAN Versus is **EXPERIMENTAL**. Validation so far is limited to localhost and automated suites.
A two-laptop test is still required before claiming that it works over a real network or Radmin VPN.
It uses ENet over UDP port 24680 and protocol 3. Both peers need the same game build and Godot version;
the connection handshake also checks the Crosswind build marker.

Connect both computers to the same local network or the same Radmin VPN network.
On the title screen, choose LAN Versus. One player hosts; the other joins using the host's displayed
LAN IPv4 address or Radmin address. The coin and side-choice step determines which player owns each side.

On the host computer, allow the game executable through Windows Firewall for the network profile in use.
If an inbound port rule is needed, allow UDP 24680 on the host for the local or Radmin network.
Use the trusted network profile rather than opening the port on unrelated public networks.

The client uses the 3D table, a round/turn/phase indicator, live lane cards and read-only opponent lane previews.
Remote Preparedness presses Draw during its own draw phase. The host validates ownership and phase;
opponent-turn and repeated draw requests are refused. Disaster draws remain automatic.
Human Crosswind has an ally-and-destination chooser on the host and remote Disaster client.

### LAN limits

- Remote Preparedness utilities are unavailable. Supply Line, Emergency Shelter and Emergency Extraction
  are also unavailable. The client shows "Not available in LAN"; supported one-ally tactics remain available.
- Evolution draw choice is local only and off by default. LAN keeps the legacy shared-hand evolution draws.
- Hidden hands and draw piles are redacted from the opponent's view. A player-hosted match cannot protect
  private information from the host itself.
- Disconnect ends the match. Do not assume reconnection or mid-match recovery is supported.
- Two-computer testing must cover both seat assignments, firewall/Radmin setup, targeting and match completion.

## Validation notes

The repo has 75 smoke suites. No suites were run for this documentation update.
Some tests intentionally read malformed save/config files, including `deck_builder_smoke.gd` and
`lan_room_smoke.gd`. Their expected parse-error diagnostics are fixture behavior, not proof of a gameplay fault.
Check each suite's result and unexpected errors; an exit code alone does not establish a clean run.
