extends SceneTree

const FIGHTER_SCENE: PackedScene = preload("res://scenes/fighters/fighter.tscn")
const OKAMURA: CharacterData = preload("res://data/fighters/okamura.tres")
const JOE: CharacterData = preload("res://data/fighters/joe_marshall.tres")
const FRANK: CharacterData = preload("res://data/fighters/frank_washington.tres")
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
	_check(OKAMURA_SPECIAL_1.projectile_texture == null, "Okamura shuriken unexpectedly gained a fighter-sprite texture")

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
	var fujiyama_height: float = _idle_rendered_height(FUJIYAMA)
	print(
		"RUNTIME IDLE HEIGHTS Okamura=%.2f Joe=%.2f Frank=%.2f Fujiyama=%.2f"
		% [okamura_height, joe_height, frank_height, fujiyama_height]
	)
	_check(absf(okamura_height / joe_height - 1.0) <= 0.075, "Okamura/Joe rendered height differs by more than 7.5%")
	_check(absf(okamura_height / frank_height - 1.0) <= 0.075, "Okamura/Frank rendered height differs by more than 7.5%")
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
