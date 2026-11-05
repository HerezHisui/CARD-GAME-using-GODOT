# Multiplayer

Versus is playable from the title screen. Choose Versus for two humans on one computer, using pass and play.
One player uses Preparedness and the other uses Disasters. A privacy cover hides the screen between human turns.
Pass the computer to the named player, then choose "I am ready" to continue.

## Local matches

Matches use preset decks and stay separate from singleplayer saves, rewards and progression.
Run buffs are cleared for the match, and the stored singleplayer state is restored when the match ends.
The shared coin screen asks for Heads or Tails. Matching the random toss lets Preparedness go first.
Otherwise Disaster goes first. The starting side switches each round, with one combat after both playing phases.

In `scripts/versus_match.gd`, both flags are currently true:

- `DISASTER_IS_HUMAN` gives the Disaster turn to a human. When false, the existing AI plays that side.
- `DISASTER_SEAT_VIEW` flips the camera to the far seat and shows the human Disaster hand as cards.
  When false, the human uses the Disaster panel instead.

## Disaster seat controls

- Drag a Base card onto an empty Disaster lane, or click the card and then its lane.
- Play a spell onto the board. Spells that need a target open a target popup.
- Play an evolution onto a deployed Disaster. That card is the first sacrifice.
  Click any further required sacrifices to finish the evolution.
- Choose End turn when finished.
- Esc or right-click cancels a picked, held or dragged card or a pending sacrifice choice.
  Use Cancel in a target popup to keep the spell in hand. With no pending choice, Esc opens the menu.

## Decks and remaining work

The code already has a deck validator and one preset per side in `scripts/versus_decks.gd`.
It checks deck sizes, card identities, copy limits, evolution piles and Preparedness tactics.
The finisher rule is not checked yet. Custom deck saves and online rooms are not built.

Stage 2e would let Player 1 choose Heads or Tails for one flip, then let the winner choose a side and go first.
That side-selection step is not built. The current coin screen only decides which side starts.

Current deck rules use 24 main cards per side, six Disaster evolutions and at most two copies per card.
Preparedness uses Brace plus two other tactics. These counts and balance numbers remain subject to playtesting.
Rotate sides, decks and first player during tests before adjusting balance.

## Known limits

Opening the on-screen Menu during a Disaster drag leaves the drag stuck after Resume.
A click-picked Disaster card stays picked after a modal, such as the battle log, closes.

## Online matches

Add private create/join rooms only after local play works. One match authority validates ownership, timing, costs and targets, resolves randomness and applies each action once. Clients receive only information they are allowed to see.

Keep hands and draw order hidden. Public cards, resources and statuses should agree for both players. A player-hosted prototype can support casual tests, but it cannot protect hidden information from the host.

Define surrender, disconnect and reconnect behavior before release. Reconnection must restore the match without repeating damage or exposing private cards. Rotate sides, decks and first player during playtests. Record shortages and why matches end before adjusting balance.
