extends Node2D

@export var round_reset_delay: float = 2.0

@onready var fighter_1: Fighter = $Fighter1
@onready var fighter_2: Fighter = $Fighter2
@onready var fighter_1_health_bar: ProgressBar = $HUD/Controls/Fighter1HealthBar
@onready var fighter_2_health_bar: ProgressBar = $HUD/Controls/Fighter2HealthBar
@onready var winner_label: Label = $HUD/Controls/WinnerLabel

var fighter_1_spawn_position: Vector2
var fighter_2_spawn_position: Vector2
var round_is_over: bool = false


func _ready() -> void:
	fighter_1_spawn_position = fighter_1.position
	fighter_2_spawn_position = fighter_2.position

	fighter_1.health_changed.connect(_on_health_changed.bind(fighter_1_health_bar))
	fighter_2.health_changed.connect(_on_health_changed.bind(fighter_2_health_bar))
	fighter_1.defeated.connect(_on_fighter_defeated)
	fighter_2.defeated.connect(_on_fighter_defeated)

	_on_health_changed(fighter_1.current_health, fighter_1.max_health, fighter_1_health_bar)
	_on_health_changed(fighter_2.current_health, fighter_2.max_health, fighter_2_health_bar)


func _on_health_changed(current_health: int, max_health: int, health_bar: ProgressBar) -> void:
	health_bar.max_value = max_health
	health_bar.value = current_health


func _on_fighter_defeated(loser: Fighter) -> void:
	if round_is_over:
		return

	round_is_over = true
	var winner: Fighter = fighter_2 if loser == fighter_1 else fighter_1
	var winner_number: int = 2 if winner == fighter_2 else 1
	winner_label.text = "PLAYER %d WINS" % winner_number
	winner_label.show()
	print("KO: %s wins; %s is defeated" % [winner.name, loser.name])

	await get_tree().create_timer(round_reset_delay).timeout
	_reset_round()


func _reset_round() -> void:
	fighter_1.reset_for_round(fighter_1_spawn_position)
	fighter_2.reset_for_round(fighter_2_spawn_position)
	winner_label.hide()
	round_is_over = false
