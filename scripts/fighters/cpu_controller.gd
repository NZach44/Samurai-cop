extends Node
class_name CPUController

enum AttackChoice {
	NONE,
	PUNCH,
	KICK,
	SPECIAL_1,
	SPECIAL_2,
}

@export var preferred_distance: float = 72.0
@export var attack_range: float = 88.0
@export var decision_interval: float = 0.25
@export var attack_cooldown: float = 0.80
@export_range(0.0, 1.0, 0.05) var attack_probability: float = 0.55
@export var special_cooldown: float = 2.40
@export_range(0.0, 1.0, 0.05) var repeat_weight_multiplier: float = 0.30
@export_range(0.0, 1.0, 0.05) var block_probability: float = 0.55
@export var block_reaction_delay: float = 0.18
@export var block_reaction_variation: float = 0.08
@export var block_hold_duration: float = 0.38
@export var threat_range_padding: float = 16.0
@export var corner_check_distance: float = 48.0
@export_range(0.0, 1.0, 0.05) var corner_backstep_probability: float = 0.35
@export var corner_backstep_delay: float = 0.45
@export var corner_backstep_duration: float = 0.30
@export var random_seed: int = 2002

var move_direction: float = 0.0
var attack_request: AttackChoice = AttackChoice.NONE
var block_requested: bool = false
var decision_time_remaining: float = 0.0
var attack_cooldown_remaining: float = 0.0
var special_cooldown_remaining: float = 0.0
var backstep_delay_remaining: float = 0.0
var backstep_time_remaining: float = 0.0
var block_reaction_remaining: float = -1.0
var block_hold_remaining: float = 0.0
var block_decision_made: bool = false
var last_attack_choice: AttackChoice = AttackChoice.NONE
var random_number_generator: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	random_number_generator.seed = random_seed
	stop()


func update_decision(
	delta: float,
	horizontal_distance: float,
	can_attack: bool,
	can_block: bool,
	opponent_is_attacking: bool,
	opponent_is_in_front: bool,
	opponent_attack_reach: float,
	opponent_near_wall: bool,
	attack_reaches: PackedFloat32Array
) -> void:
	attack_cooldown_remaining = maxf(attack_cooldown_remaining - delta, 0.0)
	special_cooldown_remaining = maxf(special_cooldown_remaining - delta, 0.0)
	_update_backstep_timers(delta)
	var distance: float = absf(horizontal_distance)
	var threat_active: bool = (
		opponent_is_attacking
		and opponent_is_in_front
		and distance <= opponent_attack_reach + threat_range_padding
	)
	_update_defense_timers(delta, opponent_is_attacking, threat_active, can_block)

	decision_time_remaining -= delta
	var should_make_decision: bool = decision_time_remaining <= 0.0
	if should_make_decision:
		decision_time_remaining = decision_interval
		attack_request = AttackChoice.NONE
		_consider_block(threat_active, can_block)

	if block_requested or block_reaction_remaining >= 0.0:
		move_direction = 0.0
		attack_request = AttackChoice.NONE
		return

	if backstep_time_remaining > 0.0:
		move_direction = -signf(horizontal_distance)
		attack_request = AttackChoice.NONE
		return

	if not should_make_decision:
		return

	var maximum_attack_reach: float = _get_maximum_attack_reach(attack_reaches)
	var should_hold_corner_spacing: bool = (
		opponent_near_wall
		and distance <= maximum_attack_reach
	)
	move_direction = (
		signf(horizontal_distance)
		if distance > preferred_distance and not should_hold_corner_spacing
		else 0.0
	)

	if (
		distance <= maximum_attack_reach
		and can_attack
		and is_zero_approx(attack_cooldown_remaining)
	):
		if random_number_generator.randf() <= attack_probability:
			attack_request = _choose_attack(distance, attack_reaches)
			if attack_request != AttackChoice.NONE:
				attack_cooldown_remaining = attack_cooldown
				if attack_request in [AttackChoice.SPECIAL_1, AttackChoice.SPECIAL_2]:
					special_cooldown_remaining = special_cooldown
				last_attack_choice = attack_request
				if (
					opponent_near_wall
					and random_number_generator.randf() <= corner_backstep_probability
				):
					backstep_delay_remaining = corner_backstep_delay


func consume_attack_request() -> AttackChoice:
	var requested: AttackChoice = attack_request
	attack_request = AttackChoice.NONE
	return requested


