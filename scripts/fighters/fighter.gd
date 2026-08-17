extends CharacterBody2D
class_name Fighter

class NormalAttackData:
	extends RefCounted
	var attack_id: StringName
	var display_name: String
	var damage: int
	var startup_time: float
	var active_time: float
	var recovery_time: float
	var knockback: float
	var hitbox_size: Vector2
	var hitbox_offset_x: float
	var animation_name: StringName
	var grounded_only: bool

signal health_changed(current_health: int, max_health: int)
signal defeated(fighter: Fighter)
signal special_move_started(move_name: String)

enum ControlMode {
	HUMAN,
	CPU,
}

const ANIMATION_IDLE: StringName = &"idle"
const ANIMATION_WALK: StringName = &"walk"
const ANIMATION_JUMP: StringName = &"jump"
const ANIMATION_CROUCH: StringName = &"crouch"
const ANIMATION_PUNCH: StringName = &"punch"
const ANIMATION_KICK: StringName = &"kick"
const ANIMATION_HURT: StringName = &"hurt"
const ANIMATION_SPECIAL_1: StringName = &"special_1"
const ANIMATION_SPECIAL_2: StringName = &"special_2"
const ANIMATION_KO: StringName = &"ko"

@export var move_speed: float = 240.0
@export var jump_velocity: float = 600.0
@export var minimum_fighter_spacing: float = 56.0
@export var separation_speed: float = 160.0
@export var max_health: int = 100
@export var hit_stun_duration: float = 0.25
@export var character_data: CharacterData
@export var control_mode: ControlMode = ControlMode.HUMAN
@export var left_action: StringName = &"p1_left"
@export var right_action: StringName = &"p1_right"
@export var jump_action: StringName = &"p1_jump"
@export var crouch_action: StringName = &"p1_crouch"
@export var punch_action: StringName = &"p1_punch"
@export var kick_action: StringName = &"p1_kick"
@export var special_1_action: StringName = &"p1_special_1"
@export var special_2_action: StringName = &"p1_special_2"
@export var opponent: Node2D
@export var punch_damage: int = 10
@export var punch_knockback_speed: float = 300.0
@export var punch_startup_time: float = 0.12
@export var punch_active_time: float = 0.10
@export var punch_recovery_time: float = 0.20
@export var kick_damage: int = 14
@export var kick_knockback_speed: float = 340.0
@export var kick_startup_time: float = 0.16
@export var kick_active_time: float = 0.12
@export var kick_recovery_time: float = 0.28
@export var kick_hitbox_width: float = 64.0
@export var kick_hitbox_height: float = 40.0
@export var kick_hitbox_offset_x: float = 58.0
@export var crouch_hurtbox_height: float = 72.0

@onready var visuals: Node2D = $Visuals
@onready var animated_sprite: AnimatedSprite2D = $Visuals/AnimatedSprite2D
@onready var fallback_visuals: Node2D = $Visuals/FallbackVisuals
@onready var punch_hit_box: Area2D = $Visuals/PunchHitBox
@onready var punch_hit_box_shape: CollisionShape2D = $Visuals/PunchHitBox/CollisionShape2D
@onready var hurt_box_shape: CollisionShape2D = $HurtBox/CollisionShape2D
@onready var cpu_controller: CPUController = $CPUController

var is_attacking: bool = false
var attack_is_active: bool = false
var hit_target_ids: Dictionary = {}
var current_health: int
var is_in_hit_stun: bool = false
var hit_stun_time_remaining: float = 0.0
var is_defeated: bool = false
var attack_sequence_id: int = 0
var controls_enabled: bool = true
var active_attack_damage: int = 0
var active_attack_knockback: float = 0.0
var active_attack_name: String = "Punch"
var active_attack_animation: StringName = ANIMATION_PUNCH
var default_hitbox_size: Vector2
var default_hitbox_position: Vector2
var facing_direction: float = 1.0
var missing_animation_warnings: Dictionary = {}
var punch_attack: NormalAttackData
var kick_attack: NormalAttackData
var is_crouching: bool = false
var standing_hurtbox_size: Vector2
var standing_hurtbox_position: Vector2


