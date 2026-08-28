extends Area2D
class_name SpecialProjectile

var source_fighter: Fighter
var direction: float = 1.0
var speed: float = 0.0
var max_distance: float = 0.0
var lifetime_remaining: float = 0.0
var start_position: Vector2
var damage: int = 0
var knockback: float = 0.0
var hit_stun_duration: float = 0.25
var block_stun_duration: float = 0.16
var attack_level: Fighter.AttackLevel = Fighter.AttackLevel.MID
var attack_title: String = "Special Move"
var has_hit: bool = false

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var visual: Polygon2D = $Visual


func configure(attacker: Fighter, special_move: SpecialMoveData, travel_direction: float) -> void:
	source_fighter = attacker
	direction = signf(travel_direction) if not is_zero_approx(travel_direction) else 1.0
	speed = maxf(special_move.projectile_speed, 0.0)
	max_distance = maxf(special_move.projectile_max_distance, 0.0)
	lifetime_remaining = maxf(special_move.projectile_lifetime, 0.01)
	start_position = global_position
	var base_damage: int = (
		special_move.projectile_damage
		if special_move.projectile_damage > 0
		else special_move.damage
	)
	damage = attacker.get_scaled_damage(base_damage)
	knockback = special_move.knockback
	hit_stun_duration = special_move.hit_stun_duration
	block_stun_duration = special_move.block_stun_duration
	attack_level = (
		Fighter.AttackLevel.LOW
		if special_move.attack_level == SpecialMoveData.AttackLevel.LOW
		else Fighter.AttackLevel.MID
	)
	attack_title = special_move.display_title
	collision_shape.shape = collision_shape.shape.duplicate()
	var rectangle: RectangleShape2D = collision_shape.shape as RectangleShape2D
	if rectangle != null:
		rectangle.size = special_move.projectile_size
	_configure_visual(special_move)
	monitoring = true


func _configure_visual(special_move: SpecialMoveData) -> void:
	var visual_size: Vector2 = (
		special_move.projectile_visual_size
		if special_move.projectile_visual_size.x > 0.0 and special_move.projectile_visual_size.y > 0.0
		else special_move.projectile_size
	)
	var half_size: Vector2 = visual_size * 0.5
	visual.polygon = PackedVector2Array([
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y),
	])
	if special_move.projectile_texture != null:
		visual.texture = special_move.projectile_texture
		visual.color = Color.WHITE
		var texture_size: Vector2 = special_move.projectile_texture.get_size()
		visual.uv = PackedVector2Array([
			Vector2.ZERO,
			Vector2(texture_size.x, 0.0),
			texture_size,
			Vector2(0.0, texture_size.y),
		])
	else:
		visual.texture = null
		visual.color = special_move.projectile_color
		visual.uv = PackedVector2Array()
	visual.scale.x = direction


func _physics_process(delta: float) -> void:
	if not is_instance_valid(source_fighter):
		queue_free()
		return
	lifetime_remaining -= delta
	global_position.x += direction * speed * delta
	if lifetime_remaining <= 0.0 or global_position.distance_to(start_position) >= max_distance:
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	if has_hit:
		return
	var target: Fighter = area.get_parent() as Fighter
	if target == null or target == source_fighter:
		return
	has_hit = true
	set_deferred("monitoring", false)
	target.receive_hit(
		damage,
		knockback,
		source_fighter,
		attack_title,
		attack_level,
		hit_stun_duration,
		block_stun_duration
	)
	queue_free()
