extends Node
class_name CPUController

@export var preferred_distance: float = 72.0
@export var attack_range: float = 88.0
@export var decision_interval: float = 0.25
@export var attack_cooldown: float = 0.80
@export_range(0.0, 1.0, 0.05) var attack_probability: float = 0.55
@export var corner_check_distance: float = 48.0
@export_range(0.0, 1.0, 0.05) var corner_backstep_probability: float = 0.35
@export var corner_backstep_delay: float = 0.45
@export var corner_backstep_duration: float = 0.30
@export var random_seed: int = 2002

var move_direction: float = 0.0
var punch_requested: bool = false
var decision_time_remaining: float = 0.0
var attack_cooldown_remaining: float = 0.0
var backstep_delay_remaining: float = 0.0
var backstep_time_remaining: float = 0.0
var random_number_generator: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	random_number_generator.seed = random_seed
	stop()


func update_decision(
	delta: float,
	horizontal_distance: float,
	can_attack: bool,
	opponent_near_wall: bool
) -> void:
	attack_cooldown_remaining = maxf(attack_cooldown_remaining - delta, 0.0)
	_update_backstep_timers(delta)
	if backstep_time_remaining > 0.0:
		move_direction = -signf(horizontal_distance)
		punch_requested = false
		return

	decision_time_remaining -= delta
	if decision_time_remaining > 0.0:
		return

	decision_time_remaining = decision_interval
	punch_requested = false
	var distance: float = absf(horizontal_distance)
	var should_hold_corner_spacing: bool = opponent_near_wall and distance <= attack_range
	move_direction = (
		signf(horizontal_distance)
		if distance > preferred_distance and not should_hold_corner_spacing
		else 0.0
	)

	if distance <= attack_range and can_attack and is_zero_approx(attack_cooldown_remaining):
		if random_number_generator.randf() <= attack_probability:
			punch_requested = true
			attack_cooldown_remaining = attack_cooldown
			if opponent_near_wall and random_number_generator.randf() <= corner_backstep_probability:
				backstep_delay_remaining = corner_backstep_delay


func consume_punch_request() -> bool:
	var requested: bool = punch_requested
	punch_requested = false
	return requested


func stop() -> void:
	move_direction = 0.0
	punch_requested = false
	decision_time_remaining = decision_interval
	backstep_delay_remaining = 0.0
	backstep_time_remaining = 0.0


func reset_for_round() -> void:
	attack_cooldown_remaining = 0.0
	stop()


func _update_backstep_timers(delta: float) -> void:
	if backstep_delay_remaining > 0.0:
		backstep_delay_remaining = maxf(backstep_delay_remaining - delta, 0.0)
		if is_zero_approx(backstep_delay_remaining):
			backstep_time_remaining = corner_backstep_duration
	elif backstep_time_remaining > 0.0:
		backstep_time_remaining = maxf(backstep_time_remaining - delta, 0.0)
