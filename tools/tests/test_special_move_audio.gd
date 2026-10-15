extends SceneTree

const FIGHTER_SCENE: PackedScene = preload("res://scenes/fighters/fighter.tscn")
const FRANK: CharacterData = preload("res://data/fighters/frank_washington.tres")
const JOE: CharacterData = preload("res://data/fighters/joe_marshall.tres")
const FRANK_SPECIAL_1: SpecialMoveData = preload("res://data/moves/frank_special_1.tres")
const FRANK_SPECIAL_2: SpecialMoveData = preload("res://data/moves/frank_special_2.tres")
const FUJIYAMA_SPECIAL_1: SpecialMoveData = preload("res://data/moves/fujiyama_special_1.tres")
const FUJIYAMA_SPECIAL_2: SpecialMoveData = preload("res://data/moves/fujiyama_special_2.tres")
const JOE_SPECIAL_2: SpecialMoveData = preload("res://data/fighters/joe_special_2.tres")
const NURSE_SPECIAL_1: SpecialMoveData = preload("res://data/moves/nurse_special_1.tres")
const NURSE_SPECIAL_2: SpecialMoveData = preload("res://data/moves/nurse_special_2.tres")
const PEGGY_SPECIAL_1: SpecialMoveData = preload("res://data/moves/peggy_special_1.tres")
const JOE_SPECIAL_1: SpecialMoveData = preload("res://data/fighters/joe_special_1.tres")
const GENERIC_SPECIAL_AUDIO: AudioStream = preload("res://assets/audio/voice/special_move.mp3")

var failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	_test_resources()
	await _test_runtime_playback()
	if failures.is_empty():
		print("PASS specific and fallback special audio, parallel fighters, and same-fighter restart")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_resources() -> void:
	_check(AudioServer.get_bus_index(&"Voice") >= 0, "Voice audio bus is missing")
	_check_specific_audio(FRANK_SPECIAL_1, "res://assets/characters/frank_washington/audio/special1.ogg", "Frank Special 1")
	_check_specific_audio(FRANK_SPECIAL_2, "res://assets/characters/frank_washington/audio/special2.ogg", "Frank Special 2")
	_check_specific_audio(FUJIYAMA_SPECIAL_1, "res://assets/characters/fujiyama/audio/special1.ogg", "Fujiyama Special 1")
	_check_specific_audio(FUJIYAMA_SPECIAL_2, "res://assets/characters/fujiyama/audio/special2.ogg", "Fujiyama Special 2")
	_check_specific_audio(JOE_SPECIAL_2, "res://assets/characters/joe_marshall/audio/special2.ogg", "Joe Special 2")
	_check_specific_audio(NURSE_SPECIAL_1, "res://assets/characters/nurse/audio/special1.ogg", "Wild Nurse Special 1")
	_check_specific_audio(NURSE_SPECIAL_2, "res://assets/characters/nurse/audio/special2.ogg", "Wild Nurse Special 2")
	_check_specific_audio(PEGGY_SPECIAL_1, "res://assets/characters/peggy/audio/special1.ogg", "Peggy Special 1")
	_check(JOE_SPECIAL_1.activation_audio == null, "Joe Special 1 should exercise the generic fallback")
	_check(GENERIC_SPECIAL_AUDIO.get_length() > 0.0, "generic special audio is empty")


func _check_specific_audio(move: SpecialMoveData, expected_path: String, label: String) -> void:
	_check(move.activation_audio != null, "%s audio is not assigned" % label)
	if move.activation_audio == null:
		return
	_check(move.activation_audio.resource_path == expected_path, "%s uses the wrong audio" % label)
	_check(move.activation_audio.get_length() > 0.0, "%s audio is empty" % label)


func _test_runtime_playback() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var fighter_1: Fighter = FIGHTER_SCENE.instantiate() as Fighter
	var fighter_2: Fighter = FIGHTER_SCENE.instantiate() as Fighter
	fighter_1.character_data = FRANK
	fighter_2.character_data = JOE
	world.add_child(fighter_1)
	world.add_child(fighter_2)
	fighter_1.set_physics_process(false)
	fighter_2.set_physics_process(false)
	var player_1: AudioStreamPlayer = fighter_1.get_node("SpecialVoicePlayer") as AudioStreamPlayer
	var player_2: AudioStreamPlayer = fighter_2.get_node("SpecialVoicePlayer") as AudioStreamPlayer
	_check(player_1 != player_2, "fighters incorrectly share one special audio player")
	_check(player_1.bus == &"Voice" and player_2.bus == &"Voice", "special audio is not routed to Voice")

	fighter_1.request_special(1)
	fighter_2.request_special(1)
	await process_frame
	_check(player_1.playing, "Frank Special 1 did not start its audio")
	_check(player_1.stream == FRANK_SPECIAL_1.activation_audio, "Frank Special 1 did not use its specific audio")
	_check(player_2.playing, "Joe's unassigned Special 1 did not start fallback audio")
	_check(player_2.stream == GENERIC_SPECIAL_AUDIO, "unassigned special did not use the generic fallback")
	_check(player_1.playing and player_2.playing, "opposing fighters' special audio did not overlap")

	await create_timer(
		FRANK_SPECIAL_1.startup_time
		+ FRANK_SPECIAL_1.active_time
		+ FRANK_SPECIAL_1.recovery_time
		+ 0.08
	).timeout
	_check(player_1.playing, "Frank's clip ended before the move could be repeated")
	var position_before_restart: float = player_1.get_playback_position()
	fighter_1.request_special(1)
	await process_frame
	var position_after_restart: float = player_1.get_playback_position()
	_check(player_1.playing, "repeated Frank Special 1 stopped its audio")
	_check(player_1.stream == FRANK_SPECIAL_1.activation_audio, "repeated Frank Special 1 changed streams")
	_check(
		position_after_restart <= position_before_restart,
		"repeated Frank Special 1 did not restart audio from the beginning"
	)

	fighter_1.reset_for_round(Vector2.ZERO)
	_check(not player_1.playing, "round reset did not stop special audio")
	player_2.stop()
	player_1.stream = null
	player_2.stream = null
	current_scene = null
	world.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
