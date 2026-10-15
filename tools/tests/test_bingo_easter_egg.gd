extends SceneTree

const ARENA_SCENE: PackedScene = preload("res://scenes/arenas/test_arena.tscn")
const JOE: CharacterData = preload("res://data/fighters/joe_marshall.tres")
const NURSE: CharacterData = preload("res://data/fighters/nurse.tres")
const NURSE_SPECIAL_2: SpecialMoveData = preload("res://data/moves/nurse_special_2.tres")
const LONG_SPECIAL_AUDIO: SpecialMoveData = preload("res://data/moves/peggy_special_1.tres")

var failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	_test_bingo_portrait()
	var game_session: Node = root.get_node("GameSession")
	game_session.clear_campaign()
	game_session.selected_player_character = NURSE
	game_session.selected_cpu_character = JOE
	var arena = ARENA_SCENE.instantiate()
	arena.round_number = 2
	arena.intro_start_delay = 0.0
	arena.round_message_duration = 0.01
	arena.fight_message_duration = 0.01
	root.add_child(arena)
	current_scene = arena

	var nurse: Fighter = arena.get_node("Fighter1") as Fighter
	var joe: Fighter = arena.get_node("Fighter2") as Fighter
	nurse.set_physics_process(false)
	joe.set_physics_process(false)
	var nurse_voice: AudioStreamPlayer = nurse.get_node("SpecialVoicePlayer") as AudioStreamPlayer
	var other_voice: AudioStreamPlayer = joe.get_node("SpecialVoicePlayer") as AudioStreamPlayer
	var bingo_voice: AudioStreamPlayer = arena.get_node("BingoVoicePlayer") as AudioStreamPlayer
	var popout: TextureRect = arena.get_node("BingoOverlay/Controls/BingoPopout") as TextureRect
	var overlay: CanvasLayer = arena.get_node("BingoOverlay") as CanvasLayer
	_check(overlay.layer > 20, "Bingo portrait is not above mobile controls")
	_check(popout.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Bingo portrait blocks touch input")
	_check(arena._is_nurse_versus_joe(nurse), "Nurse P1 versus Joe P2 is not recognized")

	# The matchup predicate must remain orientation-independent.
	nurse.character_data = JOE
	joe.character_data = NURSE
	_check(arena._is_nurse_versus_joe(joe), "Joe P1 versus Nurse P2 is not recognized")
	nurse.character_data = NURSE
	joe.character_data = JOE

	other_voice.stop()
	joe._play_special_audio(LONG_SPECIAL_AUDIO)
	nurse._play_special_audio(NURSE_SPECIAL_2)
	await process_frame
	_check(nurse_voice.playing, "Nurse Special 2 audio did not start")
	_check(not popout.visible and not bingo_voice.playing, "Bingo triggered before Nurse audio ended")

	var deadline_ms: int = Time.get_ticks_msec() + 3000
	while not bingo_voice.playing and Time.get_ticks_msec() < deadline_ms:
		await process_frame
	_check(not nurse_voice.playing, "Bingo triggered before Nurse Special 2 audio finished")
	_check(bingo_voice.playing, "Bingo audio did not start after Nurse Special 2 audio")
	_check(popout.visible, "Bingo portrait did not pop out")
	_check(other_voice.playing, "Bingo audio interrupted the other fighter's audio")
	_check(bingo_voice.bus == &"Voice", "Bingo audio is not routed to Voice")
	_check(
		bingo_voice.stream.resource_path == "res://assets/characters/joe_marshall/audio/special2.ogg",
		"Bingo event uses the wrong audio"
	)
	_check(
		popout.texture.resource_path == "res://assets/characters/joe_marshall/effects/bingo_popout.png",
		"Bingo event uses the wrong portrait"
	)

	deadline_ms = Time.get_ticks_msec() + 2500
	while popout.visible and Time.get_ticks_msec() < deadline_ms:
		await process_frame
	_check(not popout.visible, "Bingo portrait did not retract")

	nurse_voice.stop()
	other_voice.stop()
	bingo_voice.stop()
	current_scene = null
	arena.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	game_session.clear_campaign()
	if failures.is_empty():
		print("PASS Nurse/Joe Bingo timing, orientation, pop-out, and overlapping audio")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_bingo_portrait() -> void:
	var path := "res://assets/characters/joe_marshall/effects/bingo_popout.png"
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	_check(image != null and not image.is_empty(), "Bingo portrait is missing")
	if image == null or image.is_empty():
		return
	_check(image.get_size() == Vector2i(512, 512), "Bingo portrait must remain 512x512")
	_check(image.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_RGBAF], "Bingo portrait is not RGBA")
	var used_rect: Rect2i = image.get_used_rect()
	_check(used_rect.size.x >= 440 and used_rect.size.y >= 400, "Bingo portrait silhouette is incomplete")
	for x: int in image.get_width():
		_check(image.get_pixel(x, 0).a == 0.0, "Bingo portrait alpha touches the top edge")
		_check(image.get_pixel(x, image.get_height() - 1).a == 0.0, "Bingo portrait alpha touches the bottom edge")
	for y: int in image.get_height():
		_check(image.get_pixel(0, y).a == 0.0, "Bingo portrait alpha touches the left edge")
		_check(image.get_pixel(image.get_width() - 1, y).a == 0.0, "Bingo portrait alpha touches the right edge")
