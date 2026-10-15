extends SceneTree

const FIGHTER_SCENE: PackedScene = preload("res://scenes/fighters/fighter.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/special_projectile.tscn")
const JENNIFER: CharacterData = preload("res://data/fighters/jennifer.tres")
const JOE: CharacterData = preload("res://data/fighters/joe_marshall.tres")
const FRANK: CharacterData = preload("res://data/fighters/frank_washington.tres")
const YAMASHITA: CharacterData = preload("res://data/fighters/yamashita.tres")
const FUJIYAMA: CharacterData = preload("res://data/fighters/fujiyama.tres")
const OKAMURA: CharacterData = preload("res://data/fighters/okamura.tres")
const BIRTHDAY: SpecialMoveData = preload("res://data/moves/jennifer_special_1.tres")
const LION_HEAD: SpecialMoveData = preload("res://data/moves/jennifer_special_2.tres")

var failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var jennifer: Fighter = FIGHTER_SCENE.instantiate() as Fighter
	var target: Fighter = FIGHTER_SCENE.instantiate() as Fighter
	jennifer.character_data = JENNIFER
	target.character_data = JOE
	world.add_child(jennifer)
	world.add_child(target)
	target.process_mode = Node.PROCESS_MODE_DISABLED

	_test_complete_visual_contract(jennifer)
	_test_move_contracts()
	await _test_release_timing(jennifer, BIRTHDAY, 1, 0.18, 2, 0.10, 3)
	await _wait_for_recovery(jennifer, BIRTHDAY)
	await _test_release_timing(jennifer, LION_HEAD, 2, 0.27, 3, 0.10, 4)
	await _wait_for_recovery(jennifer, LION_HEAD)
	_test_projectile(jennifer, target, BIRTHDAY, Vector2(0.625, 0.625))
	_test_projectile(jennifer, target, LION_HEAD, Vector2(0.5625, 0.5625))
	_test_fallback(jennifer)

	if failures.is_empty():
		print("PASS Jennifer production sprites, runtime scale, both specials, and generic fallback")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _test_complete_visual_contract(fighter: Fighter) -> void:
	var expected := {
		&"idle": 4, &"walk": 6, &"punch": 5, &"kick": 6,
		&"crouch": 3, &"crouch_punch": 5, &"crouch_kick": 6,
		&"block": 3, &"crouch_block": 3, &"jump": 5, &"hurt": 3,
		&"special_1": 8, &"special_2": 8, &"ko": 8,
	}
	_check(JENNIFER.sprite_frames.get_animation_names().size() == 14, "Jennifer must have exactly 14 animations")
	var total := 0
	for animation: StringName in expected:
		_check(JENNIFER.sprite_frames.has_animation(animation), "missing Jennifer animation %s" % animation)
		var count := JENNIFER.sprite_frames.get_frame_count(animation)
		_check(count == expected[animation], "unexpected Jennifer frame count for %s: %d" % [animation, count])
		total += count
		for index in range(count):
			var texture := JENNIFER.sprite_frames.get_frame_texture(animation, index)
			_check(texture != null, "Jennifer %s frame %d is null" % [animation, index + 1])
			if texture != null:
				_check(not texture is AtlasTexture, "Jennifer %s frame %d is still placeholder AtlasTexture" % [animation, index + 1])
				_check(texture.get_size() == Vector2(128.0, 128.0), "Jennifer %s frame %d import is not 128x128" % [animation, index + 1])
	_check(total == 73, "Jennifer must have exactly 73 production frames")
	_check(is_equal_approx(JENNIFER.visual_scale, 1.6), "Jennifer visual_scale changed")
	_check(fighter.sprite_root.scale.is_equal_approx(Vector2.ONE * 1.6), "Jennifer SpriteRoot scale is not uniformly 1.6")
	var height := _idle_height(JENNIFER)
	var references := [JOE, FRANK, YAMASHITA, FUJIYAMA, OKAMURA]
	var total_reference := 0.0
	for character: CharacterData in references:
		total_reference += _idle_height(character)
	var mean_reference := total_reference / references.size()
	print("RUNTIME IDLE HEIGHTS Jennifer=%.2f roster_mean=%.2f" % [height, mean_reference])
	_check(absf(height / mean_reference - 1.0) <= 0.075, "Jennifer runtime height differs from roster mean by more than 7.5%")
	var opponent := Node2D.new()
	root.add_child(opponent)
	fighter.global_position = Vector2.ZERO
	opponent.global_position = Vector2(100.0, 0.0)
	fighter.opponent = opponent
	fighter._face_opponent()
	_check(not fighter.animated_sprite.flip_h, "Jennifer right-facing sprite flipped")
	opponent.global_position.x = -100.0
	fighter._face_opponent()
	_check(fighter.animated_sprite.flip_h, "Jennifer left-facing sprite did not flip")
	fighter.opponent = null
	opponent.queue_free()


