extends SceneTree
## A12: the shared LAN validators keep the old rules.
const V = preload("res://scripts/lan_validators.gd")
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func expect(ok: bool, text: String) -> void:
	if not ok:
		failures += 1
		push_error("FAILED: " + text)
func run() -> void:
	expect(V.is_index(0, 3) and V.is_index(2, 3), "0 and size - 1 are indices")
	expect(not V.is_index(3, 3) and not V.is_index(-1, 3), "out of range is refused")
	expect(not V.is_index(1.0, 3) and not V.is_index("1", 3) and not V.is_index(null, 3), "float, string, null refused")
	expect(V.only_fields({"a": 1, "b": 2}, ["a", "b"]), "exact fields pass")
	expect(not V.only_fields({"a": 1}, ["a", "b"]), "a missing field fails")
	expect(not V.only_fields({"a": 1, "b": 2, "c": 3}, ["a", "b"]), "an extra field fails")
	expect(not V.only_fields({"a": 1, "c": 2}, ["a", "b"]), "a wrong field fails")
	print("%s: lan_validators_smoke" % ["FAIL" if failures else "PASS"])
	quit(1 if failures else 0)