func _ready() -> void:
	current_health = max_health
	punch_hit_box_shape.shape = punch_hit_box_shape.shape.duplicate()
	var hitbox_rectangle: RectangleShape2D = punch_hit_box_shape.shape as RectangleShape2D
	default_hitbox_size = hitbox_rectangle.size
	default_hitbox_position = punch_hit_box.position
	hurt_box_shape.shape = hurt_box_shape.shape.duplicate()
	var hurtbox_rectangle: RectangleShape2D = hurt_box_shape.shape as RectangleShape2D
	standing_hurtbox_size = hurtbox_rectangle.size
	standing_hurtbox_position = hurt_box_shape.position
	_configure_normal_attacks()
	_configure_character_visual()
	_update_animation()


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
	_update_animation()


func _handle_control_input(delta: float) -> void:
	if control_mode == ControlMode.CPU:
		_handle_cpu_input(delta)
	else:
		_apply_control_input(
			Input.get_axis(left_action, right_action),
			Input.is_action_just_pressed(jump_action),
			Input.is_action_pressed(crouch_action),
			Input.is_action_just_pressed(punch_action),
			Input.is_action_just_pressed(kick_action),
			Input.is_action_just_pressed(special_1_action),
			Input.is_action_just_pressed(special_2_action)
		)


func _handle_cpu_input(delta: float) -> void:
	if not is_instance_valid(opponent):
		_apply_control_input(0.0, false, false, false, false, false, false)
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
		not is_attacking,
		opponent_near_wall
	)
	_apply_control_input(
		cpu_controller.move_direction,
		false,
		false,
		cpu_controller.consume_punch_request(),
		false,
		false,
		false
	)


func _apply_control_input(
	move_direction: float,
	jump_requested: bool,
	crouch_held: bool,
	punch_requested: bool,
	kick_requested: bool,
	special_1_requested: bool,
	special_2_requested: bool
) -> void:
	if not is_attacking:
		_set_crouching(crouch_held and is_on_floor() and controls_enabled)
	if is_crouching:
		velocity.x = 0.0
		return

	velocity.x = move_direction * get_move_speed()

	if is_on_floor() and jump_requested:
		velocity.y = -get_jump_velocity()

	if is_attacking:
		return
	if punch_requested:
		_start_punch()
	elif kick_requested:
		_start_kick()
	elif special_1_requested:
		_start_special(get_special_move(1), ANIMATION_SPECIAL_1)
	elif special_2_requested:
		_start_special(get_special_move(2), ANIMATION_SPECIAL_2)


func _update_hit_stun(delta: float) -> void:
	hit_stun_time_remaining = maxf(hit_stun_time_remaining - delta, 0.0)
	if is_zero_approx(hit_stun_time_remaining):
		is_in_hit_stun = false


func _face_opponent() -> void:
	if is_instance_valid(opponent) and not is_equal_approx(global_position.x, opponent.global_position.x):
		facing_direction = signf(opponent.global_position.x - global_position.x)
	animated_sprite.flip_h = facing_direction < 0.0
	fallback_visuals.scale.x = facing_direction
	punch_hit_box.position.x = absf(punch_hit_box.position.x) * facing_direction


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


func _configure_normal_attacks() -> void:
	punch_attack = _create_normal_attack(
		&"punch",
		"Punch",
		punch_damage,
		punch_startup_time,
		punch_active_time,
		punch_recovery_time,
		punch_knockback_speed,
		default_hitbox_size,
		default_hitbox_position.x,
		ANIMATION_PUNCH,
		false
	)
	kick_attack = _create_normal_attack(
		&"kick",
		"Kick",
		kick_damage,
		kick_startup_time,
		kick_active_time,
		kick_recovery_time,
		kick_knockback_speed,
		Vector2(kick_hitbox_width, kick_hitbox_height),
		kick_hitbox_offset_x,
		ANIMATION_KICK,
		false
	)


func _create_normal_attack(
	attack_id: StringName,
	display_name: String,
	damage: int,
	startup_time: float,
	active_time: float,
	recovery_time: float,
	knockback: float,
	hitbox_size: Vector2,
	hitbox_offset_x: float,
	animation_name: StringName,
	grounded_only: bool
) -> NormalAttackData:
	var attack := NormalAttackData.new()
	attack.attack_id = attack_id
	attack.display_name = display_name
	attack.damage = damage
	attack.startup_time = startup_time
	attack.active_time = active_time
	attack.recovery_time = recovery_time
	attack.knockback = knockback
	attack.hitbox_size = hitbox_size
	attack.hitbox_offset_x = hitbox_offset_x
	attack.animation_name = animation_name
	attack.grounded_only = grounded_only
	return attack


