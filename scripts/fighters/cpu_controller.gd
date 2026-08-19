extends Node
class_name CPUController

enum AttackChoice {
	NONE,
	PUNCH,
	KICK,
	SPECIAL_1,
	SPECIAL_2,
}

const PRESSURE_MAX: float = 3.0
const PRESSURE_DECAY_PER_SECOND: float = 0.60
const PRESSURE_DISTANCE_PADDING: float = 28.0
const COUNTER_WINDOW_DURATION: float = 0.34

@export var difficulty_profile: CpuDifficultyProfile = preload(
	"res://data/difficulties/medium.tres"
)
@export var preferred_distance: float = 72.0
@export var attack_range: float = 88.0
@export var threat_range_padding: float = 28.0
@export var corner_check_distance: float = 48.0
@export var corner_backstep_delay: float = 0.45
@export var corner_backstep_duration: float = 0.30
@export var random_seed: int = 2002
@export var debug_decisions: bool = false

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
var pressure_score: float = 0.0
var opponent_was_attacking: bool = false
var observed_opponent_attack_sequence: int = -1
var opponent_active_phase_seen: bool = false
var opponent_in_recovery: bool = false
var counter_window_remaining: float = 0.0
var random_number_generator: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	random_number_generator.seed = random_seed
	reset_for_round()


func set_difficulty_profile(profile: CpuDifficultyProfile) -> void:
	if profile != null:
		difficulty_profile = profile
		decision_time_remaining = _next_decision_interval()


func update_decision(
	delta: float,
	horizontal_distance: float,
	can_attack: bool,
	can_block: bool,
	opponent_is_attacking: bool,
	opponent_attack_is_active: bool,
	opponent_attack_sequence: int,
	opponent_is_in_front: bool,
	opponent_attack_reach: float,
	opponent_near_wall: bool,
	attack_reaches: PackedFloat32Array
) -> void:
	attack_cooldown_remaining = maxf(attack_cooldown_remaining - delta, 0.0)
	special_cooldown_remaining = maxf(special_cooldown_remaining - delta, 0.0)
	counter_window_remaining = maxf(counter_window_remaining - delta, 0.0)
	_update_backstep_timers(delta)

	var distance: float = absf(horizontal_distance)
	var maximum_attack_reach: float = _get_maximum_attack_reach(attack_reaches)
	var attack_started: bool = (
		opponent_is_attacking
		and opponent_attack_sequence != observed_opponent_attack_sequence
	)
	var attack_ended: bool = not opponent_is_attacking and opponent_was_attacking
	if attack_started:
		observed_opponent_attack_sequence = opponent_attack_sequence
		opponent_active_phase_seen = false
		opponent_in_recovery = false
		block_requested = false
		block_reaction_remaining = -1.0
		block_hold_remaining = 0.0
		block_decision_made = false
	if opponent_attack_is_active:
		opponent_active_phase_seen = true
	var recovery_started: bool = (
		opponent_is_attacking
		and opponent_active_phase_seen
		and not opponent_attack_is_active
		and not opponent_in_recovery
	)
	if recovery_started:
		opponent_in_recovery = true
	_update_pressure(delta, attack_started, distance, opponent_attack_reach)
	opponent_was_attacking = opponent_is_attacking
	if recovery_started or attack_ended:
		_consider_counterattack(distance, maximum_attack_reach)
	if attack_ended:
		opponent_active_phase_seen = false
		opponent_in_recovery = false

	var threat_active: bool = (
		opponent_is_attacking
		and not opponent_in_recovery
		and opponent_is_in_front
		and distance <= opponent_attack_reach + threat_range_padding
	)
	_update_defense_timers(delta, opponent_is_attacking, threat_active, can_block)
	_consider_defense(threat_active, can_block)

	decision_time_remaining -= delta
	var should_make_decision: bool = decision_time_remaining <= 0.0
	if should_make_decision:
		decision_time_remaining = _next_decision_interval()
		attack_request = AttackChoice.NONE

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

	var pressure_factor: float = _get_pressure_factor()
	var target_distance: float = (
		preferred_distance
		* difficulty_profile.preferred_distance_multiplier
		* (1.0 + pressure_factor * difficulty_profile.pressure_response_probability * 0.12)
	)
	var should_hold_corner_spacing: bool = (
		opponent_near_wall
		and distance <= maximum_attack_reach
	)

	if (
		counter_window_remaining > 0.0
		and distance <= maximum_attack_reach
		and can_attack
		and is_zero_approx(attack_cooldown_remaining)
	):
		var counter_choice: AttackChoice = _choose_counterattack(distance, attack_reaches)
		if counter_choice != AttackChoice.NONE:
			_queue_attack(counter_choice, opponent_near_wall)
			counter_window_remaining = 0.0
			return

	if (
		distance < target_distance * 0.78
		and pressure_factor > 0.25
		and random_number_generator.randf()
			<= difficulty_profile.retreat_probability
			* difficulty_profile.pressure_response_probability
			* pressure_factor
	):
		backstep_time_remaining = corner_backstep_duration
		move_direction = -signf(horizontal_distance)
		_debug_decision("RETREAT")
		return

	move_direction = (
		signf(horizontal_distance)
		if distance > target_distance and not should_hold_corner_spacing
		else 0.0
	)

	if (
		distance <= maximum_attack_reach
		and can_attack
		and is_zero_approx(attack_cooldown_remaining)
		and random_number_generator.randf() <= difficulty_profile.attack_probability
	):
		var choice: AttackChoice = _choose_attack(distance, attack_reaches)
		if choice != AttackChoice.NONE:
			_queue_attack(choice, opponent_near_wall)


