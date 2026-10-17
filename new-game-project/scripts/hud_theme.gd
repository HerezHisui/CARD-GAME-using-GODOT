@tool
extends Control
const UI = preload("res://scripts/ui_theme.gd")

func _ready() -> void:
	UI.apply_hud(self)