func _start_punch() -> void:
	_start_normal_attack(punch_attack)


func _start_kick() -> void:
	_start_normal_attack(kick_attack)


func _start_normal_attack(attack: NormalAttackData) -> void:
	if attack == null or not _can_start_attack():
		return
	if attack.grounded_only and not is_on_floor():
		return
	_start_attack(
		attack.display_name,
		attack.damage,
		attack.knockback,
		attack.startup_time,
		attack.active_time,
		attack.recovery_time,
		attack.hitbox_size,
		attack.hitbox_offset_x,
		attack.animation_name
	)


func _start_special(
	special_move: SpecialMoveData,
	animation_name: StringName = ANIMATION_SPECIAL_1
) -> void:
	if special_move == null or not _can_start_attack():
		return
	special_move_started.emit(special_move.display_name)
	_start_attack(
		special_move.display_name,
		special_move.damage,
		special_move.knockback,
		special_move.startup_time,
		special_move.active_time,
		special_move.recovery_time,
		Vector2(special_move.hitbox_width, special_move.hitbox_height),
		special_move.hitbox_offset_x,
		animation_name
	)


func _can_start_attack() -> bool:
	return (
		controls_enabled
		and not is_defeated
		and not is_in_hit_stun
		and not is_attacking
		and not is_crouching
	)


func _start_attack(
	attack_name: String,
	base_damage: int,
	knockback_speed: float,
	startup_time: float,
	active_time: float,
	recovery_time: float,
	hitbox_size: Vector2,
	hitbox_offset_x: float,
	animation_name: StringName
) -> void:
	is_attacking = true
	hit_target_ids.clear()
	active_attack_name = attack_name
	active_attack_damage = get_scaled_damage(base_damage)
	active_attack_knockback = knockback_speed
	active_attack_animation = animation_name
	_configure_attack_hitbox(hitbox_size, hitbox_offset_x)
	_update_animation()
	attack_sequence_id += 1
	var current_attack_id: int = attack_sequence_id
	await get_tree().create_timer(startup_time).timeout
	if current_attack_id != attack_sequence_id or is_defeated:
		return

	attack_is_active = true
	punch_hit_box.set_deferred("monitoring", true)
	await get_tree().create_timer(active_time).timeout
	if current_attack_id != attack_sequence_id:
		return

	attack_is_active = false
	punch_hit_box.set_deferred("monitoring", false)
	await get_tree().create_timer(recovery_time).timeout
	if current_attack_id != attack_sequence_id:
		return
	is_attacking = false
	_restore_default_attack_hitbox()
	_update_animation()


func _on_punch_hit_box_area_entered(hurt_box: Area2D) -> void:
	if not attack_is_active:
		return

	var target: Fighter = hurt_box.get_parent() as Fighter
	if target == null or target == self or hit_target_ids.has(target.get_instance_id()):
		return

	hit_target_ids[target.get_instance_id()] = true
	target.receive_hit(
		active_attack_damage,
		active_attack_knockback,
		self,
		active_attack_name
	)


func receive_hit(
	damage: int,
	knockback_speed: float,
	attacker: Fighter,
	attack_name: String = "Punch"
) -> void:
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
	if attack_name == "Punch":
		print("PUNCH HIT: %s hit %s for %d damage (%d health remaining)" % [
			attacker.get_display_name(),
			get_display_name(),
			damage_dealt,
			current_health,
		])
	elif attack_name == "Kick":
		print("KICK HIT: %s hit %s for %d damage (%d health remaining)" % [
			attacker.get_display_name(),
			get_display_name(),
			damage_dealt,
			current_health,
		])
	else:
		print("SPECIAL HIT: %s used %s on %s for %d damage (%d health remaining)" % [
			attacker.get_display_name(),
			attack_name,
			get_display_name(),
			damage_dealt,
			current_health,
		])

	if current_health == 0:
		is_defeated = true
		_cancel_attack()
		defeated.emit(self)
	else:
		_update_animation()


func reset_for_round(spawn_position: Vector2) -> void:
	position = spawn_position
	velocity = Vector2.ZERO
	current_health = max_health
	is_defeated = false
	is_in_hit_stun = false
	hit_stun_time_remaining = 0.0
	_set_crouching(false)
	_cancel_attack()
	cpu_controller.reset_for_round()
	health_changed.emit(current_health, max_health)


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled:
		_set_crouching(false)
		cpu_controller.stop()
		_cancel_attack()


