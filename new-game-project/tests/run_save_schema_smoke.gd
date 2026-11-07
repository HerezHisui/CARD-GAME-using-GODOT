# Covers: audit A4. A save with a missing, null or wrong-type director or collection is rejected cleanly.
extends SceneTree

var checks := 0
var failures := 0

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func read_with(text: String, save: Node) -> Dictionary:
	var file := FileAccess.open(save.save_path(), FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return save.read_save()

func _initialize() -> void:
	var save: Node = load("res://scripts/run_save.gd").new()
	save.setup(null)
	expect(not save.enabled, "the test uses a disposable save path")
	var bad := [
		'{"version":1}',
		'{"version":1,"director":null}',
		'{"version":1,"director":5}',
		'{"version":1,"director":"x"}',
		'{"version":1,"director":[]}',
		'{"version":1,"director":{}}',
		'{"version":1,"director":{"collection":null}}',
		'{"version":1,"director":{"collection":{}}}',
		'{"version":1,"director":{"collection":"abc"}}',
		'{"version":1,"director":{"collection":[1,2,3]}}',
		'{"version":2,"director":{"collection":[1,2,3,4,5]}}',
		'[1,2,3]',
	]
	for text in bad:
		expect(read_with(text, save).is_empty(), "rejected: " + text)
	var good := read_with('{"version":1,"director":{"collection":[1,2,3,4,5]}}', save)
	expect(not good.is_empty() and good.director.collection.size() == 5, "a valid save still loads")
	save.discard()
	save.free()
	if failures > 0:
		push_error("run_save_schema_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: run_save_schema_smoke (%d checks)" % checks)
	quit(0)
