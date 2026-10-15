extends SceneTree

const FIGHTER_SCENE: PackedScene = preload("res://scenes/fighters/fighter.tscn")
const PEGGY: CharacterData = preload("res://data/fighters/peggy.tres")
const PEGGY_HEART: SpecialMoveData = preload("res://data/moves/peggy_special_2.tres")
const PROJECTILE_CASES: Array[Dictionary] = [
	{"fighter": preload("res://data/fighters/frank_washington.tres"), "move": preload("res://data/moves/frank_special_2.tres")},
	{"fighter": preload("res://data/fighters/fujiyama.tres"), "move": preload("res://data/moves/fujiyama_special_1.tres")},
	{"fighter": preload("res://data/fighters/jennifer.tres"), "move": preload("res://data/moves/jennifer_special_1.tres")},
	{"fighter": preload("res://data/fighters/jennifer.tres"), "move": preload("res://data/moves/jennifer_special_2.tres")},
	{"fighter": preload("res://data/fighters/nurse.tres"), "move": preload("res://data/moves/nurse_special_1.tres")},
	{"fighter": preload("res://data/fighters/nurse.tres"), "move": preload("res://data/moves/nurse_special_2.tres")},
	{"fighter": preload("res://data/fighters/okamura.tres"), "move": preload("res://data/moves/okamura_special_1.tres")},
	{"fighter": PEGGY, "move": preload("res://data/moves/peggy_special_1.tres")},
	{"fighter": PEGGY, "move": PEGGY_HEART},
	{"fighter": preload("res://data/fighters/yamashita.tres"), "move": preload("res://data/fighters/yamashita_special_2.tres")},
]

var failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	_test_projectile_speeds()
	_test_handcuffs_readability()
	await _test_peggy_heart_spawn()
	if failures.is_empty():
		print("PASS projectile speed, Peggy muzzle origin, and handcuffs readability")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_projectile_speeds() -> void:
	for entry: Dictionary in PROJECTILE_CASES:
		var fighter: CharacterData = entry["fighter"]
		var move: SpecialMoveData = entry["move"]
		_check(move.behavior == SpecialMoveData.SpecialBehavior.PROJECTILE, "%s is no longer a projectile" % move.special_id)
		_check(
			move.projectile_speed > fighter.move_speed,
			"%s projectile can be overtaken by %s walking" % [move.special_id, fighter.display_name]
		)
		_check(
			move.projectile_speed / fighter.move_speed >= 1.12,
			"%s projectile needs at least a 12%% speed margin over its fighter" % move.special_id
		)


func _test_handcuffs_readability() -> void:
	var path := "res://assets/characters/peggy/effects/handcuffs.png"
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	_check(image != null and not image.is_empty(), "Peggy handcuffs image is missing")
	if image == null or image.is_empty():
		return
	_check(image.get_size() == Vector2i(128, 128), "Peggy handcuffs must remain 128x128")
	var used_rect: Rect2i = image.get_used_rect()
	_check(used_rect.size.x >= 96 and used_rect.size.y >= 80, "Peggy handcuffs silhouette is still too thin")
	var visible_pixels: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a > 0.1:
				visible_pixels += 1
	_check(visible_pixels >= 2000, "Peggy handcuffs do not contain enough visible area")


func _test_peggy_heart_spawn() -> void:
	_check(is_equal_approx(PEGGY_HEART.hitbox_offset_y, -84.0), "Peggy heart is not aligned to the gun muzzle height")
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var fighter: Fighter = FIGHTER_SCENE.instantiate() as Fighter
	fighter.character_data = PEGGY
	world.add_child(fighter)
	fighter.set_physics_process(false)
	fighter.global_position = Vector2(300.0, 240.0)
	for direction: float in [1.0, -1.0]:
		fighter.facing_direction = direction
		fighter._spawn_special_projectile(PEGGY_HEART)
		var projectiles: Array[Node] = get_nodes_in_group(&"special_projectiles")
		_check(not projectiles.is_empty(), "Peggy heart did not spawn")
		if projectiles.is_empty():
			continue
		var projectile: SpecialProjectile = projectiles[-1] as SpecialProjectile
		var expected := fighter.global_position + Vector2(
			absf(PEGGY_HEART.hitbox_offset_x) * direction,
			-84.0
		)
		_check(projectile.global_position.is_equal_approx(expected), "Peggy heart runtime origin differs from the muzzle anchor")
		projectile.queue_free()
		await process_frame
	world.queue_free()
	await process_frame