func register_opponent_pressure(amount: float = 1.0) -> void:
	pressure_score = clampf(pressure_score + maxf(amount, 0.0), 0.0, PRESSURE_MAX)
	# Repeated contact shortens the next think cycle, but actions still go through
	# Fighter permissions and retain their normal startup/recovery timing.
	var response_scale: float = (
		1.0
		- _get_pressure_factor()
		* difficulty_profile.pressure_response_probability
		* 0.65
	)
	decision_time_remaining = minf(
		decision_time_remaining,
		difficulty_profile.decision_interval_min * response_scale
	)
	attack_cooldown_remaining = minf(
		attack_cooldown_remaining,
		difficulty_profile.attack_cooldown * response_scale
	)


func update_inactive(delta: float) -> void:
	# Memory still fades during stun without allowing any decisions or actions.
	pressure_score = maxf(pressure_score - PRESSURE_DECAY_PER_SECOND * delta, 0.0)


func register_blocked_opponent_attack() -> void:
	register_opponent_pressure()
	# Block stun outlasts the remainder of the current active window, so do not
	# keep holding guard through the attacker's recovery frames.
	block_requested = false
	block_reaction_remaining = -1.0
	block_hold_remaining = 0.0
	block_decision_made = true
	opponent_active_phase_seen = true
	opponent_in_recovery = true
	# A successful guard creates a fair punish opportunity during the attacker's
	# existing recovery; profile probability keeps the response imperfect.
	var counter_probability: float = minf(
		difficulty_profile.counterattack_probability
			* (0.65 + _get_pressure_factor() * 0.35),
		0.90
	)
	if random_number_generator.randf() <= counter_probability:
		counter_window_remaining = COUNTER_WINDOW_DURATION
		decision_time_remaining = 0.0
		# The Fighter was able to guard, so no attack recovery is being skipped;
		# clear only the controller's optional pacing delay for this punish chance.
		attack_cooldown_remaining = 0.0
	elif (
		random_number_generator.randf()
		<= difficulty_profile.retreat_probability
		* difficulty_profile.pressure_response_probability
	):
		backstep_time_remaining = corner_backstep_duration


func consume_attack_request() -> AttackChoice:
	var requested: AttackChoice = attack_request
	attack_request = AttackChoice.NONE
	return requested


func stop() -> void:
	move_direction = 0.0
	attack_request = AttackChoice.NONE
	block_requested = false
	decision_time_remaining = _next_decision_interval()
	backstep_delay_remaining = 0.0
	backstep_time_remaining = 0.0
	block_reaction_remaining = -1.0
	block_hold_remaining = 0.0
	block_decision_made = false
	counter_window_remaining = 0.0


func reset_for_round() -> void:
	attack_cooldown_remaining = 0.0
	special_cooldown_remaining = 0.0
	last_attack_choice = AttackChoice.NONE
	pressure_score = 0.0
	opponent_was_attacking = false
	observed_opponent_attack_sequence = -1
	opponent_active_phase_seen = false
	opponent_in_recovery = false
	stop()


func _update_pressure(
	delta: float,
	attack_started: bool,
	distance: float,
	opponent_attack_reach: float
) -> void:
	update_inactive(delta)
	if (
		attack_started
		and distance <= opponent_attack_reach + threat_range_padding + PRESSURE_DISTANCE_PADDING
	):
		register_opponent_pressure(0.75)


