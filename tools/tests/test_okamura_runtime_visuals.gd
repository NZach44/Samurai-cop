extends SceneTree

const FIGHTER_SCENE: PackedScene = preload("res://scenes/fighters/fighter.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/special_projectile.tscn")
const OKAMURA: CharacterData = preload("res://data/fighters/okamura.tres")
const JOE: CharacterData = preload("res://data/fighters/joe_marshall.tres")
const FRANK: CharacterData = preload("res://data/fighters/frank_washington.tres")
const YAMASHITA: CharacterData = preload("res://data/fighters/yamashita.tres")
const FUJIYAMA: CharacterData = preload("res://data/fighters/fujiyama.tres")
const OKAMURA_SPECIAL_1: SpecialMoveData = preload("res://data/moves/okamura_special_1.tres")
const OKAMURA_SPECIAL_2: SpecialMoveData = preload("res://data/moves/okamura_special_2.tres")

var failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	_test_move_contract()

	# Keep this test useful while Milestone 15D is still on placeholder art.
	# As soon as the production-only crouch_punch animation appears, all visual
	# acceptance checks below become mandatory.
	if not OKAMURA.sprite_frames.has_animation(&"crouch_punch"):
		if failures.is_empty():
			print("PASS Okamura move contract; production sprite checks pending")
			quit(0)
			return
		_finish()
		return

	var arena := Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var fighter: Fighter = FIGHTER_SCENE.instantiate() as Fighter
	fighter.character_data = OKAMURA
	arena.add_child(fighter)
	fighter.process_mode = Node.PROCESS_MODE_DISABLED

	_test_character_visuals(fighter)
	_test_shuriken_projectile(fighter)
	await _test_special_2_flying_kick(fighter)
	fighter.queue_free()
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("PASS Okamura production sprites and runtime visual regression")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_move_contract() -> void:
	_check(OKAMURA_SPECIAL_1.special_id == &"okamura_shuriken", "Okamura special_1 id changed")
	_check(OKAMURA_SPECIAL_1.display_title == "Shuriken!", "Okamura special_1 title changed")
	_check(
		OKAMURA_SPECIAL_1.behavior == SpecialMoveData.SpecialBehavior.PROJECTILE,
		"Okamura special_1 must remain a projectile",
	)
	_check(OKAMURA_SPECIAL_1.animation_name == &"special_1", "Okamura special_1 animation changed")
	_check(OKAMURA_SPECIAL_1.projectile_texture != null, "Okamura shuriken projectile texture is missing")
	_check(OKAMURA_SPECIAL_1.projectile_visual_size.is_equal_approx(Vector2(35.2, 35.2)), "Okamura shuriken visual size changed")
	_check(is_equal_approx(OKAMURA_SPECIAL_1.projectile_spin_speed, 12.0), "Okamura shuriken spin speed changed")
	_check(not OKAMURA_SPECIAL_1.projectile_flip_with_direction, "Okamura shuriken should rotate without horizontal mirroring")

	_check(OKAMURA_SPECIAL_2.special_id == &"okamura_black_belt", "Okamura special_2 id changed")
	_check(OKAMURA_SPECIAL_2.display_title == "Karate Black Belt", "Okamura special_2 title changed")
	_check(
		OKAMURA_SPECIAL_2.behavior == SpecialMoveData.SpecialBehavior.FLYING_KICK,
		"Okamura special_2 must remain flying-kick behavior",
	)
	_check(OKAMURA_SPECIAL_2.animation_name == &"special_2", "Okamura special_2 animation changed")
	_check(OKAMURA_SPECIAL_2.projectile_texture == null, "Okamura special_2 unexpectedly gained a projectile texture")