func stop() -> void:
	move_direction = 0.0
	attack_request = AttackChoice.NONE
	block_requested = false
	decision_time_remaining = decision_interval
	backstep_delay_remaining = 0.0
	backstep_time_remaining = 0.0
	block_reaction_remaining = -1.0
	block_hold_remaining = 0.0
	block_decision_made = false


func reset_for_round() -> void:
	attack_cooldown_remaining = 0.0
	special_cooldown_remaining = 0.0
	last_attack_choice = AttackChoice.NONE
	stop()


func _update_backstep_timers(delta: float) -> void:
	if backstep_delay_remaining > 0.0:
		backstep_delay_remaining = maxf(backstep_delay_remaining - delta, 0.0)
		if is_zero_approx(backstep_delay_remaining):
			backstep_time_remaining = corner_backstep_duration
	elif backstep_time_remaining > 0.0:
		backstep_time_remaining = maxf(backstep_time_remaining - delta, 0.0)


func _update_defense_timers(
	delta: float,
	opponent_is_attacking: bool,
	threat_active: bool,
	can_block: bool
) -> void:
	if not opponent_is_attacking:
		block_requested = false
		block_reaction_remaining = -1.0
		block_hold_remaining = 0.0
		block_decision_made = false
		return

	if block_requested:
		block_hold_remaining = maxf(block_hold_remaining - delta, 0.0)
		if not threat_active or is_zero_approx(block_hold_remaining):
			block_requested = false

	if block_reaction_remaining >= 0.0:
		block_reaction_remaining = maxf(block_reaction_remaining - delta, 0.0)
		if is_zero_approx(block_reaction_remaining):
			block_reaction_remaining = -1.0
			if threat_active and can_block:
				block_requested = true
				block_hold_remaining = block_hold_duration * random_number_generator.randf_range(
					0.75,
					1.0
				)


func _consider_block(threat_active: bool, can_block: bool) -> void:
	if not threat_active or not can_block or block_decision_made:
		return
	block_decision_made = true
	if random_number_generator.randf() > block_probability:
		return
	block_reaction_remaining = maxf(
		block_reaction_delay + random_number_generator.randf_range(
			-block_reaction_variation,
			block_reaction_variation
		),
		0.0
	)


func _choose_attack(distance: float, attack_reaches: PackedFloat32Array) -> AttackChoice:
	var candidates: Array[Dictionary] = []
	var punch_reach: float = _get_attack_reach(AttackChoice.PUNCH, attack_reaches)
	var is_close: bool = punch_reach > 0.0 and distance <= punch_reach
	_add_attack_candidate(candidates, AttackChoice.PUNCH, 5.0, distance, attack_reaches)
	_add_attack_candidate(
		candidates,
		AttackChoice.KICK,
		2.5 if is_close else 5.0,
		distance,
		attack_reaches
	)
	if is_zero_approx(special_cooldown_remaining):
		_add_attack_candidate(
			candidates,
			AttackChoice.SPECIAL_1,
			0.9 if is_close else 1.4,
			distance,
			attack_reaches
		)
		_add_attack_candidate(
			candidates,
			AttackChoice.SPECIAL_2,
			0.6 if is_close else 1.1,
			distance,
			attack_reaches
		)

	var total_weight: float = 0.0
	for candidate: Dictionary in candidates:
		total_weight += float(candidate["weight"])
	if is_zero_approx(total_weight):
		return AttackChoice.NONE

	var selection: float = random_number_generator.randf() * total_weight
	for candidate: Dictionary in candidates:
		selection -= float(candidate["weight"])
		if selection <= 0.0:
			return int(candidate["choice"])
	return int(candidates.back()["choice"])


func _add_attack_candidate(
	candidates: Array[Dictionary],
	choice: AttackChoice,
	base_weight: float,
	distance: float,
	attack_reaches: PackedFloat32Array
) -> void:
	var reach: float = _get_attack_reach(choice, attack_reaches)
	if reach <= 0.0 or distance > reach:
		return
	var weight: float = base_weight
	if choice == last_attack_choice:
		weight *= repeat_weight_multiplier
	candidates.append({"choice": choice, "weight": weight})


func _get_attack_reach(choice: AttackChoice, attack_reaches: PackedFloat32Array) -> float:
	if choice < 0 or choice >= attack_reaches.size():
		return 0.0
	return attack_reaches[choice]


func _get_maximum_attack_reach(attack_reaches: PackedFloat32Array) -> float:
	var maximum_reach: float = attack_range
	for reach: float in attack_reaches:
		maximum_reach = maxf(maximum_reach, reach)
	return maximum_reach