func _update_backstep_timers(delta: float) -> void:
	if backstep_delay_remaining > 0.0:
		backstep_delay_remaining = maxf(backstep_delay_remaining - delta, 0.0)
		if is_zero_approx(backstep_delay_remaining):
			backstep_time_remaining = corner_backstep_duration
			_debug_decision("RETREAT")
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
				block_hold_remaining = random_number_generator.randf_range(
					difficulty_profile.block_hold_min,
					difficulty_profile.block_hold_max
				)
				_debug_decision("BLOCK")


func _consider_defense(threat_active: bool, can_block: bool) -> void:
	if not threat_active or not can_block or block_decision_made:
		return
	block_decision_made = true
	var pressure_factor: float = _get_pressure_factor()
	var effective_block_probability: float = minf(
		difficulty_profile.block_probability
			+ (1.0 - difficulty_profile.block_probability)
			* pressure_factor
			* difficulty_profile.pressure_response_probability,
		0.92
	)
	if random_number_generator.randf() <= effective_block_probability:
		block_reaction_remaining = random_number_generator.randf_range(
			difficulty_profile.defensive_reaction_min,
			difficulty_profile.defensive_reaction_max
		)
	elif (
		pressure_factor > 0.0
		and random_number_generator.randf()
			<= difficulty_profile.retreat_probability
			* difficulty_profile.pressure_response_probability
			* pressure_factor
	):
		backstep_time_remaining = corner_backstep_duration
		_debug_decision("RETREAT")


func _consider_counterattack(distance: float, maximum_attack_reach: float) -> void:
	if distance > maximum_attack_reach:
		return
	var pressure_bonus: float = 1.0 + _get_pressure_factor() * 0.20
	if (
		random_number_generator.randf()
		<= difficulty_profile.counterattack_probability * pressure_bonus
	):
		counter_window_remaining = COUNTER_WINDOW_DURATION
		decision_time_remaining = 0.0


func _queue_attack(choice: AttackChoice, opponent_near_wall: bool) -> void:
	attack_request = choice
	attack_cooldown_remaining = difficulty_profile.attack_cooldown
	if choice in [AttackChoice.SPECIAL_1, AttackChoice.SPECIAL_2]:
		special_cooldown_remaining = difficulty_profile.special_cooldown
	last_attack_choice = choice
	_debug_decision(str(AttackChoice.keys()[choice]))
	if (
		opponent_near_wall
		and random_number_generator.randf() <= difficulty_profile.retreat_probability
	):
		backstep_delay_remaining = corner_backstep_delay


func _choose_attack(distance: float, attack_reaches: PackedFloat32Array) -> AttackChoice:
	var candidates: Array[Dictionary] = []
	var punch_reach: float = _get_attack_reach(AttackChoice.PUNCH, attack_reaches)
	var is_close: bool = punch_reach > 0.0 and distance <= punch_reach
	_add_attack_candidate(
		candidates,
		AttackChoice.PUNCH,
		difficulty_profile.punch_weight,
		distance,
		attack_reaches
	)
	_add_attack_candidate(
		candidates,
		AttackChoice.KICK,
		difficulty_profile.kick_weight * (0.65 if is_close else 1.15),
		distance,
		attack_reaches
	)
	if is_zero_approx(special_cooldown_remaining):
		_add_attack_candidate(
			candidates,
			AttackChoice.SPECIAL_1,
			difficulty_profile.special_weight * (0.75 if is_close else 1.0),
			distance,
			attack_reaches
		)
		_add_attack_candidate(
			candidates,
			AttackChoice.SPECIAL_2,
			difficulty_profile.special_weight * (0.55 if is_close else 0.85),
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


func _choose_counterattack(
	distance: float,
	attack_reaches: PackedFloat32Array
) -> AttackChoice:
	var punch_reach: float = _get_attack_reach(AttackChoice.PUNCH, attack_reaches)
	var quick_punish_probability: float = (
		0.75 + difficulty_profile.counterattack_probability * 0.25
	)
	if last_attack_choice == AttackChoice.PUNCH:
		quick_punish_probability *= 0.85
	if (
		punch_reach > 0.0
		and distance <= punch_reach
		and random_number_generator.randf() <= quick_punish_probability
	):
		return AttackChoice.PUNCH
	return _choose_attack(distance, attack_reaches)


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
		weight *= difficulty_profile.repeat_attack_penalty
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


func _get_pressure_factor() -> float:
	return pressure_score / PRESSURE_MAX


func _next_decision_interval() -> float:
	return random_number_generator.randf_range(
		difficulty_profile.decision_interval_min,
		difficulty_profile.decision_interval_max
	)


func _debug_decision(decision: String) -> void:
	if debug_decisions:
		print("[%s] CPU decision: %s" % [difficulty_profile.profile_name, decision])
