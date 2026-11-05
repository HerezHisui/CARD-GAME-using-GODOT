# Tester issue #14: remote Preparedness utilities and contingencies

Plan only, 2026-11-06. Inspected branch `lan-prototype`, HEAD `743f125`.
No gameplay changes, flag changes, test execution, commit or push in this task.

## Current cause and scope

- `preparedness_actions.gd`: `_card_problem` rejects every utility; `use_utility` always returns `not_supported`.
- `lan_actions.gd` already routes `utility {hand, target}` to that stub; routing alone is insufficient.
- `lan_view.gd` supplies unit-lane hints, Plan tokens and tactic hints, but no utility choice state or candidates.
- Contingencies are not wholly unavailable: one-ally tactics already use `use_tactic` and `arm_tactic`.
  `NOT_SUPPORTED_TACTICS` specifically excludes Supply Line, Emergency Shelter and Emergency Extraction.
- `lan_board_3d.gd` and `lan_prep_panel.gd` need Preparedness picks. Despite its name,
  `lan_client_panel.gd` is the Disaster panel; it needs no change for this feature.
- The D2-b/c report records these exclusions intentionally. Its historical flag/status claims are stale;
  current source is authoritative. `contingency_rules.gd` owns delayed timing, tokens and extraction.

## Proposed implementation

1. Add a separate `LAN_PREP_UTILITIES` flag, false by default, with an enabled-mode test override.
   Preserve all current flags and the disabled path. Simple must play both seat assignments before enabling it.
2. Implement authoritative utility actions without opening a host-local menu or borrowing local seat ownership
   across an await. Extract reusable rule application from `game_3d_manager.gd`; keep local/singleplayer behavior.
3. Extend existing `utility` into begin/pick/cancel stages. The host creates a private pending choice with
   encounter serial, choice ID, source identity and current legal targets. A pick carries only those IDs.
   Block conflicting play/draw/end actions while pending; cancellation spends nothing and cannot reroll a choice.
4. Support the actual effect families: draw, blast, barrier, herb and tablet need no target;
   rally/cleanse choose a deployed ally; seal chooses an eligible enemy field card;
   tax chooses a blind enemy-hand entry; move chooses an ally then an empty lane;
   tutor chooses an eligible own-deck entry; recover chooses an eligible own graveyard entry.
   Scout needs a private intel view matching the existing reveal rule, not a host-only modal.
   Preserve current empty-lane, capacity, effect-power, consumption and expiry rules, including failure behavior.
5. Retain existing one-ally tactics. Supply and Shelter send no ally target; Extraction picks an ally and
   empty destination. Reuse `contingency_rules.arm`, including delayed combat resolution, rather than applying
   effects immediately. Share seat-independent validation instead of expanding the temporary local-seat workaround.

## Host validation and private view

- Authenticate the RPC sender through `seat_of`; require remote Preparedness, active encounter and play phase.
- Validate message types, source membership, utility/tactic identity, unlocks, energy, seals, tokens,
  committed round, armed/pending state, eligible live targets and destination occupancy before spending anything.
- Reject stale serials, replaced sources, forged/duplicate picks and changed target membership without mutation.
  Snapshot card IDs are rebuilt per view; use stable choice-local handles, not persistent snapshot IDs or names.
- Preparedness view adds utility availability/reasons, pick kind, legal handles, pending choice and tactic target
  requirements. Reveal own tutor/recover candidates only while needed. Tax gets blind handles, never faces.
- Scout may reveal only what its rule permits, for the existing lifetime; unrelated Disaster cards/decks and RNG
  remain absent. Send no Preparedness candidates, pending secrets or intel in the Disaster view.
- Send a fresh authoritative view after success, rejection and cancellation, including hand-only/token changes.
  Restore pending UI after a refreshed view; invalidate it on reset, disconnect, match end or encounter change.

## Files and client picking

Existing production owners: `versus_match.gd`, `preparedness_actions.gd`, `game_3d_manager.gd`,
`contingency_rules.gd`, `lan_actions.gd`, `lan_session.gd`, `lan_view.gd`, `lan_board_3d.gd`,
`lan_prep_panel.gd`. Add one focused helper for utility/pending-choice rules if extraction needs it.
`run_director.gd` may also need narrow changes to share local rule application without host UI side effects.
The 3D board and fallback Preparedness panel both need no-target activation, ally/enemy lane picks,
ally-then-destination picks, blind hand picks, private candidate lists, prompts and Cancel/Esc handling.
Hints guide picking; they never authorize an action. Existing units, Draw and one-ally tactics remain usable.

## Tests, cost and risks

- Add 3-4 suites: authoritative effect/tactic matrix; private-view redaction; real-input client picks/cancel;
  loopback RPC with forged/stale/repeated/wrong-seat actions and disconnect/reset during each pick stage.
- Cover spending exactly once, invalid/cancelled actions spending nothing, empty/full zones, duplicate copies,
  sealed/taxed sources, effect expiry, scout privacy, delayed Supply/Shelter/Extraction, and hand-only refreshes.
- Run enabled tests plus affected local utility/contingency suites and all LAN suites serially.
  Before release, run the full disabled suite set and test both owners on two real computers.
- Existing tests deliberately assert `not_supported`: `lan_seats_smoke.gd:112-113` and
  `lan_prep_smoke.gd:176,331`. Keep them unchanged under the default-off flag; add enabled fixtures separately.
- Estimate: 9-11 production files plus 3-4 new suites, about 1,100-1,700 added/changed lines including tests.
  This is an implementation estimate, not a tested count or delivery promise.
- Protocol: existing `utility.target` cannot safely represent all stages. Add an enabled-feature capability/build
  check before match start; reject incompatible peers clearly. PROTOCOL 2 alone does not establish compatibility.
  Decide capability encoding before implementation; disabled matches retain their existing transport behavior.
- Highest risks: secret candidate leakage, stale hand indices, double spending, host modal pauses, lost pending
  choices and late messages changing a new encounter. Keep host authority and explicit cancellation boundaries.

## Tonight and safe fallback

**No**, full support cannot safely be promised in one more session tonight. The effect matrix, private intel,
multistep choices and delayed tactics need implementation plus input, redaction and real-peer validation.
A smaller subset would be a separate scoped approval, not completion of #14.

If skipped, keep authoritative `not_supported` guards and supported one-ally tactics. Show
"Not available in LAN" for unsupported utility/tactic attempts and a visible explanation beside disabled items;
do not hide the whole contingency interface. Apply the explanation in both 3D and fallback Preparedness UIs.
Estimate 15-30 production lines across `lan_board_3d.gd` and `lan_prep_panel.gd`, plus a new 20-40-line UI check.
This improves clarity only; #14 remains deferred. Keep `743f125` as the baseline; release approval is separate.