func _idle_height(character: CharacterData) -> float:
	var texture := character.sprite_frames.get_frame_texture(&"idle", 0)
	return texture.get_image().get_used_rect().size.y * character.visual_scale


func _test_move_contracts() -> void:
	_check(BIRTHDAY.special_id == &"jennifer_birthday", "Birthday special id changed")
	_check(BIRTHDAY.display_title == "Happy Birthday To Me", "Birthday title changed")
	_check(BIRTHDAY.behavior == SpecialMoveData.SpecialBehavior.PROJECTILE, "Birthday behavior changed")
	_check(BIRTHDAY.projectile_texture != null, "Birthday cake texture missing")
	_check(BIRTHDAY.projectile_texture.resource_path.ends_with("birthday_cake.png"), "Birthday special has wrong texture")
	_check(BIRTHDAY.projectile_visual_size == Vector2(60.0, 60.0), "Birthday visual size changed")
	_check(is_equal_approx(BIRTHDAY.startup_time, 0.24) and is_equal_approx(BIRTHDAY.recovery_time, 0.32), "Birthday timing changed")
	_check(BIRTHDAY.projectile_speed == 340.0 and BIRTHDAY.projectile_max_distance == 420.0, "Birthday tuning changed")
	_check(is_equal_approx(BIRTHDAY.projectile_lifetime, 2.2), "Birthday lifetime changed")
	_check(BIRTHDAY.projectile_damage == 13 and BIRTHDAY.projectile_size == Vector2(42.0, 28.0), "Birthday damage/collision changed")
	_check(LION_HEAD.special_id == &"jennifer_lion_head", "Lion special id changed")
	_check(LION_HEAD.display_title == "Summon Lion Head", "Lion title changed")
	_check(LION_HEAD.behavior == SpecialMoveData.SpecialBehavior.PROJECTILE, "Lion behavior changed")
	_check(LION_HEAD.projectile_texture != null, "Lion texture missing")
	_check(LION_HEAD.projectile_texture.resource_path.ends_with("lion_head.png"), "Lion special has wrong texture")
	_check(LION_HEAD.projectile_texture != BIRTHDAY.projectile_texture, "Jennifer projectile textures were swapped/shared")
	_check(LION_HEAD.projectile_visual_size == Vector2(72.0, 72.0), "Lion visual size changed")
	_check(is_equal_approx(LION_HEAD.startup_time, 0.32) and is_equal_approx(LION_HEAD.recovery_time, 0.4), "Lion timing changed")
	_check(LION_HEAD.projectile_speed == 300.0 and LION_HEAD.projectile_max_distance == 360.0, "Lion tuning changed")
	_check(is_equal_approx(LION_HEAD.projectile_lifetime, 2.2), "Lion lifetime changed")
	_check(LION_HEAD.projectile_damage == 17 and LION_HEAD.projectile_size == Vector2(46.0, 38.0), "Lion damage/collision changed")
	_check(LION_HEAD.projectile_speed < BIRTHDAY.projectile_speed, "Lion projectile must remain slower than cake")
	_check(LION_HEAD.projectile_max_distance < BIRTHDAY.projectile_max_distance, "Lion range must remain shorter than cake")
	_check(is_zero_approx(LION_HEAD.projectile_spin_speed), "Lion projectile must not spin")


