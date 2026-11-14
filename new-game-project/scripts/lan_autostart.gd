extends RefCounted
## Debug only: lets the editor's Debug > Customize Run Instances start a LAN match with no clicks.
## Instance 1 launch args: "-- host". Instance 2: "-- join 127.0.0.1".
## Does nothing in a release build, with LAN off, or without these args.

const VersusMatch = preload("res://scripts/versus_match.gd")
const DEFAULT_IP := "127.0.0.1"


## Reads the user args. Returns {mode, ip}. mode is "host", "join" or "" (do nothing).
static func parse(args: Array) -> Dictionary:
	var plan := {"mode": "", "ip": ""}
	if args.is_empty():
		return plan
	var first := str(args[0])
	if first == "host":
		plan.mode = "host"
	elif first == "join":
		plan.mode = "join"
		plan.ip = str(args[1]) if args.size() > 1 else DEFAULT_IP
	return plan


## Called once by run_director at startup. Uses the same functions as the lobby buttons.
static func run(director: Node) -> void:
	if not OS.is_debug_build() or not VersusMatch.LAN_ENABLED:
		return
	var plan := parse(Array(OS.get_cmdline_user_args()))
	if plan.mode == "":
		return
	director.open_lan_lobby()
	var lan: Node = director.lan_title
	if plan.mode == "host":
		lan.show_host()
		# lan_title's own handler runs first (connected earlier), so remote_id is set before Start.
		var start := func(_id: int) -> void: lan.start_match.call_deferred()
		lan.session.peer_joined.connect(start, CONNECT_ONE_SHOT)
	else:
		lan.show_join()
		lan.ip_edit.text = plan.ip
		lan.connect_to_host()
