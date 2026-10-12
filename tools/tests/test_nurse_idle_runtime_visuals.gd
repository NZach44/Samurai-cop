extends SceneTree

const FIGHTER_SCENE: PackedScene = preload("res://scenes/fighters/fighter.tscn")
const NURSE: CharacterData = preload("res://data/fighters/nurse.tres")
const NURSE_SPECIAL_1: SpecialMoveData = preload("res://data/moves/nurse_special_1.tres")
const NURSE_SPECIAL_2: SpecialMoveData = preload("res://data/moves/nurse_special_2.tres")
const REFERENCES: Array[CharacterData] = [
	preload("res://data/fighters/joe_marshall.tres"),
	preload("res://data/fighters/frank_washington.tres"),
	preload("res://data/fighters/yamashita.tres"),
	preload("res://data/fighters/fujiyama.tres"),
	preload("res://data/fighters/okamura.tres"),
	preload("res://data/fighters/jennifer.tres"),
	preload("res://data/fighters/peggy.tres"),
]

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
	var fighter: Fighter = FIGHTER_SCENE.instantiate() as Fighter
	fighter.character_data = NURSE
	world.add_child(fighter)
	fighter.set_physics_process(false)

	_check(NURSE.sprite_frames.get_frame_count(&"idle") == 4, "Wild Nurse idle must have four frames")
	_check(is_equal_approx(NURSE.sprite_frames.get_animation_speed(&"idle"), 6.0), "Wild Nurse idle must run at 6 FPS")
	_check(NURSE.sprite_frames.get_animation_loop(&"idle"), "Wild Nurse idle must loop")
	_check(NURSE.sprite_frames.get_frame_count(&"walk") == 6, "Wild Nurse walk must have six frames")
	_check(is_equal_approx(NURSE.sprite_frames.get_animation_speed(&"walk"), 9.0), "Wild Nurse walk must run at 9 FPS")
	_check(NURSE.sprite_frames.get_animation_loop(&"walk"), "Wild Nurse walk must loop")
	_check(NURSE.sprite_frames.get_frame_count(&"punch") == 5, "Wild Nurse punch must have five frames")
	_check(is_equal_approx(NURSE.sprite_frames.get_animation_speed(&"punch"), 12.0), "Wild Nurse punch must run at 12 FPS")
	_check(not NURSE.sprite_frames.get_animation_loop(&"punch"), "Wild Nurse punch must not loop")
	_check(NURSE.sprite_frames.get_frame_count(&"kick") == 6, "Wild Nurse kick must have six frames")
	_check(is_equal_approx(NURSE.sprite_frames.get_animation_speed(&"kick"), 12.0), "Wild Nurse kick must run at 12 FPS")
	_check(not NURSE.sprite_frames.get_animation_loop(&"kick"), "Wild Nurse kick must not loop")
	_check(NURSE.sprite_frames.get_frame_count(&"crouch") == 3, "Wild Nurse crouch must have three frames")
	_check(is_equal_approx(NURSE.sprite_frames.get_animation_speed(&"crouch"), 8.0), "Wild Nurse crouch must run at 8 FPS")
	_check(not NURSE.sprite_frames.get_animation_loop(&"crouch"), "Wild Nurse crouch must hold instead of loop")
	_check(NURSE.sprite_frames.get_frame_count(&"crouch_punch") == 5, "Wild Nurse crouch punch must have five frames")
	_check(is_equal_approx(NURSE.sprite_frames.get_animation_speed(&"crouch_punch"), 12.0), "Wild Nurse crouch punch must run at 12 FPS")
	_check(not NURSE.sprite_frames.get_animation_loop(&"crouch_punch"), "Wild Nurse crouch punch must not loop")
	_check(NURSE.sprite_frames.get_frame_count(&"crouch_kick") == 6, "Wild Nurse crouch kick must have six frames")
	_check(is_equal_approx(NURSE.sprite_frames.get_animation_speed(&"crouch_kick"), 12.0), "Wild Nurse crouch kick must run at 12 FPS")
	_check(not NURSE.sprite_frames.get_animation_loop(&"crouch_kick"), "Wild Nurse crouch kick must not loop")
	for block_animation: StringName in [&"block", &"crouch_block"]:
		_check(NURSE.sprite_frames.get_frame_count(block_animation) == 3, "Wild Nurse %s must have three frames" % block_animation)
		_check(is_equal_approx(NURSE.sprite_frames.get_animation_speed(block_animation), 8.0), "Wild Nurse %s must run at 8 FPS" % block_animation)
		_check(not NURSE.sprite_frames.get_animation_loop(block_animation), "Wild Nurse %s must hold instead of loop" % block_animation)
	_check(NURSE.sprite_frames.get_frame_count(&"jump") == 5, "Wild Nurse jump must have five physics-selected frames")
	_check(is_equal_approx(NURSE.sprite_frames.get_animation_speed(&"jump"), 10.0), "Wild Nurse jump must use the 10 FPS contract")
	_check(not NURSE.sprite_frames.get_animation_loop(&"jump"), "Wild Nurse jump must not loop")
	_check(NURSE.sprite_frames.get_frame_count(&"hurt") == 3, "Wild Nurse hurt must have three frames")
	_check(is_equal_approx(NURSE.sprite_frames.get_animation_speed(&"hurt"), 10.0), "Wild Nurse hurt must run at 10 FPS")
	_check(not NURSE.sprite_frames.get_animation_loop(&"hurt"), "Wild Nurse hurt must hold instead of loop")
	for special_animation: StringName in [&"special_1", &"special_2"]:
		_check(NURSE.sprite_frames.get_frame_count(special_animation) == 8, "Wild Nurse %s must have eight frames" % special_animation)
		_check(is_equal_approx(NURSE.sprite_frames.get_animation_speed(special_animation), 12.0), "Wild Nurse %s must run at 12 FPS" % special_animation)
		_check(not NURSE.sprite_frames.get_animation_loop(special_animation), "Wild Nurse %s must not loop" % special_animation)
	_check(NURSE.sprite_frames.get_frame_count(&"ko") == 8, "Wild Nurse KO must have eight frames")
	_check(is_equal_approx(NURSE.sprite_frames.get_animation_speed(&"ko"), 10.0), "Wild Nurse KO must run at 10 FPS")
	_check(not NURSE.sprite_frames.get_animation_loop(&"ko"), "Wild Nurse KO must hold instead of loop")
	_check(NURSE_SPECIAL_1.projectile_texture != null, "Wild Nurse stethoscope projectile texture is missing")
	_check(NURSE_SPECIAL_1.projectile_texture.resource_path.ends_with("stethoscope.png"), "Wild Nurse Special 1 projectile is not the stethoscope")
	_check(NURSE_SPECIAL_1.projectile_visual_size == Vector2(64.0, 64.0), "Wild Nurse stethoscope visual size changed")
	_check(is_equal_approx(NURSE_SPECIAL_1.projectile_spin_speed, 10.0), "Wild Nurse stethoscope must spin")
	_check(NURSE_SPECIAL_2.projectile_texture != null, "Wild Nurse heart projectile texture is missing")
	_check(NURSE_SPECIAL_2.projectile_texture.resource_path.ends_with("heart.png"), "Wild Nurse Special 2 projectile is not the heart")
	_check(NURSE_SPECIAL_2.projectile_visual_size == Vector2(40.0, 40.0), "Wild Nurse heart visual size changed")
	_check(is_zero_approx(NURSE_SPECIAL_2.projectile_spin_speed), "Wild Nurse heart must not spin")
	_check(is_equal_approx(NURSE_SPECIAL_2.hitbox_offset_y, -86.0), "Wild Nurse heart no longer starts at syringe height")
	_check(is_equal_approx(NURSE.visual_scale, 1.63), "Wild Nurse visual_scale must be 1.63")
	_check(
		fighter.sprite_root.scale.is_equal_approx(Vector2.ONE * NURSE.visual_scale),
		"Wild Nurse must use one uniform SpriteRoot scale",
	)

	var minimum_center_x := INF
	var maximum_center_x := -INF
	for frame_index: int in range(4):
		var texture: Texture2D = NURSE.sprite_frames.get_frame_texture(&"idle", frame_index)
		_check(texture != null, "Wild Nurse idle frame %d is null" % [frame_index + 1])
		if texture == null:
			continue
		_check(not texture is AtlasTexture, "Wild Nurse idle frame %d is still a placeholder" % [frame_index + 1])
		_check(texture.get_size() == Vector2(128.0, 128.0), "Wild Nurse idle frame %d import is not 128x128" % [frame_index + 1])
		var used_rect: Rect2i = texture.get_image().get_used_rect()
		_check(used_rect.size.y == 108, "Wild Nurse idle frame %d imported height changed" % [frame_index + 1])
		_check(used_rect.end.y == 124, "Wild Nurse idle frame %d baseline changed" % [frame_index + 1])
		var center_x: float = used_rect.position.x + used_rect.size.x * 0.5
		minimum_center_x = minf(minimum_center_x, center_x)
		maximum_center_x = maxf(maximum_center_x, center_x)
	_check(maximum_center_x - minimum_center_x <= 0.25, "Wild Nurse idle has a horizontal visual jump")

	var walk_minimum_center_x := INF
	var walk_maximum_center_x := -INF
	var walk_minimum_height := INF
	var walk_maximum_height := -INF
	for frame_index: int in range(6):
		var texture: Texture2D = NURSE.sprite_frames.get_frame_texture(&"walk", frame_index)
		_check(texture != null, "Wild Nurse walk frame %d is null" % [frame_index + 1])
		if texture == null:
			continue
		_check(not texture is AtlasTexture, "Wild Nurse walk frame %d is still a placeholder" % [frame_index + 1])
		_check(texture.get_size() == Vector2(128.0, 128.0), "Wild Nurse walk frame %d import is not 128x128" % [frame_index + 1])
		var used_rect: Rect2i = texture.get_image().get_used_rect()
		_check(used_rect.end.y == 124, "Wild Nurse walk frame %d baseline changed" % [frame_index + 1])
		var center_x: float = used_rect.position.x + used_rect.size.x * 0.5
		walk_minimum_center_x = minf(walk_minimum_center_x, center_x)
		walk_maximum_center_x = maxf(walk_maximum_center_x, center_x)
		walk_minimum_height = minf(walk_minimum_height, used_rect.size.y)
		walk_maximum_height = maxf(walk_maximum_height, used_rect.size.y)
	_check(walk_maximum_center_x - walk_minimum_center_x <= 0.5, "Wild Nurse walk bakes horizontal travel into its frames")
	_check(walk_maximum_height == 108.0, "Wild Nurse walk maximum imported height differs from idle")
	_check(walk_minimum_height / 108.0 >= 0.99, "Wild Nurse walk has a scale pop relative to idle")

	var punch_minimum_center_x := INF
	var punch_maximum_center_x := -INF
	for frame_index: int in range(5):
		var texture: Texture2D = NURSE.sprite_frames.get_frame_texture(&"punch", frame_index)
		_check(texture != null, "Wild Nurse punch frame %d is null" % [frame_index + 1])
		if texture == null:
			continue
		_check(not texture is AtlasTexture, "Wild Nurse punch frame %d is still a placeholder" % [frame_index + 1])
		_check(texture.get_size() == Vector2(128.0, 128.0), "Wild Nurse punch frame %d import is not 128x128" % [frame_index + 1])
		var used_rect: Rect2i = texture.get_image().get_used_rect()
		_check(used_rect.end.y == 124, "Wild Nurse punch frame %d baseline changed" % [frame_index + 1])
		var center_x: float = used_rect.position.x + used_rect.size.x * 0.5
		punch_minimum_center_x = minf(punch_minimum_center_x, center_x)
		punch_maximum_center_x = maxf(punch_maximum_center_x, center_x)
	_check(punch_maximum_center_x - punch_minimum_center_x <= 0.5, "Wild Nurse punch bakes horizontal travel into its frames")

	var kick_height_reference := -1
	for frame_index: int in range(6):
		var texture: Texture2D = NURSE.sprite_frames.get_frame_texture(&"kick", frame_index)
		_check(texture != null, "Wild Nurse kick frame %d is null" % [frame_index + 1])
		if texture == null:
			continue
		_check(not texture is AtlasTexture, "Wild Nurse kick frame %d is still a placeholder" % [frame_index + 1])
		_check(texture.get_size() == Vector2(128.0, 128.0), "Wild Nurse kick frame %d import is not 128x128" % [frame_index + 1])
		var image := texture.get_image()
		var used_rect: Rect2i = image.get_used_rect()
		_check(used_rect.end.y == 124, "Wild Nurse kick frame %d baseline changed" % [frame_index + 1])
		if frame_index == 0:
			kick_height_reference = used_rect.size.y
		else:
			_check(
				float(used_rect.size.y) / float(kick_height_reference) >= 0.94,
				"Wild Nurse kick frame %d exceeds allowed pose compression" % [frame_index + 1],
			)
	_check(
		NURSE.sprite_frames.get_frame_texture(&"kick", 0).get_image().get_data()
		== NURSE.sprite_frames.get_frame_texture(&"kick", 5).get_image().get_data(),
		"Wild Nurse kick recovery does not return to its exact guard anchor",
	)

	for frame_index: int in range(3):
		var texture: Texture2D = NURSE.sprite_frames.get_frame_texture(&"crouch", frame_index)
		_check(texture != null, "Wild Nurse crouch frame %d is null" % [frame_index + 1])
		if texture == null:
			continue
		_check(not texture is AtlasTexture, "Wild Nurse crouch frame %d is still a placeholder" % [frame_index + 1])
		_check(texture.get_size() == Vector2(128.0, 128.0), "Wild Nurse crouch frame %d import is not 128x128" % [frame_index + 1])
		_check(texture.get_image().get_used_rect().end.y == 124, "Wild Nurse crouch frame %d baseline changed" % [frame_index + 1])

	for animation: StringName in [&"crouch_punch", &"crouch_kick", &"block", &"crouch_block", &"jump", &"hurt", &"special_1", &"special_2", &"ko"]:
		var expected_count: int = NURSE.sprite_frames.get_frame_count(animation)
		for frame_index: int in range(expected_count):
			var texture: Texture2D = NURSE.sprite_frames.get_frame_texture(animation, frame_index)
			_check(texture != null, "Wild Nurse %s frame %d is null" % [animation, frame_index + 1])
			if texture == null:
				continue
			_check(not texture is AtlasTexture, "Wild Nurse %s frame %d is still a placeholder" % [animation, frame_index + 1])
			_check(texture.get_size() == Vector2(128.0, 128.0), "Wild Nurse %s frame %d import is not 128x128" % [animation, frame_index + 1])
			_check(texture.get_image().get_used_rect().end.y == 124, "Wild Nurse %s frame %d baseline changed" % [animation, frame_index + 1])

	var runtime_height := _idle_runtime_height(NURSE)
	var reference_total := 0.0
	for reference: CharacterData in REFERENCES:
		reference_total += _idle_runtime_height(reference)
	var reference_mean := reference_total / REFERENCES.size()
	print("RUNTIME IDLE HEIGHTS WildNurse=%.2f roster_mean=%.2f difference=%.2f%%" % [
		runtime_height,
		reference_mean,
		(runtime_height / reference_mean - 1.0) * 100.0,
	])
	_check(absf(runtime_height / reference_mean - 1.0) <= 0.075, "Wild Nurse runtime height differs from roster mean by more than 7.5%")

	var imported_baseline_y := 124.0
	var runtime_foot_y := fighter.sprite_root.position.y + NURSE.visual_scale * (
		fighter.animated_sprite.position.y + imported_baseline_y - 64.0
	)
	_check(absf(runtime_foot_y - 64.0) <= 8.0, "Wild Nurse idle is not grounded within the production baseline tolerance")

	var original_root_position := fighter.sprite_root.position
	var opponent := Node2D.new()
	world.add_child(opponent)
	fighter.global_position = Vector2.ZERO
	opponent.global_position = Vector2(100.0, 0.0)
	fighter.opponent = opponent
	fighter._play_animation_if_available(&"idle")
	_check(fighter.animated_sprite.animation == &"idle", "Wild Nurse could not enter idle")
	fighter.velocity.x = NURSE.move_speed
	fighter._play_animation_if_available(&"walk")
	_check(fighter.animated_sprite.animation == &"walk", "Wild Nurse idle-to-walk transition failed")
	fighter._face_opponent()
	_check(not fighter.animated_sprite.flip_h, "Wild Nurse right-facing walk is flipped")
	opponent.global_position.x = -100.0
	fighter.velocity.x = -NURSE.move_speed
	fighter._face_opponent()
	_check(fighter.animated_sprite.flip_h, "Wild Nurse left-facing walk did not flip")
	_check(fighter.sprite_root.position == original_root_position, "Wild Nurse facing changed the visual position")
	_check(fighter.sprite_root.scale.is_equal_approx(Vector2.ONE * NURSE.visual_scale), "Wild Nurse facing changed visual scale")
	fighter.animated_sprite.set_frame_and_progress(5, 0.9)
	fighter.animated_sprite.play(&"walk")
	await create_timer(0.2).timeout
	_check(fighter.animated_sprite.animation == &"walk" and fighter.animated_sprite.is_playing(), "Wild Nurse walk did not continue looping")
	_check(fighter.animated_sprite.frame != 5, "Wild Nurse walk did not wrap from its final frame")
	fighter.velocity.x = 0.0
	fighter._play_animation_if_available(&"idle")
	_check(fighter.animated_sprite.animation == &"idle", "Wild Nurse walk-to-idle transition failed")
	await create_timer(0.85).timeout
	_check(fighter.animated_sprite.animation == &"idle" and fighter.animated_sprite.is_playing(), "Wild Nurse idle did not continue looping")

	var original_punch_damage := fighter.punch_damage
	var original_punch_startup := fighter.punch_startup_time
	var original_punch_active := fighter.punch_active_time
	var original_punch_recovery := fighter.punch_recovery_time
	var original_hitbox_position := fighter.punch_hit_box.position
	var original_hitbox_shape: RectangleShape2D = fighter.punch_hit_box_shape.shape as RectangleShape2D
	var original_hitbox_size := original_hitbox_shape.size
	opponent.global_position.x = 100.0
	fighter._face_opponent()
	fighter.request_punch()
	_check(fighter.is_performing_attack(), "Wild Nurse right-facing punch did not enter attacking state")
	_check(fighter.animated_sprite.animation == &"punch", "Wild Nurse right-facing punch art did not display")
	_check(not fighter.animated_sprite.flip_h, "Wild Nurse right-facing punch is flipped")
	await create_timer(0.5).timeout
	_check(not fighter.is_performing_attack(), "Wild Nurse punch did not return from attack state")
	fighter._play_animation_if_available(&"idle")
	_check(fighter.animated_sprite.animation == &"idle", "Wild Nurse punch did not transition cleanly back to idle")
	opponent.global_position.x = -100.0
	fighter._face_opponent()
	fighter.request_punch()
	_check(fighter.animated_sprite.animation == &"punch", "Wild Nurse left-facing punch art did not display")
	_check(fighter.animated_sprite.flip_h, "Wild Nurse left-facing punch did not flip")
	await create_timer(0.5).timeout
	_check(fighter.punch_damage == original_punch_damage, "Wild Nurse punch damage changed during art integration")
	_check(is_equal_approx(fighter.punch_startup_time, original_punch_startup), "Wild Nurse punch startup changed during art integration")
	_check(is_equal_approx(fighter.punch_active_time, original_punch_active), "Wild Nurse punch active time changed during art integration")
	_check(is_equal_approx(fighter.punch_recovery_time, original_punch_recovery), "Wild Nurse punch recovery changed during art integration")
	_check(fighter.punch_hit_box.position == original_hitbox_position, "Wild Nurse punch hitbox position did not restore")
	_check(original_hitbox_shape.size == original_hitbox_size, "Wild Nurse punch hitbox size changed during art integration")

	var original_kick_damage := fighter.kick_damage
	var original_kick_startup := fighter.kick_startup_time
	var original_kick_active := fighter.kick_active_time
	var original_kick_recovery := fighter.kick_recovery_time
	var original_kick_width := fighter.kick_hitbox_width
	var original_kick_height := fighter.kick_hitbox_height
	var original_kick_offset := fighter.kick_hitbox_offset_x
	opponent.global_position.x = 100.0
	fighter._face_opponent()
	fighter.request_kick()
	_check(fighter.is_performing_attack(), "Wild Nurse right-facing kick did not enter attacking state")
	_check(fighter.animated_sprite.animation == &"kick", "Wild Nurse right-facing kick art did not display")
	_check(not fighter.animated_sprite.flip_h, "Wild Nurse right-facing kick is flipped")
	await create_timer(0.65).timeout
	_check(not fighter.is_performing_attack(), "Wild Nurse kick did not return from attack state")
	fighter._play_animation_if_available(&"idle")
	_check(fighter.animated_sprite.animation == &"idle", "Wild Nurse kick did not transition cleanly back to idle")
	opponent.global_position.x = -100.0
	fighter._face_opponent()
	fighter.request_kick()
	_check(fighter.animated_sprite.animation == &"kick", "Wild Nurse left-facing kick art did not display")
	_check(fighter.animated_sprite.flip_h, "Wild Nurse left-facing kick did not flip")
	await create_timer(0.65).timeout
	_check(fighter.kick_damage == original_kick_damage, "Wild Nurse kick damage changed during art integration")
	_check(is_equal_approx(fighter.kick_startup_time, original_kick_startup), "Wild Nurse kick startup changed during art integration")
	_check(is_equal_approx(fighter.kick_active_time, original_kick_active), "Wild Nurse kick active time changed during art integration")
	_check(is_equal_approx(fighter.kick_recovery_time, original_kick_recovery), "Wild Nurse kick recovery changed during art integration")
	_check(is_equal_approx(fighter.kick_hitbox_width, original_kick_width), "Wild Nurse kick hitbox width changed during art integration")
	_check(is_equal_approx(fighter.kick_hitbox_height, original_kick_height), "Wild Nurse kick hitbox height changed during art integration")
	_check(is_equal_approx(fighter.kick_hitbox_offset_x, original_kick_offset), "Wild Nurse kick hitbox offset changed during art integration")
	fighter._play_animation_if_available(&"crouch")
	_check(fighter.animated_sprite.animation == &"crouch", "Wild Nurse dedicated crouch art did not display")
	await create_timer(0.5).timeout
	_check(fighter.animated_sprite.frame == 2, "Wild Nurse crouch did not hold its final frame")
	opponent.global_position.x = 100.0
	fighter._face_opponent()
	fighter._play_animation_if_available(&"crouch_punch")
	_check(fighter.animated_sprite.animation == &"crouch_punch", "Wild Nurse dedicated right-facing crouch punch did not display")
	_check(not fighter.animated_sprite.flip_h, "Wild Nurse right-facing crouch punch is flipped")
	fighter._play_animation_if_available(&"crouch")
	_check(fighter.animated_sprite.animation == &"crouch", "Wild Nurse crouch punch did not transition back to crouch art")
	opponent.global_position.x = -100.0
	fighter._face_opponent()
	fighter._play_animation_if_available(&"crouch_kick")
	_check(fighter.animated_sprite.animation == &"crouch_kick", "Wild Nurse dedicated left-facing crouch kick did not display")
	_check(fighter.animated_sprite.flip_h, "Wild Nurse left-facing crouch kick did not flip")
	fighter._play_animation_if_available(&"crouch")
	_check(fighter.animated_sprite.animation == &"crouch", "Wild Nurse crouch kick did not transition back to crouch art")
	opponent.global_position.x = 100.0
	fighter._face_opponent()
	fighter._play_animation_if_available(&"block")
	_check(fighter.animated_sprite.animation == &"block" and not fighter.animated_sprite.flip_h, "Wild Nurse right-facing block art did not display")
	await create_timer(0.45).timeout
	_check(fighter.animated_sprite.frame == 2, "Wild Nurse block did not hold its final frame")
	opponent.global_position.x = -100.0
	fighter._face_opponent()
	fighter._play_animation_if_available(&"crouch_block")
	_check(fighter.animated_sprite.animation == &"crouch_block" and fighter.animated_sprite.flip_h, "Wild Nurse left-facing crouch block art did not display")
	await create_timer(0.45).timeout
	_check(fighter.animated_sprite.frame == 2, "Wild Nurse crouch block did not hold its final frame")
	var jump_speed := fighter.get_jump_velocity()
	var jump_velocities: Array[float] = [-jump_speed, -jump_speed * 0.4, 0.0, jump_speed * 0.4, jump_speed]
	for jump_frame: int in range(5):
		fighter.velocity.y = jump_velocities[jump_frame]
		fighter._update_jump_animation()
		_check(fighter.animated_sprite.animation == &"jump", "Wild Nurse jump art did not display")
		_check(fighter.animated_sprite.frame == jump_frame, "Wild Nurse jump physics selected wrong phase %d" % [jump_frame + 1])
		_check(not fighter.animated_sprite.is_playing(), "Wild Nurse physics-selected jump frame must remain paused")
	fighter._play_animation_if_available(&"hurt")
	await create_timer(0.35).timeout
	_check(fighter.animated_sprite.animation == &"hurt" and fighter.animated_sprite.frame == 2, "Wild Nurse hurt did not hold its final frame")

	for special_slot: int in [1, 2]:
		var special_move: SpecialMoveData = NURSE_SPECIAL_1 if special_slot == 1 else NURSE_SPECIAL_2
		for direction: float in [1.0, -1.0]:
			fighter.facing_direction = direction
			var projectile_count_before: int = get_nodes_in_group(&"special_projectiles").size()
			fighter._spawn_special_projectile(special_move)
			var projectiles: Array[Node] = get_nodes_in_group(&"special_projectiles")
			_check(projectiles.size() == projectile_count_before + 1, "Wild Nurse %s must spawn exactly one projectile" % special_move.animation_name)
			if projectiles.size() != projectile_count_before + 1:
				continue
			var projectile: SpecialProjectile = projectiles[-1] as SpecialProjectile
			_check(projectile != null, "Wild Nurse %s spawned the wrong projectile type" % special_move.animation_name)
			if projectile == null:
				continue
			var expected_position := fighter.global_position + Vector2(absf(special_move.hitbox_offset_x) * direction, special_move.hitbox_offset_y)
			_check(projectile.global_position.is_equal_approx(expected_position), "Wild Nurse %s projectile origin changed" % special_move.animation_name)
			_check(projectile.projectile_visual.texture == special_move.projectile_texture, "Wild Nurse %s runtime projectile texture is missing" % special_move.animation_name)
			_check(projectile.projectile_visual.visible and not projectile.visual.visible, "Wild Nurse %s textured/fallback visual state is wrong" % special_move.animation_name)
			var expected_visual_scale := special_move.projectile_visual_size / special_move.projectile_texture.get_size()
			_check(projectile.projectile_visual.scale.abs().is_equal_approx(expected_visual_scale), "Wild Nurse %s projectile visual size changed" % special_move.animation_name)
			var start_rotation: float = projectile.projectile_visual.rotation
			projectile._physics_process(0.1)
			if special_slot == 1:
				_check(not is_equal_approx(projectile.projectile_visual.rotation, start_rotation), "Wild Nurse stethoscope projectile did not spin")
			else:
				_check(is_equal_approx(projectile.projectile_visual.rotation, start_rotation), "Wild Nurse heart projectile unexpectedly spins")
			projectile.queue_free()
			await process_frame

	opponent.global_position.x = 100.0
	fighter._face_opponent()
	fighter.request_special(1)
	_check(fighter.animated_sprite.animation == &"special_1" and not fighter.animated_sprite.flip_h, "Wild Nurse right-facing Special 1 art did not display")
	await create_timer(NURSE_SPECIAL_1.startup_time + NURSE_SPECIAL_1.active_time + NURSE_SPECIAL_1.recovery_time + 0.05).timeout
	_check(fighter.fighter_state == Fighter.FighterState.NORMAL, "Wild Nurse Special 1 did not recover to idle state")
	opponent.global_position.x = -100.0
	fighter._face_opponent()
	fighter.request_special(2)
	_check(fighter.animated_sprite.animation == &"special_2" and fighter.animated_sprite.flip_h, "Wild Nurse left-facing Special 2 art did not display")
	await create_timer(NURSE_SPECIAL_2.startup_time + NURSE_SPECIAL_2.active_time + NURSE_SPECIAL_2.recovery_time + 0.05).timeout
	_check(fighter.fighter_state == Fighter.FighterState.NORMAL, "Wild Nurse Special 2 did not recover to idle state")
	for spawned_projectile: Node in get_nodes_in_group(&"special_projectiles"):
		spawned_projectile.queue_free()
	await process_frame

	fighter._play_animation_if_available(&"ko")
	await create_timer(0.9).timeout
	_check(fighter.animated_sprite.animation == &"ko" and fighter.animated_sprite.frame == 7, "Wild Nurse KO did not hold its final grounded frame")

	if failures.is_empty():
		print("PASS Wild Nurse complete production set, projectiles, runtime scale, transitions, holds, gameplay timing, physics phases, and both facings")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _idle_runtime_height(character: CharacterData) -> float:
	var texture: Texture2D = character.sprite_frames.get_frame_texture(&"idle", 0)
	return texture.get_image().get_used_rect().size.y * character.visual_scale
