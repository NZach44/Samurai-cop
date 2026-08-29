extends SceneTree

const FIGHTER_SCENE: PackedScene = preload("res://scenes/fighters/fighter.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/special_projectile.tscn")
const FUJIYAMA: CharacterData = preload("res://data/fighters/fujiyama.tres")
const JOE: CharacterData = preload("res://data/fighters/joe_marshall.tres")
const FRANK: CharacterData = preload("res://data/fighters/frank_washington.tres")
const FUJIYAMA_SPECIAL_1: SpecialMoveData = preload("res://data/moves/fujiyama_special_1.tres")
const FUJIYAMA_SPECIAL_2: SpecialMoveData = preload("res://data/moves/fujiyama_special_2.tres")
const FALLBACK_PROJECTILE_MOVE: SpecialMoveData = preload("res://data/moves/frank_special_2.tres")

var failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var attacker: Fighter = FIGHTER_SCENE.instantiate() as Fighter
	attacker.character_data = FUJIYAMA
	arena.add_child(attacker)
	attacker.process_mode = Node.PROCESS_MODE_DISABLED

	_test_character_visuals(attacker)
	_test_textured_projectile(attacker)
	_test_fallback_projectile(attacker)

	attacker.queue_free()
	if failures.is_empty():
		print("PASS Fujiyama production sprites, runtime visuals, and generic projectile regression")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


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
		_check(FUJIYAMA.sprite_frames.has_animation(animation), "missing Fujiyama animation %s" % animation)
		var frame_count: int = FUJIYAMA.sprite_frames.get_frame_count(animation)
		_check(
			frame_count == expected_frames[animation],
			"unexpected Fujiyama frame count for %s" % animation
		)
		total_frames += frame_count
		fighter.animated_sprite.play(animation)
		_check(fighter.animated_sprite.animation == animation, "Fujiyama could not play %s" % animation)
	_check(total_frames == 73, "Fujiyama production sprite contract must contain 73 frames")

	_check(is_equal_approx(FUJIYAMA.visual_scale, 2.05), "Fujiyama visual_scale must be 2.05")
	_check(fighter.sprite_root.scale.is_equal_approx(Vector2(2.05, 2.05)), "Fujiyama must use one SpriteRoot scale")
	var fujiyama_height: float = _idle_rendered_height(FUJIYAMA)
	var joe_height: float = _idle_rendered_height(JOE)
	var frank_height: float = _idle_rendered_height(FRANK)
	print("RUNTIME IDLE HEIGHTS Fujiyama=%.2f Joe=%.2f Frank=%.2f" % [fujiyama_height, joe_height, frank_height])
	_check(absf(fujiyama_height / joe_height - 1.0) <= 0.05, "Fujiyama/Joe rendered height differs by more than 5%%")
	_check(absf(fujiyama_height / frank_height - 1.0) <= 0.05, "Fujiyama/Frank rendered height differs by more than 5%%")

	var opponent := Node2D.new()
	root.add_child(opponent)
	opponent.global_position = Vector2(100.0, 0.0)
	fighter.opponent = opponent
	fighter._face_opponent()
	_check(not fighter.animated_sprite.flip_h, "Fujiyama right-facing sprite must not flip")
	opponent.global_position = Vector2(-100.0, 0.0)
	fighter._face_opponent()
	_check(fighter.animated_sprite.flip_h, "Fujiyama left-facing sprite must flip")
	fighter.opponent = null
	opponent.queue_free()

	_check(FUJIYAMA_SPECIAL_2.behavior == SpecialMoveData.SpecialBehavior.FLYING_KICK, "Fujiyama special_2 behavior changed")
	_check(FUJIYAMA_SPECIAL_2.projectile_texture == null, "Fujiyama special_2 unexpectedly gained a projectile texture")


func _idle_rendered_height(character: CharacterData) -> float:
	var texture: Texture2D = character.sprite_frames.get_frame_texture(&"idle", 0)
	var used_height: float = texture.get_image().get_used_rect().size.y
	return used_height * character.visual_scale


