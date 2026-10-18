# Multiplayer plan

Multiplayer is not playable. The menu entry is disabled. Start with a local rules prototype before adding online rooms.

## Scope and tentative rules

One player uses Preparedness and the other uses Disasters. Reuse card identities and effects, but keep multiplayer rules and deck saves separate from singleplayer. Run upgrades, supplies, character perks and saved progress do not transfer.

Tentative decks: 24 main cards per side; Disasters also get six evolutions. Preparedness selects three tactics, including Brace. Begin with two copies per card and unupgraded definitions. These counts and all balance numbers are starting points for testing, not fixed rules.

Use four lanes per side. Alternate the first player each round, with one combat after both playing phases. Start from the current energy, Tension, sacrifice and Plan rules. Set opening hands, draw rates, health and action limits before testing.

## First prototype

Build a deck validator and one legal preset per side. Then run both human sides locally, using a privacy screen between turns. Test costs, targets, sacrifice choices, effect expiry and exact duplicate handling. Check that saving decks cannot overwrite a singleplayer run.

## Online matches

Add private create/join rooms only after local play works. One match authority validates ownership, timing, costs and targets, resolves randomness and applies each action once. Clients receive only information they are allowed to see.

Keep hands and draw order hidden. Public cards, resources and statuses should agree for both players. A player-hosted prototype can support casual tests, but it cannot protect hidden information from the host.

Define surrender, disconnect and reconnect behavior before release. Reconnection must restore the match without repeating damage or exposing private cards. Rotate sides, decks and first player during playtests. Record shortages and why matches end before adjusting balance.
