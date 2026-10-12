extends SceneTree

const ARENA_SCENE: PackedScene = preload("res://scenes/arenas/test_arena.tscn")
const JOE: CharacterData = preload("res://data/fighters/joe_marshall.tres")
const FRANK: CharacterData = preload("res://data/fighters/frank_washington.tres")
const YAMASHITA: CharacterData = preload("res://data/fighters/yamashita.tres")
const FUJIYAMA: CharacterData = preload("res://data/fighters/fujiyama.tres")
const OKAMURA: CharacterData = preload("res://data/fighters/okamura.tres")
const JENNIFER: CharacterData = preload("res://data/fighters/jennifer.tres")
const PEGGY: CharacterData = preload("res://data/fighters/peggy.tres")
const NURSE: CharacterData = preload("res://data/fighters/nurse.tres")

var failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var expected_mapping: Dictionary = {
		JENNIFER: &"stage_01",
		FUJIYAMA: &"stage_02",
		FRANK: &"stage_03",
		YAMASHITA: &"stage_04",
		JOE: &"stage_04",
		OKAMURA: &"stage_05",
		PEGGY: &"stage_06",
		NURSE: &"stage_07",
	}
	for character: CharacterData in expected_mapping:
		var expected_arena_id: StringName = expected_mapping[character]
		_check(character.home_arena_id == expected_arena_id, "%s home arena mapping changed" % character.display_name)
		_check(ArenaCatalog.arena_id_for_opponent(character) == expected_arena_id, "%s is not authoritative as the opponent arena" % character.display_name)

	_check(ArenaCatalog.get_display_name(&"stage_01") == "Lion Head Room", "stage_01 name changed")
	_check(ArenaCatalog.get_display_name(&"stage_02") == "Chief's House", "stage_02 name changed")
	_check(ArenaCatalog.get_display_name(&"stage_03") == "Parking", "stage_03 name changed")
	_check(ArenaCatalog.get_display_name(&"stage_04") == "Outlands", "stage_04 name changed")
	_check(ArenaCatalog.get_display_name(&"stage_05") == "Outlands 2", "stage_05 name changed")
	_check(ArenaCatalog.get_display_name(&"stage_06") == "Police Station", "stage_06 name changed")
	_check(ArenaCatalog.get_display_name(&"stage_07") == "Hospital", "stage_07 name changed")
	for arena_id: StringName in [&"stage_01", &"stage_02", &"stage_03", &"stage_04", &"stage_05", &"stage_06", &"stage_07"]:
		_check(ArenaCatalog.get_background_texture(arena_id) != null, "%s artwork did not load" % arena_id)
	_check(ArenaCatalog.get_background_texture(&"missing_stage") == null, "missing artwork must use fallback")

	_test_cover_scaling()
	await _test_runtime_arena(JOE, JENNIFER, &"stage_01", false)
	await _test_runtime_arena(PEGGY, FUJIYAMA, &"stage_02", false)
	await _test_runtime_arena(JENNIFER, FRANK, &"stage_03", false)
	await _test_runtime_arena(OKAMURA, YAMASHITA, &"stage_04", false)
	await _test_runtime_arena(YAMASHITA, JOE, &"stage_04", false)
	await _test_runtime_arena(JOE, OKAMURA, &"stage_05", false)
	await _test_runtime_arena(JOE, PEGGY, &"stage_06", false)
	await _test_runtime_arena(JOE, NURSE, &"stage_07", false)
	await _test_default_test_arena()

	var game_session: Node = root.get_node("GameSession")
	game_session.clear_campaign()
	if failures.is_empty():
		print("PASS all opponent-bound arenas, shared stage_04, fallback safety, responsive cover, layering, and mobile safe zone")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_cover_scaling() -> void:
	var source_size := Vector2(1672.0, 941.0)
	for target_size: Vector2 in [
		Vector2(1152.0, 648.0),
		Vector2(1296.0, 648.0),
		Vector2(1404.0, 648.0),
		Vector2(1440.0, 648.0),
	]:
		var cover_scale: float = maxf(target_size.x / source_size.x, target_size.y / source_size.y)
		var drawn_size: Vector2 = source_size * cover_scale
		_check(drawn_size.x + 0.01 >= target_size.x, "cover scaling exposes a horizontal border at %s" % target_size)
		_check(drawn_size.y + 0.01 >= target_size.y, "cover scaling exposes a vertical border at %s" % target_size)


