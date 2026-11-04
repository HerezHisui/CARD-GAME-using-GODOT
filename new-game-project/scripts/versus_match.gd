extends Node
## One Versus match started from the title screen. Child of run_director, not an autoload.
## It never touches the save file. It keeps the singleplayer run state and puts it back when the match ends.
## The Disaster side is a human (see DISASTER_IS_HUMAN), or the existing AI when that is false.

const VersusDecks = preload("res://scripts/versus_decks.gd")

# Who plays the Disaster in Versus. true = a human uses the Disaster panel, false = the existing AI.
const DISASTER_IS_HUMAN := true

var director: Node
var game: Node
var running := false
var winner := ""
# Singleplayer state this match touches.
var saved_unlocked: Array[String] = []
var saved_player_buffs: Dictionary = {}
var saved_enemy_buffs: Dictionary = {}
var saved_player_hp := 0
var saved_character := 0
var saved_caption := ""

func setup(owner_director: Node) -> void:
	director = owner_director
	game = director.game

## Turn a list of card ids into card definitions, using the pools from versus_decks.gd.
func _cards_from_ids(ids: Array, pools: Array) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for id in ids:
		for pool: Dictionary in pools:
			if pool.has(id):
				cards.append(pool[id].duplicate(true))
				break
	return cards

func start() -> void:
	if running: return
	var prep: Dictionary = VersusDecks.preset(VersusDecks.SIDE_PREP)
	var disaster: Dictionary = VersusDecks.preset(VersusDecks.SIDE_DISASTER)
	var prep_pool: Dictionary = VersusDecks.pool(VersusDecks.SIDE_PREP)
	var disaster_pool: Dictionary = VersusDecks.pool(VersusDecks.SIDE_DISASTER)
	var prep_deck := _cards_from_ids(prep.main, [prep_pool.base])
	var disaster_deck := _cards_from_ids(disaster.main, [disaster_pool.base, disaster_pool.spells])
	var evolutions := _cards_from_ids(disaster.evolutions, [disaster_pool.evolutions])
	running = true
	winner = ""
	# Remember the singleplayer state before the match changes it.
	saved_unlocked.assign(game.plans.unlocked)
	saved_player_buffs = game.player_run_buffs.duplicate(true)
	saved_enemy_buffs = game.enemy_run_buffs.duplicate(true)
	saved_player_hp = game.player_hp
	saved_character = director.selected_character
	saved_caption = game._player_hp_ui.get_node("Caption").text
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	game.player_hp = game.hero_max_hp()
	game._player_hp_ui.get_node("Caption").text = "PREPAREDNESS"
	# A Versus match is not a run: no autosave, no map, no rewards.
	director.run_active = false
	director.encounter = "versus"
	director.intel_revealed = false
	director.battle_active = true
	director.modal.hide()
	director.screen = ""
	var tactics: Array[String] = []
	tactics.assign(prep.tactics)
	game.disaster_is_human = DISASTER_IS_HUMAN
	game.start_versus(prep_deck, disaster_deck, evolutions, tactics)

func restore_run_state() -> void:
	game.plans.unlocked.assign(saved_unlocked)
	game.player_run_buffs = saved_player_buffs.duplicate(true)
	game.enemy_run_buffs = saved_enemy_buffs.duplicate(true)
	game.player_hp = saved_player_hp
	director.selected_character = saved_character
	game._player_hp_ui.get_node("Caption").text = saved_caption

## Called by run_director.battle_finished when the encounter is "versus".
func finish(prep_won: bool) -> void:
	if not running: return
	running = false
	winner = "preparedness" if prep_won else "disaster"
	restore_run_state()
	director.run_active = false
	director.encounter = "battle"
	var title := "PREPAREDNESS WINS" if prep_won else "DISASTER WINS"
	var subtitle := "The school is safe." if prep_won else "The school was lost."
	director.reset_panel(title, subtitle, "result")
	director.button("Back to title", director.return_title, director.content)
