extends SceneTree
## Drill Night words: no death, forever or old-name wording in player text.
## Scans data JSON values, reset_panel and banner literals, the boss scripts and the combat lines.
const BANNED := "(?i)\\b(trapped|forever|die|dies|dead|death|kill|killed|killing|blood|" \
	+ "drrills|drrm|competition|contest|lesson)\\b"
## Text allowed to keep a banned word, with the reason.
const KEEP := [
]
## Scripts whose every literal is player text (boss intents and banners, buff tiles, leader kits).
const WHOLE_SCRIPTS := ["res://scripts/boss_rules.gd", "res://scripts/final_boss.gd",
	"res://scripts/battle_rules.gd", "res://scripts/leader_kits.gd"]
var failures := 0
var scanned := 0
var banned := RegEx.new()
var literal := RegEx.new()

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error(message)

## Fails on a banned word unless the whole text is on the KEEP list.
func scan(text: String, where: String) -> void:
	scanned += 1
	if text in KEEP: return
	var hit := banned.search(text)
	check(hit == null, "%s: \"%s\" in \"%s\"" % [where, hit.get_string() if hit else "", text])

func scan_value(value: Variant, where: String) -> void:
	if value is String: scan(value, where)
	elif value is Array:
		for item in value: scan_value(item, where)
	elif value is Dictionary:
		for key in value: scan_value(value[key], "%s/%s" % [where, key])

func literals(line: String) -> Array:
	var out: Array = []
	for found in literal.search_all(line): out.append(found.get_string(1))
	return out

func run() -> void:
	banned.compile(BANNED)
	literal.compile("\"((?:[^\"\\\\]|\\\\.)*)\"")

	# The checker itself must catch a banned word, or the scan proves nothing.
	check(banned.search("Trapped after midnight") != null and banned.search("stay forever") != null,
		"The banned-word check finds a hit")
	check(banned.search("Deadweight") == null and banned.search("Make it to dawn") == null,
		"The banned-word check skips longer words and clean text")

	# Data: every string value in every JSON file.
	var data_files := 0
	for file in DirAccess.get_files_at("res://data"):
		if not file.ends_with(".json"): continue
		data_files += 1
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + file))
		check(parsed != null, "%s parses" % file)
		scan_value(parsed, file)
	check(data_files >= 7, "All data files are scanned (%d)" % data_files)

	# Scripts: reset_panel, banner and combat-line literals everywhere; every literal in the boss scripts.
	var panel_lines := 0
	for file in DirAccess.get_files_at("res://scripts"):
		if not file.ends_with(".gd"): continue
		var path := "res://scripts/" + file
		var whole: bool = path in WHOLE_SCRIPTS
		var number := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			number += 1
			if line.strip_edges().begins_with("#"): continue
			# lines.append( also covers the LAN inspect's combat lines (lan_board_3d.gd _combat_text).
			var player_line := line.contains("reset_panel(") or line.contains("banner(") \
				or line.contains("combat.append(") or line.contains("lines.append(")
			if not whole and not player_line: continue
			if player_line: panel_lines += 1
			for text in literals(line): scan(text, "%s:%d" % [file, number])
	check(panel_lines >= 50, "reset_panel and banner lines are found (%d)" % panel_lines)

	print("DN WORDS: %d texts scanned, %d failures" % [scanned, failures])
	quit(1 if failures else 0)
