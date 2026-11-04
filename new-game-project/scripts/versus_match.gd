extends Node
## One Versus match started from the title screen. Child of run_director, not an autoload.
## It never touches the save file. It keeps the singleplayer run state and puts it back when the match ends.
## The Disaster side is a human (see DISASTER_IS_HUMAN), or the existing AI when that is false.

const VersusDecks = preload("res://scripts/versus_decks.gd")

# Who plays the Disaster in Versus. true = a human uses the Disaster panel, false = the existing AI.
const DISASTER_IS_HUMAN := true
# true = the human Disaster plays from the far seat with real cards. false = the Disaster panel.
const DISASTER_SEAT_VIEW := true
# true = Player 1 calls the coin and the toss winner picks a side. false = the old one-call coin.
const PREMATCH_COIN_FLIP := true

# Sent when the toss winner picks a side. "" means the wait was cancelled.
signal side_chosen(side: String)

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
# Coin flip before the match (PREMATCH_COIN_FLIP). Player 1 calls, the winner picks a side.
var prematch_active := false # true while waiting for the toss winner's side
var prematch_serial := 0 # goes up on every new wait or clear, so old waits stop
var coin_call := -1 # 0 Heads, 1 Tails, -1 none
var coin_winner := 0 # 1 or 2, 0 = none yet
var player1_side := ""
var player2_side := ""
var automated_side := "" # Explicit opt-in for test fixtures, never set by gameplay.

## Player 1 wins the toss when the call matches the result.
static func resolve_winner(called: int, result: int) -> int:
	return 1 if called == result else 2

## The toss winner gets the picked side, the other player gets the other side. Returns {1: side, 2: side}.
static func assign_sides(toss_winner: int, winner_side: String) -> Dictionary:
	var other := VersusDecks.SIDE_DISASTER
	if winner_side == VersusDecks.SIDE_DISASTER: other = VersusDecks.SIDE_PREP
	if toss_winner == 1: return {1: winner_side, 2: other}
	return {1: other, 2: winner_side}

## The picked side goes first in round 1. player_first is true when Preparedness goes first.
static func prep_goes_first(winner_side: String) -> bool:
	return winner_side == VersusDecks.SIDE_PREP

## Start waiting for the toss winner's side. Returns the side, or "" when the wait was cancelled.
func wait_for_side(called: int, result: int) -> String:
	prematch_serial += 1
	var serial := prematch_serial
	prematch_active = true
	coin_call = called
	coin_winner = resolve_winner(called, result)
	player1_side = ""
	player2_side = ""
	if automated_side != "": choose_side.call_deferred(automated_side)
	var side: String = await side_chosen
	if serial != prematch_serial: return ""
	return side

## The later side screen calls this. A repeated, late or unknown choice is ignored.
func choose_side(side: String) -> void:
	if not prematch_active: return
	if side != VersusDecks.SIDE_PREP and side != VersusDecks.SIDE_DISASTER: return
	prematch_active = false
	var sides := assign_sides(coin_winner, side)
	player1_side = sides[1]
	player2_side = sides[2]
	side_chosen.emit(side)

## Forget the coin flip state and wake any old wait so it can end.
func clear_prematch() -> void:
	var was_waiting := prematch_active
	prematch_serial += 1
	prematch_active = false
	coin_call = -1
	coin_winner = 0
	player1_side = ""
	player2_side = ""
	if was_waiting: side_chosen.emit("")

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
	clear_prematch()
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
	game.disaster_seat_view = DISASTER_SEAT_VIEW
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
	clear_prematch()
	# The coin flip may still hide the Preparedness hand.
	game.reveal_versus_hand()
	winner = "preparedness" if prep_won else "disaster"
	restore_run_state()
	director.run_active = false
	director.encounter = "battle"
	var title := "PREPAREDNESS WINS" if prep_won else "DISASTER WINS"
	var subtitle := "The school is safe." if prep_won else "The school was lost."
	director.reset_panel(title, subtitle, "result")
	director.button("Back to title", director.return_title, director.content)
