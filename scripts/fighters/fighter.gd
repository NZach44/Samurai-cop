extends CharacterBody2D
class_name Fighter

@export var move_speed: float = 240.0
@export var jump_velocity: float = 600.0
@export var max_health: int = 100
@export var hit_stun_duration: float = 0.25
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

var is_punching: bool = false
var punch_is_active: bool = false
var hit_target_ids: Dictionary = {}
var current_health: int
var is_in_hit_stun: bool = false
var hit_stun_time_remaining: float = 0.0


func _ready() -> void:
	current_health = max_health


func _physics_process(delta: float) -> void:
	if is_in_hit_stun:
		_update_hit_stun(delta)
	else:
		_handle_player_input()

	if not is_on_floor():
		velocity += get_gravity() * delta

	move_and_slide()
	_face_opponent()


func _handle_player_input() -> void:
	var move_direction: float = Input.get_axis(left_action, right_action)
	velocity.x = move_direction * move_speed

	if is_on_floor() and Input.is_action_just_pressed(jump_action):
		velocity.y = -jump_velocity

	if Input.is_action_just_pressed(punch_action) and not is_punching:
		_start_punch()


func _update_hit_stun(delta: float) -> void:
	hit_stun_time_remaining = maxf(hit_stun_time_remaining - delta, 0.0)
	if is_zero_approx(hit_stun_time_remaining):
		is_in_hit_stun = false


func _face_opponent() -> void:
	if is_instance_valid(opponent) and not is_equal_approx(global_position.x, opponent.global_position.x):
		visuals.scale.x = signf(opponent.global_position.x - global_position.x)


func _start_punch() -> void:
	is_punching = true
	hit_target_ids.clear()
	await get_tree().create_timer(punch_startup_time).timeout

	punch_is_active = true
	punch_hit_box.set_deferred("monitoring", true)
	await get_tree().create_timer(punch_active_time).timeout

	punch_is_active = false
	punch_hit_box.set_deferred("monitoring", false)
	await get_tree().create_timer(punch_recovery_time).timeout
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
	var previous_health: int = current_health
	current_health = clampi(current_health - damage, 0, max_health)

	var knockback_direction: float = signf(global_position.x - attacker.global_position.x)
	velocity.x = knockback_direction * knockback_speed
	is_in_hit_stun = true
	hit_stun_time_remaining = hit_stun_duration

	var damage_dealt: int = previous_health - current_health
	print("PUNCH HIT: %s hit %s for %d damage (%d health remaining)" % [
		attacker.name,
		name,
		damage_dealt,
		current_health,
	])
