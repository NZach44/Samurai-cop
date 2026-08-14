extends CharacterBody2D
class_name Fighter

signal health_changed(current_health: int, max_health: int)
signal defeated(fighter: Fighter)

enum ControlMode {
	HUMAN,
	CPU,
}

@export var move_speed: float = 240.0
@export var jump_velocity: float = 600.0
@export var minimum_fighter_spacing: float = 56.0
@export var separation_speed: float = 160.0
@export var max_health: int = 100
@export var hit_stun_duration: float = 0.25
@export var control_mode: ControlMode = ControlMode.HUMAN
@export var left_action: StringName = &"p1_left"
@export var right_action: StringName = &"p1_right"
@export var jump_action: StringName = &"p1_jump"
@export var punch_action: StringName = &"p1_punch"
@export var opponent: Node2D
@export var punch_damage: int = 10
@export var punch_knockback_speed: float = 300.0
@export var punch_startup_time: float = 0.12
@export var punch_active_time: float = 0.10
@export var punch_recovery_time: float = 0.20

@onready var visuals: Node2D = $Visuals
@onready var punch_hit_box: Area2D = $Visuals/PunchHitBox
@onready var cpu_controller: CPUController = $CPUController

var is_punching: bool = false
var punch_is_active: bool = false
var hit_target_ids: Dictionary = {}
var current_health: int
var is_in_hit_stun: bool = false
var hit_stun_time_remaining: float = 0.0
var is_defeated: bool = false
var attack_sequence_id: int = 0
var controls_enabled: bool = true


func _ready() -> void:
	current_health = max_health


func _physics_process(delta: float) -> void:
	if is_defeated:
		if is_in_hit_stun:
			_update_hit_stun(delta)
		else:
			velocity.x = 0.0
	elif is_in_hit_stun:
		_update_hit_stun(delta)
	elif controls_enabled:
		_handle_control_input(delta)
	else:
		velocity.x = 0.0

	if not is_on_floor():
		velocity += get_gravity() * delta

	move_and_slide()
	_resolve_grounded_spacing(delta)
	_face_opponent()


func _handle_control_input(delta: float) -> void:
	if control_mode == ControlMode.CPU:
		_handle_cpu_input(delta)
	else:
		_apply_control_input(
			Input.get_axis(left_action, right_action),
			Input.is_action_just_pressed(jump_action),
			Input.is_action_just_pressed(punch_action)
		)


func _handle_cpu_input(delta: float) -> void:
	if not is_instance_valid(opponent):
		_apply_control_input(0.0, false, false)
		return

	var horizontal_distance: float = opponent.global_position.x - global_position.x
	var opponent_fighter: Fighter = opponent as Fighter
	var opponent_near_wall: bool = (
		opponent_fighter != null
		and opponent_fighter.is_near_world_wall(cpu_controller.corner_check_distance)
	)
	cpu_controller.update_decision(
		delta,
		horizontal_distance,
		not is_punching,
		opponent_near_wall
	)
	_apply_control_input(
		cpu_controller.move_direction,
		false,
		cpu_controller.consume_punch_request()
	)


func _apply_control_input(move_direction: float, jump_requested: bool, punch_requested: bool) -> void:
	velocity.x = move_direction * move_speed

	if is_on_floor() and jump_requested:
		velocity.y = -jump_velocity

	if punch_requested and not is_punching:
		_start_punch()


func _update_hit_stun(delta: float) -> void:
	hit_stun_time_remaining = maxf(hit_stun_time_remaining - delta, 0.0)
	if is_zero_approx(hit_stun_time_remaining):
		is_in_hit_stun = false


func _face_opponent() -> void:
	if is_instance_valid(opponent) and not is_equal_approx(global_position.x, opponent.global_position.x):
		visuals.scale.x = signf(opponent.global_position.x - global_position.x)


func is_near_world_wall(check_distance: float) -> bool:
	return (
		test_move(global_transform, Vector2.LEFT * check_distance)
		or test_move(global_transform, Vector2.RIGHT * check_distance)
	)