func _test_textured_projectile(attacker: Fighter) -> void:
	var projectiles_before: int = get_nodes_in_group(&"special_projectiles").size()
	attacker._spawn_special_projectile(FUJIYAMA_SPECIAL_1)
	var launched_projectiles: Array[Node] = get_nodes_in_group(&"special_projectiles")
	_check(launched_projectiles.size() == projectiles_before + 1, "Fujiyama special_1 did not launch a projectile")
	if launched_projectiles.size() > projectiles_before:
		var launched: SpecialProjectile = launched_projectiles[-1] as SpecialProjectile
		_check(launched.visual.texture == FUJIYAMA_SPECIAL_1.projectile_texture, "launched special_1 projectile is not the piano")
		launched.queue_free()

	var projectile: SpecialProjectile = PROJECTILE_SCENE.instantiate() as SpecialProjectile
	root.add_child(projectile)
	projectile.configure(attacker, FUJIYAMA_SPECIAL_1, 1.0)
	var rectangle: RectangleShape2D = projectile.collision_shape.shape as RectangleShape2D
	_check(rectangle.size.is_equal_approx(Vector2(78.0, 56.0)), "piano collision must remain projectile_size")
	_check(_polygon_size(projectile.visual.polygon).is_equal_approx(Vector2(132.0, 78.0)), "piano visual must use projectile_visual_size")
	_check(projectile.visual.texture == FUJIYAMA_SPECIAL_1.projectile_texture, "piano texture was not applied")
	_check(projectile.visual.color.is_equal_approx(Color.WHITE), "textured projectile must render without fallback tint")
	_check(projectile.visual.uv.size() == 4, "textured projectile must define four UV points")
	_check(projectile.visual.uv[2].is_equal_approx(FUJIYAMA_SPECIAL_1.projectile_texture.get_size()), "piano UVs must cover the complete texture")
	_check(_texture_is_predominantly_black(FUJIYAMA_SPECIAL_1.projectile_texture), "piano texture is not predominantly black")
	_check(projectile.visual.scale.x > 0.0, "right-traveling piano must face right")
	projectile.configure(attacker, FUJIYAMA_SPECIAL_1, -1.0)
	_check(projectile.visual.scale.x < 0.0, "left-traveling piano must flip")
	_check(is_equal_approx(projectile.speed, 180.0), "piano projectile speed changed")
	_check(is_equal_approx(projectile.max_distance, 360.0), "piano projectile range changed")
	_check(is_equal_approx(projectile.lifetime_remaining, 2.4), "piano projectile lifetime changed")
	_check(projectile.damage == attacker.get_scaled_damage(20), "piano projectile damage changed")
	_check(is_equal_approx(projectile.block_stun_duration, FUJIYAMA_SPECIAL_1.block_stun_duration), "piano block stun changed")
	_check(is_equal_approx(projectile.hit_stun_duration, FUJIYAMA_SPECIAL_1.hit_stun_duration), "piano hit stun changed")
	_check(is_equal_approx(projectile.knockback, FUJIYAMA_SPECIAL_1.knockback), "piano knockback changed")
	projectile.queue_free()


func _test_fallback_projectile(attacker: Fighter) -> void:
	var projectile: SpecialProjectile = PROJECTILE_SCENE.instantiate() as SpecialProjectile
	root.add_child(projectile)
	projectile.global_position = Vector2.ZERO
	projectile.configure(attacker, FALLBACK_PROJECTILE_MOVE, 1.0)
	var rectangle: RectangleShape2D = projectile.collision_shape.shape as RectangleShape2D
	_check(projectile.visual.texture == null, "textureless projectile must keep Polygon2D fallback")
	_check(projectile.visual.color.is_equal_approx(FALLBACK_PROJECTILE_MOVE.projectile_color), "fallback projectile color changed")
	_check(projectile.visual.uv.is_empty(), "fallback projectile must not retain texture UVs")
	_check(rectangle.size.is_equal_approx(FALLBACK_PROJECTILE_MOVE.projectile_size), "fallback collision size changed")
	_check(_polygon_size(projectile.visual.polygon).is_equal_approx(FALLBACK_PROJECTILE_MOVE.projectile_size), "fallback visual size changed")
	var expected_distance: float = FALLBACK_PROJECTILE_MOVE.projectile_speed * 0.1
	projectile._physics_process(0.1)
	_check(is_equal_approx(projectile.global_position.x, expected_distance), "fallback projectile movement changed")
	projectile._physics_process(FALLBACK_PROJECTILE_MOVE.projectile_max_distance / FALLBACK_PROJECTILE_MOVE.projectile_speed)
	_check(projectile.is_queued_for_deletion(), "fallback projectile no longer expires at finite range")


func _polygon_size(polygon: PackedVector2Array) -> Vector2:
	var minimum: Vector2 = polygon[0]
	var maximum: Vector2 = polygon[0]
	for point: Vector2 in polygon:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return maximum - minimum


func _texture_is_predominantly_black(texture: Texture2D) -> bool:
	var image: Image = texture.get_image()
	var opaque_pixels: int = 0
	var dark_pixels: int = 0
	var brown_pixels: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var color: Color = image.get_pixel(x, y)
			if color.a < 0.5:
				continue
			opaque_pixels += 1
			if maxf(color.r, maxf(color.g, color.b)) < 0.24:
				dark_pixels += 1
			if color.r > 0.28 and color.r > color.g * 1.3 and color.r > color.b * 1.3:
				brown_pixels += 1
	return (
		opaque_pixels > 0
		and float(dark_pixels) / opaque_pixels > 0.55
		and float(brown_pixels) / opaque_pixels < 0.04
	)