func _test_runtime_arena(
	player: CharacterData,
	opponent: CharacterData,
	expected_arena_id: StringName,
	expect_fallback: bool
) -> void:
	var game_session: Node = root.get_node("GameSession")
	game_session.clear_campaign()
	game_session.selected_player_character = player
	game_session.selected_cpu_character = opponent
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	await process_frame

	var presentation: ArenaBackground = arena.get_node("ArenaBackground/Presentation") as ArenaBackground
	var fighter_1: Fighter = arena.get_node("Fighter1") as Fighter
	var fighter_2: Fighter = arena.get_node("Fighter2") as Fighter
	var mobile_controls: CanvasLayer = arena.get_node("MobileControls") as CanvasLayer
	var control_zone: Control = arena.get_node("MobileControls/Layout/ControlZone") as Control
	_check(fighter_1.character_data == player, "selected player was not applied at match startup")
	_check(fighter_2.character_data == opponent, "selected opponent was not applied at match startup")
	_check(presentation.active_arena_id == expected_arena_id, "opponent did not select %s" % expected_arena_id)
	_check(presentation.is_using_fallback() == expect_fallback, "%s fallback state is wrong" % expected_arena_id)
	_check((arena.get_node("ArenaBackground") as CanvasLayer).layer < 0, "arena artwork is not behind fighters")
	_check((arena.get_node("HUD") as CanvasLayer).layer > 0, "HUD is not above fighters")
	_check(mobile_controls.layer > (arena.get_node("HUD") as CanvasLayer).layer, "mobile controls are not above the HUD/background")
	_check(presentation.get_rect().end.y <= control_zone.position.y + 0.01, "stage artwork overlaps the mobile control zone")
	_check(fighter_1.sprite_root.scale.is_equal_approx(Vector2.ONE * player.visual_scale), "arena changed player visual scale")
	_check(fighter_2.sprite_root.scale.is_equal_approx(Vector2.ONE * opponent.visual_scale), "arena changed opponent visual scale")
	var floor_shape: RectangleShape2D = (arena.get_node("Floor/CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	_check(floor_shape != null and floor_shape.size == Vector2(1152.0, 64.0), "arena changed the gameplay floor shape")
	_check((arena.get_node("LeftBoundary") as StaticBody2D).position == Vector2(-32.0, 324.0), "arena changed the left gameplay bound")
	_check((arena.get_node("RightBoundary") as StaticBody2D).position == Vector2(1184.0, 324.0), "arena changed the right gameplay bound")

	arena.queue_free()
	await process_frame


func _test_default_test_arena() -> void:
	var game_session: Node = root.get_node("GameSession")
	game_session.clear_campaign()
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	await process_frame
	var presentation: ArenaBackground = arena.get_node("ArenaBackground/Presentation") as ArenaBackground
	_check(presentation.active_arena_id == &"stage_04", "default P2 must select Yamashita's home arena")
	_check(not presentation.is_using_fallback(), "default P2's stage_04 artwork did not load")
	var invalid_opponent := CharacterData.new()
	invalid_opponent.home_arena_id = &"missing_stage"
	presentation.configure_for_opponent(invalid_opponent)
	_check(presentation.active_arena_id == ArenaCatalog.DEFAULT_ARENA_ID, "invalid opponent arena must select default")
	_check(presentation.is_using_fallback(), "invalid opponent arena must display fallback")
	arena.queue_free()
	await process_frame