func get_display_name() -> String:
	if character_data != null and not character_data.display_name.is_empty():
		return character_data.display_name
	return name


func get_move_speed() -> float:
	return character_data.move_speed if character_data != null else move_speed


func get_jump_velocity() -> float:
	return character_data.jump_velocity if character_data != null else jump_velocity


func get_punch_damage() -> int:
	return get_scaled_damage(punch_damage)


func get_kick_damage() -> int:
	return get_scaled_damage(kick_damage)


func get_special_move(slot: int) -> SpecialMoveData:
	if character_data == null:
		return null
	return character_data.special_move_1 if slot == 1 else character_data.special_move_2


func get_scaled_damage(base_damage: int) -> int:
	var power_multiplier: float = character_data.power_multiplier if character_data != null else 1.0
	return maxi(roundi(float(base_damage) * power_multiplier), 0)


func _configure_attack_hitbox(hitbox_size: Vector2, hitbox_offset_x: float) -> void:
	var hitbox_rectangle: RectangleShape2D = punch_hit_box_shape.shape as RectangleShape2D
	hitbox_rectangle.size = hitbox_size
	punch_hit_box.position = Vector2(
		absf(hitbox_offset_x) * facing_direction,
		default_hitbox_position.y
	)


func _restore_default_attack_hitbox() -> void:
	_configure_attack_hitbox(default_hitbox_size, default_hitbox_position.x)


func _configure_character_visual() -> void:
	if character_data != null and character_data.sprite_frames != null:
		animated_sprite.sprite_frames = character_data.sprite_frames
		animated_sprite.show()
		fallback_visuals.hide()
		return

	animated_sprite.hide()
	fallback_visuals.show()
	push_warning("%s has no character SpriteFrames; using the fallback visual." % name)


func _set_crouching(crouching: bool) -> void:
	if is_crouching == crouching:
		return
	is_crouching = crouching

	var hurtbox_rectangle: RectangleShape2D = hurt_box_shape.shape as RectangleShape2D
	if is_crouching:
		var crouching_height: float = clampf(
			crouch_hurtbox_height,
			1.0,
			standing_hurtbox_size.y
		)
		hurtbox_rectangle.size = Vector2(standing_hurtbox_size.x, crouching_height)
		hurt_box_shape.position = standing_hurtbox_position + Vector2(
			0.0,
			(standing_hurtbox_size.y - crouching_height) * 0.5
		)
	else:
		hurtbox_rectangle.size = standing_hurtbox_size
		hurt_box_shape.position = standing_hurtbox_position
	_update_animation()


func _update_animation() -> void:
	if is_defeated:
		_play_animation_if_available(ANIMATION_KO)
	elif is_in_hit_stun:
		_play_animation_if_available(ANIMATION_HURT)
	elif is_attacking:
		_play_animation_if_available(active_attack_animation)
	elif not is_on_floor():
		_play_animation_if_available(ANIMATION_JUMP)
	elif is_crouching:
		_play_animation_if_available(ANIMATION_CROUCH)
	elif not is_zero_approx(velocity.x):
		_play_animation_if_available(ANIMATION_WALK)
	else:
		_play_animation_if_available(ANIMATION_IDLE)


func _play_animation_if_available(animation_name: StringName) -> void:
	if not animated_sprite.visible or animated_sprite.sprite_frames == null:
		return

	var selected_animation: StringName = animation_name
	if not animated_sprite.sprite_frames.has_animation(selected_animation):
		if not missing_animation_warnings.has(animation_name):
			missing_animation_warnings[animation_name] = true
			push_warning("%s is missing animation '%s'; falling back to idle." % [
				get_display_name(),
				animation_name,
			])
		selected_animation = ANIMATION_IDLE

	if not animated_sprite.sprite_frames.has_animation(selected_animation):
		animated_sprite.stop()
		return
	if animated_sprite.animation != selected_animation:
		animated_sprite.play(selected_animation)


func _cancel_attack() -> void:
	attack_sequence_id += 1
	is_attacking = false
	attack_is_active = false
	hit_target_ids.clear()
	punch_hit_box.set_deferred("monitoring", false)
	_restore_default_attack_hitbox()
	_update_animation()
