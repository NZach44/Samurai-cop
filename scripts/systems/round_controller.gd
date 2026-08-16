extends Node2D

enum MatchState {
	ROUND_START,
	FIGHTING,
	ROUND_OVER,
	MATCH_OVER,
}

const ROUNDS_TO_WIN: int = 2

@export var round_message_duration: float = 0.8
@export var fight_message_duration: float = 1.0
@export var round_end_delay: float = 2.0
@export var match_end_delay: float = 3.0

@onready var fighter_1: Fighter = $Fighter1
@onready var fighter_2: Fighter = $Fighter2
@onready var fighter_1_health_bar: ProgressBar = $HUD/Controls/Fighter1HealthBar
@onready var fighter_2_health_bar: ProgressBar = $HUD/Controls/Fighter2HealthBar
@onready var fighter_1_name_label: Label = $HUD/Controls/Fighter1Label
@onready var fighter_2_name_label: Label = $HUD/Controls/Fighter2Label
@onready var fighter_1_rounds_label: Label = $HUD/Controls/Fighter1RoundsLabel
@onready var fighter_2_rounds_label: Label = $HUD/Controls/Fighter2RoundsLabel
@onready var winner_label: Label = $HUD/Controls/WinnerLabel

var fighter_1_spawn_position: Vector2
var fighter_2_spawn_position: Vector2
var fighter_1_round_wins: int = 0
var fighter_2_round_wins: int = 0
var round_number: int = 1
var match_state: MatchState = MatchState.ROUND_START


func _ready() -> void:
	fighter_1_spawn_position = fighter_1.position
	fighter_2_spawn_position = fighter_2.position

	fighter_1.health_changed.connect(_on_health_changed.bind(fighter_1_health_bar))
	fighter_2.health_changed.connect(_on_health_changed.bind(fighter_2_health_bar))
	fighter_1.defeated.connect(_on_fighter_defeated)
	fighter_2.defeated.connect(_on_fighter_defeated)

	_on_health_changed(fighter_1.current_health, fighter_1.max_health, fighter_1_health_bar)
	_on_health_changed(fighter_2.current_health, fighter_2.max_health, fighter_2_health_bar)
	fighter_1_name_label.text = fighter_1.get_display_name()
	fighter_2_name_label.text = fighter_2.get_display_name()
	_update_round_win_ui()
	_start_round()


func _on_health_changed(current_health: int, max_health: int, health_bar: ProgressBar) -> void:
	health_bar.max_value = max_health
	health_bar.value = current_health


func _on_fighter_defeated(loser: Fighter) -> void:
	# Only the first defeat signal in active play can award this round.
	if match_state != MatchState.FIGHTING:
		return

	match_state = MatchState.ROUND_OVER
	_set_fighter_controls_enabled(false)
	var winner: Fighter = fighter_2 if loser == fighter_1 else fighter_1
	var winner_number: int = 2 if winner == fighter_2 else 1
	if winner == fighter_1:
		fighter_1_round_wins += 1
	else:
		fighter_2_round_wins += 1
	_update_round_win_ui()

	winner_label.text = "PLAYER %d WINS ROUND" % winner_number
	winner_label.show()
	print("ROUND %d: %s wins; %s is defeated" % [
		round_number,
		winner.get_display_name(),
		loser.get_display_name(),
	])

	await get_tree().create_timer(round_end_delay).timeout
	if _get_round_wins(winner) >= ROUNDS_TO_WIN:
		_finish_match(winner, winner_number)
	else:
		round_number += 1
		_start_round()


func _start_round() -> void:
	match_state = MatchState.ROUND_START
	_set_fighter_controls_enabled(false)
	fighter_1.reset_for_round(fighter_1_spawn_position)
	fighter_2.reset_for_round(fighter_2_spawn_position)

	winner_label.text = "ROUND %d" % round_number
	winner_label.show()
	await get_tree().create_timer(round_message_duration).timeout
	if match_state != MatchState.ROUND_START:
		return

	winner_label.text = "FIGHT!"
	await get_tree().create_timer(fight_message_duration).timeout
	if match_state != MatchState.ROUND_START:
		return

	winner_label.hide()
	match_state = MatchState.FIGHTING
	_set_fighter_controls_enabled(true)


func _finish_match(winner: Fighter, winner_number: int) -> void:
	match_state = MatchState.MATCH_OVER
	_set_fighter_controls_enabled(false)
	winner_label.text = "PLAYER %d WINS THE MATCH" % winner_number
	winner_label.show()
	print("MATCH OVER: %s wins the match" % winner.get_display_name())

	await get_tree().create_timer(match_end_delay).timeout
	fighter_1_round_wins = 0
	fighter_2_round_wins = 0
	round_number = 1
	_update_round_win_ui()
	_start_round()


func _get_round_wins(fighter: Fighter) -> int:
	return fighter_1_round_wins if fighter == fighter_1 else fighter_2_round_wins


func _set_fighter_controls_enabled(enabled: bool) -> void:
	fighter_1.set_controls_enabled(enabled)
	fighter_2.set_controls_enabled(enabled)


func _update_round_win_ui() -> void:
	fighter_1_rounds_label.text = "P1 ROUNDS: %d" % fighter_1_round_wins
	fighter_2_rounds_label.text = "P2 ROUNDS: %d" % fighter_2_round_wins
