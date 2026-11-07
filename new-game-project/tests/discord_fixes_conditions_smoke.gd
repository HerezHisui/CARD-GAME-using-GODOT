# Covers: Toxin Hunter's looser Versus condition (Discord fix, item 5). The change lives only in the
# versus_balance.gd override layer behind BALANCE_PATCH. data/*.json keeps the old threshold.
extends SceneTree

const VersusBalance = preload("res://scripts/versus_balance.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func source_card(id: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/response_expansion.json"))
	var cards: Array = parsed if parsed is Array else parsed.get("cards", [])
	for card in cards:
		if card is Dictionary and str(card.get("id", "")) == id: return card
	return {}

func run() -> void:
	var toxin := source_card("toxin_hunter")
	expect(not toxin.is_empty(), "Toxin Hunter is in the data")
	expect(int(toxin.condition.threshold) == 3, "data keeps the old threshold of 3")
	var patched: Dictionary = VersusBalance.card(toxin, true)
	expect(int(patched.condition.threshold) == 2, "Versus balance patch lowers the threshold to 2")
	expect(int(patched.condition.get("strikes", 1)) == 2, "the reward stays attack twice")
	expect(str(patched.condition.status) == "any", "the status stays any of Burn, Poison or Bleed")
	expect(int(VersusBalance.card(toxin, false).condition.threshold) == 3, "patch off keeps 3")
	expect(int(toxin.condition.threshold) == 3, "the source dictionary is not changed")
	var momentum := source_card("momentum_team")
	expect(int(VersusBalance.card(momentum, true).condition.threshold) == 2, "Momentum Team is unchanged")
	if failures > 0:
		push_error("discord_fixes_conditions_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: discord_fixes_conditions_smoke (%d checks)" % checks)
	quit(0)