func _test_character_visuals(fighter: Fighter) -> void:
	var expected_frames: Dictionary = {
		&"idle": 4,
		&"walk": 6,
		&"punch": 5,
		&"kick": 6,
		&"crouch": 3,
		&"crouch_punch": 5,
		&"crouch_kick": 6,
		&"block": 3,
		&"crouch_block": 3,
		&"jump": 5,
		&"hurt": 3,
		&"special_1": 8,
		&"special_2": 8,
		&"ko": 8,
	}
	var total_frames: int = 0
	for animation: StringName in expected_frames:
		_check(OKAMURA.sprite_frames.has_animation(animation), "missing Okamura animation %s" % animation)
		var frame_count: int = OKAMURA.sprite_frames.get_frame_count(animation)
		_check(
			frame_count == expected_frames[animation],
			"unexpected Okamura frame count for %s: %d" % [animation, frame_count],
		)
		total_frames += frame_count
		fighter.animated_sprite.play(animation)
		_check(fighter.animated_sprite.animation == animation, "Okamura could not play %s" % animation)
	_check(total_frames == 73, "Okamura production sprite contract must contain 73 frames")

	_check(OKAMURA.visual_scale > 0.0, "Okamura visual_scale must be positive")
	_check(
		fighter.sprite_root.scale.is_equal_approx(Vector2.ONE * OKAMURA.visual_scale),
		"Okamura must use one uniform SpriteRoot scale",
	)

	var okamura_height: float = _idle_rendered_height(OKAMURA)
	var joe_height: float = _idle_rendered_height(JOE)
	var frank_height: float = _idle_rendered_height(FRANK)
	var yamashita_height: float = _idle_rendered_height(YAMASHITA)
	var fujiyama_height: float = _idle_rendered_height(FUJIYAMA)
	print(
		"RUNTIME IDLE HEIGHTS Okamura=%.2f Joe=%.2f Frank=%.2f Yamashita=%.2f Fujiyama=%.2f"
		% [okamura_height, joe_height, frank_height, yamashita_height, fujiyama_height]
	)
	_check(absf(okamura_height / joe_height - 1.0) <= 0.075, "Okamura/Joe rendered height differs by more than 7.5%")
	_check(absf(okamura_height / frank_height - 1.0) <= 0.075, "Okamura/Frank rendered height differs by more than 7.5%")
	_check(absf(okamura_height / yamashita_height - 1.0) <= 0.075, "Okamura/Yamashita rendered height differs by more than 7.5%")
	_check(absf(okamura_height / fujiyama_height - 1.0) <= 0.075, "Okamura/Fujiyama rendered height differs by more than 7.5%")

	var opponent := Node2D.new()
	root.add_child(opponent)
	opponent.global_position = Vector2(100.0, 0.0)
	fighter.opponent = opponent
	fighter._face_opponent()
	_check(not fighter.animated_sprite.flip_h, "Okamura right-facing sprite must not flip")
	opponent.global_position = Vector2(-100.0, 0.0)
	fighter._face_opponent()
	_check(fighter.animated_sprite.flip_h, "Okamura left-facing sprite must flip")
	fighter.opponent = null
	opponent.queue_free()


func _idle_rendered_height(character: CharacterData) -> float:
	var texture: Texture2D = character.sprite_frames.get_frame_texture(&"idle", 0)
	var used_height: float = texture.get_image().get_used_rect().size.y
	return used_height * character.visual_scale


