extends SceneTree
## Card art: every ART entry points to a file that exists, and the six Warden boss cards have art.

const CardScript = preload("res://scripts/card_3d.gd")

const WARDEN_NAMES: Array[String] = [
	"Night Watch",
	"Hall Monitor",
	"West Circuit Pillar",
	"East Circuit Pillar",
	"Shield Guardian",
	"Emergency Shackle",
]

var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func run() -> void:
	# Every ART value must be a real file. The imported texture must load too.
	for card_name in CardScript.ART:
		var path: String = CardScript.ART[card_name]
		expect(ResourceLoader.exists(path), "art file exists for " + card_name)
	# The six Warden names are in ART and load as textures.
	for card_name in WARDEN_NAMES:
		expect(CardScript.ART.has(card_name), "ART has " + card_name)
		var path: String = CardScript.ART.get(card_name, "")
		var tex = load(path) if path != "" else null
		expect(tex is Texture2D, "Warden art loads as a texture: " + card_name)
	# The name to key helper keeps the Warden names as they are.
	for card_name in WARDEN_NAMES:
		expect(CardScript.art_key(card_name) == card_name, "art_key keeps " + card_name)
	print("warden_art_smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
