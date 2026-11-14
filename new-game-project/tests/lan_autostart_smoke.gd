extends SceneTree
## lan_autostart.parse: the launch args become {mode, ip}. Pure function, no network.

const LanAutostart = preload("res://scripts/lan_autostart.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func check(args: Array, mode: String, ip: String) -> void:
	var plan: Dictionary = LanAutostart.parse(args)
	expect(plan.get("mode") == mode, "%s gives mode '%s', got '%s'" % [args, mode, plan.get("mode")])
	expect(plan.get("ip") == ip, "%s gives ip '%s', got '%s'" % [args, ip, plan.get("ip")])


func run() -> void:
	check(["host"], "host", "")
	check(["join", "10.0.0.5"], "join", "10.0.0.5")
	check(["join"], "join", "127.0.0.1")
	check([], "", "")
	check(["x"], "", "")
	# The tests run without user args, so run() must leave nothing behind.
	expect(OS.get_cmdline_user_args().is_empty(), "test run has no user args")
	if failures > 0:
		print("lan_autostart_smoke: %d of %d checks FAILED" % [failures, checks])
		quit(1)
		return
	print("lan_autostart_smoke: all %d checks passed" % checks)
	quit(0)