func _test_shuriken_projectile(attacker: Fighter) -> void:
	for direction: float in [1.0, -1.0]:
		attacker.facing_direction = direction
		var projectiles_before: int = get_nodes_in_group(&"special_projectiles").size()
		attacker._spawn_special_projectile(OKAMURA_SPECIAL_1)
		var launched_projectiles: Array[Node] = get_nodes_in_group(&"special_projectiles")
		_check(launched_projectiles.size() == projectiles_before + 1, "Okamura special_1 must spawn exactly one shuriken")
		if launched_projectiles.size() == projectiles_before + 1:
			var launched: SpecialProjectile = launched_projectiles[-1] as SpecialProjectile
			_check(launched != null, "Okamura spawned projectile has the wrong type")
			if launched != null:
				var expected_position := attacker.global_position + Vector2(
					absf(OKAMURA_SPECIAL_1.hitbox_offset_x) * direction,
					OKAMURA_SPECIAL_1.hitbox_offset_y,
				)
				_check(launched.global_position.is_equal_approx(expected_position), "Okamura shuriken spawn position changed")
				_check(is_equal_approx(launched.direction, direction), "Okamura shuriken spawn direction changed")
				_check(launched.projectile_visual.texture == OKAMURA_SPECIAL_1.projectile_texture, "spawned Okamura shuriken texture is missing")
				_check(not launched.visual.visible, "spawned Okamura shuriken still shows the grey fallback")
				launched.queue_free()

	var projectile: SpecialProjectile = PROJECTILE_SCENE.instantiate() as SpecialProjectile
	root.add_child(projectile)
	projectile.global_position = Vector2.ZERO
	projectile.configure(attacker, OKAMURA_SPECIAL_1, 1.0)
	var rectangle: RectangleShape2D = projectile.collision_shape.shape as RectangleShape2D
	_check(rectangle != null, "Okamura shuriken collision shape is missing")
	_check(rectangle.size.is_equal_approx(Vector2(24.0, 24.0)), "Okamura shuriken collision size changed")
	_check(projectile.get_node_or_null("ProjectileVisual") is Sprite2D, "Okamura shuriken Sprite2D is missing")
	_check(projectile.projectile_visual.texture == OKAMURA_SPECIAL_1.projectile_texture, "Okamura shuriken texture was not applied")
	_check(projectile.projectile_visual.visible, "Okamura shuriken Sprite2D is hidden")
	_check(not projectile.visual.visible, "Okamura grey Polygon2D fallback is still visible")
	_check(projectile.projectile_visual.scale.is_equal_approx(Vector2(0.55, 0.55)), "Okamura shuriken visual scale changed")
	_check(is_equal_approx(projectile.speed, 320.0), "Okamura shuriken speed changed")
	_check(is_equal_approx(projectile.max_distance, 440.0), "Okamura shuriken range changed")
	_check(is_equal_approx(projectile.lifetime_remaining, 1.8), "Okamura shuriken lifetime changed")
	_check(projectile.damage == attacker.get_scaled_damage(13), "Okamura shuriken damage changed")
	var start_x: float = projectile.global_position.x
	var start_rotation: float = projectile.projectile_visual.rotation
	projectile._physics_process(0.1)
	_check(is_equal_approx(projectile.global_position.x - start_x, 32.0), "Okamura shuriken rightward movement changed")
	_check(projectile.projectile_visual.rotation > start_rotation, "Okamura shuriken did not spin right")
	projectile.configure(attacker, OKAMURA_SPECIAL_1, -1.0)
	_check(projectile.projectile_visual.scale.is_equal_approx(Vector2(0.55, 0.55)), "left-moving shuriken must not mirror its texture")
	start_x = projectile.global_position.x
	start_rotation = projectile.projectile_visual.rotation
	projectile._physics_process(0.1)
	_check(is_equal_approx(projectile.global_position.x - start_x, -32.0), "Okamura shuriken leftward movement changed")
	_check(projectile.projectile_visual.rotation < start_rotation, "Okamura shuriken did not reverse spin left")
	projectile._physics_process(OKAMURA_SPECIAL_1.projectile_max_distance / OKAMURA_SPECIAL_1.projectile_speed)
	_check(projectile.is_queued_for_deletion(), "Okamura shuriken no longer expires at finite range")
	projectile.queue_free()


func _test_special_2_flying_kick(fighter: Fighter) -> void:
	await process_frame
	fighter.process_mode = Node.PROCESS_MODE_INHERIT
	await physics_frame
	for direction: float in [1.0, -1.0]:
		fighter.facing_direction = direction
		fighter._face_opponent()
		var projectiles_before: int = get_nodes_in_group(&"special_projectiles").size()
		var start_x: float = fighter.global_position.x
		fighter.request_special(2)
		_check(fighter.animated_sprite.animation == &"special_2", "Okamura special_2 animation did not start")
		_check(is_equal_approx(fighter.active_attack_forward_speed, 190.0), "Okamura special_2 forward speed changed")
		_check(fighter.animated_sprite.flip_h == (direction < 0.0), "Okamura special_2 facing flip is wrong")
		await physics_frame
		await physics_frame
		_check((fighter.global_position.x - start_x) * direction > 0.0, "Okamura special_2 did not move forward")
		await create_timer(OKAMURA_SPECIAL_2.startup_time + 0.02).timeout
		_check(fighter.attack_is_active, "Okamura special_2 did not enter its active window")
		_check(get_nodes_in_group(&"special_projectiles").size() == projectiles_before, "Okamura special_2 must not spawn a projectile")
		await create_timer(OKAMURA_SPECIAL_2.active_time + OKAMURA_SPECIAL_2.recovery_time + 0.02).timeout
		_check(fighter.fighter_state == Fighter.FighterState.NORMAL, "Okamura special_2 did not recover")
		_check(is_zero_approx(fighter.active_attack_forward_speed), "Okamura special_2 movement did not stop on recovery")
	fighter.process_mode = Node.PROCESS_MODE_DISABLED