func _resolve_grounded_spacing(delta: float) -> void:
	var opponent_fighter: Fighter = opponent as Fighter
	if opponent_fighter == null or not is_on_floor() or not opponent_fighter.is_on_floor():
		return
	if get_instance_id() > opponent_fighter.get_instance_id():
		return

	var horizontal_offset: float = opponent_fighter.global_position.x - global_position.x
	var overlap: float = minimum_fighter_spacing - absf(horizontal_offset)
	if overlap <= 0.0:
		return

	var separation_direction: float = signf(horizontal_offset)
	if is_zero_approx(separation_direction):
		separation_direction = 1.0
	var correction: float = minf(overlap, separation_speed * delta)

	var original_position: Vector2 = global_position
	move_and_collide(Vector2.LEFT * separation_direction * correction * 0.5)
	var self_distance_moved: float = absf(global_position.x - original_position.x)

	var opponent_original_position: Vector2 = opponent_fighter.global_position
	opponent_fighter.move_and_collide(
		Vector2.RIGHT * separation_direction * (correction - self_distance_moved)
	)
	var opponent_distance_moved: float = absf(
		opponent_fighter.global_position.x - opponent_original_position.x
	)

	var remaining_correction: float = correction - self_distance_moved - opponent_distance_moved
	if remaining_correction > 0.0:
		move_and_collide(Vector2.LEFT * separation_direction * remaining_correction)


func _start_punch() -> void:
	is_punching = true
	hit_target_ids.clear()
	attack_sequence_id += 1
	var current_attack_id: int = attack_sequence_id
	await get_tree().create_timer(punch_startup_time).timeout
	if current_attack_id != attack_sequence_id or is_defeated:
		return

	punch_is_active = true
	punch_hit_box.set_deferred("monitoring", true)
	await get_tree().create_timer(punch_active_time).timeout
	if current_attack_id != attack_sequence_id:
		return

	punch_is_active = false
	punch_hit_box.set_deferred("monitoring", false)
	await get_tree().create_timer(punch_recovery_time).timeout
	if current_attack_id != attack_sequence_id:
		return
	is_punching = false


func _on_punch_hit_box_area_entered(hurt_box: Area2D) -> void:
	if not punch_is_active:
		return

	var target: Fighter = hurt_box.get_parent() as Fighter
	if target == null or target == self or hit_target_ids.has(target.get_instance_id()):
		return

	hit_target_ids[target.get_instance_id()] = true
	target.receive_hit(punch_damage, punch_knockback_speed, self)


func receive_hit(damage: int, knockback_speed: float, attacker: Fighter) -> void:
	if is_defeated:
		return

	var previous_health: int = current_health
	current_health = clampi(current_health - damage, 0, max_health)
	health_changed.emit(current_health, max_health)

	var knockback_direction: float = signf(global_position.x - attacker.global_position.x)
	velocity.x = knockback_direction * knockback_speed
	is_in_hit_stun = true
	hit_stun_time_remaining = hit_stun_duration
	if control_mode == ControlMode.CPU:
		cpu_controller.stop()

	var damage_dealt: int = previous_health - current_health
	print("PUNCH HIT: %s hit %s for %d damage (%d health remaining)" % [
		attacker.name,
		name,
		damage_dealt,
		current_health,
	])

	if current_health == 0:
		is_defeated = true
		_cancel_attack()
		defeated.emit(self)


func reset_for_round(spawn_position: Vector2) -> void:
	position = spawn_position
	velocity = Vector2.ZERO
	current_health = max_health
	is_defeated = false
	is_in_hit_stun = false
	hit_stun_time_remaining = 0.0
	_cancel_attack()
	cpu_controller.reset_for_round()
	health_changed.emit(current_health, max_health)


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled:
		cpu_controller.stop()
		_cancel_attack()


func _cancel_attack() -> void:
	attack_sequence_id += 1
	is_punching = false
	punch_is_active = false
	hit_target_ids.clear()
	punch_hit_box.set_deferred("monitoring", false)
