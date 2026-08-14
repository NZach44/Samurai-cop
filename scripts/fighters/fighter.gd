extends CharacterBody2D

@export var move_speed: float = 240.0
@export var jump_velocity: float = 600.0
@export var left_action: StringName = &"p1_left"
@export var right_action: StringName = &"p1_right"
@export var jump_action: StringName = &"p1_jump"
@export var punch_action: StringName = &"p1_punch"
@export var opponent: Node2D
@export var punch_startup_time: float = 0.12
@export var punch_active_time: float = 0.10
@export var punch_recovery_time: float = 0.20

@onready var visuals: Node2D = $Visuals
@onready var punch_hit_box: Area2D = $Visuals/PunchHitBox

var is_punching: bool = false
var punch_is_active: bool = false
var hit_target_ids: Dictionary = {}


func _physics_process(delta: float) -> void:
	var move_direction: float = Input.get_axis(left_action, right_action)
	velocity.x = move_direction * move_speed

	if not is_on_floor():
		velocity += get_gravity() * delta
	elif Input.is_action_just_pressed(jump_action):
		velocity.y = -jump_velocity

	if Input.is_action_just_pressed(punch_action) and not is_punching:
		_start_punch()

	move_and_slide()
	_face_opponent()


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

	var target: Node = hurt_box.get_parent()
	if target == self or hit_target_ids.has(target.get_instance_id()):
		return

	hit_target_ids[target.get_instance_id()] = true
	print("PUNCH HIT: %s hit %s" % [name, target.name])
