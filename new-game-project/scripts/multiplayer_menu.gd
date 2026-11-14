extends RefCounted
## Title: the Multiplayer panel. Three buttons: Versus (local), LAN Versus (LAN lobby), Back (title).
## Only used when VersusMatch.LAN_ENABLED is true. Nothing LAN loads here; LAN Versus makes it on first press.


static func show_panel(director: Node) -> void:
	director.reset_panel("MULTIPLAYER", "", "title_help")
	var box: VBoxContainer = director.content
	director.button("Versus", director.start_versus_match, box).name = "VersusButton"
	director.button("LAN Versus", director.open_lan_lobby, box).name = "LanVersusButton"
	director.button("Back", director.show_title, box).name = "BackButton"