func _test_release_timing(
	fighter: Fighter,
	move: SpecialMoveData,
	slot: int,
	pre_delay: float,
	pre_frame: int,
	post_delay: float,
	minimum_post_frame: int
) -> void:
	var before := get_nodes_in_group(&"special_projectiles").size()
	fighter.facing_direction = 1.0
	fighter.request_special(slot)
	await create_timer(pre_delay).timeout
	_check(get_nodes_in_group(&"special_projectiles").size() == before, "%s spawned too early" % move.display_title)
	_check(fighter.animated_sprite.animation == move.animation_name, "%s animation did not play" % move.display_title)
	_check(fighter.animated_sprite.frame == pre_frame, "%s pre-release frame mismatch" % move.display_title)
	await create_timer(post_delay).timeout
	var projectiles := get_nodes_in_group(&"special_projectiles")
	_check(projectiles.size() == before + 1, "%s must spawn exactly one projectile" % move.display_title)
	_check(fighter.animated_sprite.frame >= minimum_post_frame, "%s projectile spawned before visual handoff" % move.display_title)
	if projectiles.size() > before:
		projectiles[-1].queue_free()
	await process_frame


func _wait_for_recovery(fighter: Fighter, move: SpecialMoveData) -> void:
	await create_timer(move.active_time + move.recovery_time + 0.05).timeout
	_check(fighter.fighter_state == Fighter.FighterState.NORMAL, "%s did not recover" % move.display_title)


func _test_projectile(attacker: Fighter, target: Fighter, move: SpecialMoveData, expected_scale: Vector2) -> void:
	for direction in [1.0, -1.0]:
		var before := get_nodes_in_group(&"special_projectiles").size()
		attacker.facing_direction = direction
		attacker._spawn_special_projectile(move)
		var projectiles := get_nodes_in_group(&"special_projectiles")
		_check(projectiles.size() == before + 1, "%s did not spawn exactly once" % move.display_title)
		if projectiles.size() <= before:
			continue
		var projectile := projectiles[-1] as SpecialProjectile
		_check(projectile != null, "%s projectile has wrong type" % move.display_title)
		if projectile == null:
			continue
		var shape := projectile.collision_shape.shape as RectangleShape2D
		_check(shape != null and shape.size == move.projectile_size, "%s collision changed" % move.display_title)
		_check(projectile.projectile_visual.visible and not projectile.visual.visible, "%s textured visual/fallback state is wrong" % move.display_title)
		_check(projectile.projectile_visual.texture == move.projectile_texture, "%s runtime texture mismatch" % move.display_title)
		_check(projectile.projectile_visual.scale.is_equal_approx(expected_scale), "%s runtime visual scale mismatch" % move.display_title)
		_check(is_equal_approx(projectile.direction, direction), "%s direction mismatch" % move.display_title)
		var start_x := projectile.global_position.x
		var start_rotation := projectile.projectile_visual.rotation
		projectile._physics_process(0.1)
		_check(is_equal_approx(projectile.global_position.x - start_x, direction * move.projectile_speed * 0.1), "%s movement changed" % move.display_title)
		_check(is_equal_approx(projectile.projectile_visual.rotation, start_rotation), "%s unexpectedly spins" % move.display_title)
		if direction > 0.0:
			target.current_health = target.max_health
			var health_before := target.current_health
			projectile._on_area_entered(target.get_node("HurtBox") as Area2D)
			_check(health_before - target.current_health == attacker.get_scaled_damage(move.projectile_damage), "%s applied damage changed" % move.display_title)
		else:
			projectile.queue_free()


func _test_fallback(attacker: Fighter) -> void:
	var move := SpecialMoveData.new()
	move.projectile_size = Vector2(31.0, 17.0)
	move.projectile_color = Color(0.2, 0.4, 0.6, 1.0)
	var projectile := PROJECTILE_SCENE.instantiate() as SpecialProjectile
	root.add_child(projectile)
	projectile.configure(attacker, move, 1.0)
	_check(projectile.visual.visible, "textureless fallback is hidden")
	_check(projectile.visual.texture == null, "textureless fallback gained a texture")
	_check(not projectile.projectile_visual.visible, "textureless fallback shows Sprite2D")
	_check(projectile.visual.color.is_equal_approx(move.projectile_color), "textureless fallback color changed")
	var shape := projectile.collision_shape.shape as RectangleShape2D
	_check(shape != null and shape.size == move.projectile_size, "textureless fallback collision changed")
	projectile.queue_free()
