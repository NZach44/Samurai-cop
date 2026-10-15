extends SceneTree

const ARENA_SCENE: PackedScene = preload("res://scenes/arenas/test_arena.tscn")
const JOE: CharacterData = preload("res://data/fighters/joe_marshall.tres")
const FRANK: CharacterData = preload("res://data/fighters/frank_washington.tres")
const YAMASHITA: CharacterData = preload("res://data/fighters/yamashita.tres")
const FUJIYAMA: CharacterData = preload("res://data/fighters/fujiyama.tres")
const JENNIFER: CharacterData = preload("res://data/fighters/jennifer.tres")
const PEGGY: CharacterData = preload("res://data/fighters/peggy.tres")
const OKAMURA: CharacterData = preload("res://data/fighters/okamura.tres")
const NURSE: CharacterData = preload("res://data/fighters/nurse.tres")

var failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	_test_character_resources()
	await _test_audio_driven_order()
	await _test_later_round_skips_intros()
	await _test_restart_during_intro()
	await _test_missing_audio_fallback()

	var game_session: Node = root.get_node("GameSession")
	game_session.clear_campaign()
	if failures.is_empty():
		print("PASS first-round-only intros, sequential timing, input lock, and missing-audio fallback")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_character_resources() -> void:
	var expected_quotes: Dictionary = {
		JOE: "It means Japanese sword",
		FRANK: "Because I'm an undercover cop",
		YAMASHITA: "... and then we will see who the real samurai is",
		FUJIYAMA: "So they call him SAMURAI, HUH",
		JENNIFER: "How did you know I'd come home with you?",
		PEGGY: "Let's use it before you lose it",
		OKAMURA: "Fight me like a man!",
		NURSE: "Do you like what you see?",
	}
	for character: CharacterData in expected_quotes:
		_check(character.intro_text == expected_quotes[character], "%s intro quote changed" % character.display_name)
		_check(character.intro_audio != null, "%s intro audio is missing" % character.display_name)
		if character.intro_audio != null:
			_check(character.intro_audio.get_length() > 0.0, "%s intro audio has no duration" % character.display_name)
	_check(AudioServer.get_bus_index(&"Voice") >= 0, "Voice audio bus is missing")


func _test_audio_driven_order() -> void:
	var game_session: Node = root.get_node("GameSession")
	game_session.clear_campaign()
	game_session.selected_player_character = JOE
	game_session.selected_cpu_character = PEGGY
	var arena = ARENA_SCENE.instantiate()
	arena.round_message_duration = 0.05
	arena.fight_message_duration = 0.05
	root.add_child(arena)
	current_scene = arena
	await process_frame

	var fighter_1: Fighter = arena.get_node("Fighter1") as Fighter
	var fighter_2: Fighter = arena.get_node("Fighter2") as Fighter
	var voice: AudioStreamPlayer = arena.get_node("IntroVoicePlayer") as AudioStreamPlayer
	var bubble: PanelContainer = arena.get_node("HUD/Controls/IntroBubble") as PanelContainer
	var label: Label = arena.get_node("HUD/Controls/IntroBubble/Label") as Label
	var round_label: Label = arena.get_node("HUD/Controls/WinnerLabel") as Label
	_check(voice.bus == &"Voice", "intro player is not routed to Voice")
	_check(not fighter_1.controls_enabled and not fighter_2.controls_enabled, "fighters are enabled before intros")

	var saw_p1: bool = false
	var saw_p2: bool = false
	var p1_finished_ms: int = -1
	var p2_started_ms: int = -1
	var p2_finished_ms: int = -1
	var round_started_ms: int = -1
	var was_playing: bool = false
	var previous_stream: AudioStream = null
	var deadline_ms: int = Time.get_ticks_msec() + 15000
	while arena.match_state != arena.MatchState.FIGHTING and Time.get_ticks_msec() < deadline_ms:
		await process_frame
		if arena.match_state != arena.MatchState.FIGHTING:
			_check(not fighter_1.controls_enabled and not fighter_2.controls_enabled, "combat enabled during intro/ROUND/FIGHT sequence")
		if voice.playing:
			_check(bubble.visible, "intro bubble hidden while voice is playing")
			if voice.stream == JOE.intro_audio:
				saw_p1 = true
				_check(label.text == JOE.intro_text, "P1 voice used the wrong quote bubble")
			elif voice.stream == PEGGY.intro_audio:
				if not saw_p2:
					p2_started_ms = Time.get_ticks_msec()
				saw_p2 = true
				_check(label.text == PEGGY.intro_text, "P2 voice used the wrong quote bubble")
			else:
				_check(false, "unexpected intro stream played")
			if previous_stream != null and voice.stream != previous_stream:
				_check(not was_playing, "P1 and P2 intro voices overlapped")
			previous_stream = voice.stream
		elif was_playing:
			if saw_p2:
				p2_finished_ms = Time.get_ticks_msec()
			elif saw_p1:
				p1_finished_ms = Time.get_ticks_msec()
		if p2_finished_ms >= 0 and round_started_ms < 0 and round_label.visible and round_label.text.begins_with("ROUND"):
			round_started_ms = Time.get_ticks_msec()
		was_playing = voice.playing

	_check(saw_p1, "P1 intro audio never played")
	_check(saw_p2, "P2 intro audio never played")
	_check(arena.match_state == arena.MatchState.FIGHTING, "match did not reach FIGHTING after intros")
	_check(fighter_1.controls_enabled and fighter_2.controls_enabled, "fighters were not enabled after FIGHT")
	_check(p1_finished_ms >= 0 and p2_started_ms >= 0, "could not observe the P1-to-P2 pause")
	if p1_finished_ms >= 0 and p2_started_ms >= 0:
		var p1_gap: float = float(p2_started_ms - p1_finished_ms) / 1000.0
		_check(p1_gap >= 0.45 and p1_gap <= 0.65, "P1-to-P2 pause was %.3f seconds" % p1_gap)
	_check(p2_finished_ms >= 0 and round_started_ms >= 0, "could not observe the P2-to-ROUND pause")
	if p2_finished_ms >= 0 and round_started_ms >= 0:
		var p2_gap: float = float(round_started_ms - p2_finished_ms) / 1000.0
		_check(p2_gap >= 0.45 and p2_gap <= 0.65, "P2-to-ROUND pause was %.3f seconds" % p2_gap)

	arena.queue_free()
	await process_frame


func _test_later_round_skips_intros() -> void:
	var game_session: Node = root.get_node("GameSession")
	game_session.clear_campaign()
	game_session.selected_player_character = JOE
	game_session.selected_cpu_character = PEGGY
	var arena = ARENA_SCENE.instantiate()
	arena.round_number = 2
	arena.intro_start_delay = 0.0
	arena.round_message_duration = 0.01
	arena.fight_message_duration = 0.01
	root.add_child(arena)
	current_scene = arena
	var voice: AudioStreamPlayer = arena.get_node("IntroVoicePlayer") as AudioStreamPlayer
	var bubble: PanelContainer = arena.get_node("HUD/Controls/IntroBubble") as PanelContainer
	var heard_intro: bool = false
	var saw_intro_bubble: bool = false
	var deadline_ms: int = Time.get_ticks_msec() + 2000
	while arena.match_state != arena.MatchState.FIGHTING and Time.get_ticks_msec() < deadline_ms:
		await process_frame
		heard_intro = heard_intro or voice.playing
		saw_intro_bubble = saw_intro_bubble or bubble.visible
	_check(arena.match_state == arena.MatchState.FIGHTING, "round 2 did not reach FIGHTING")
	_check(not heard_intro, "intro voice repeated in round 2")
	_check(not saw_intro_bubble, "intro quote repeated in round 2")
	arena.queue_free()
	await process_frame


func _test_missing_audio_fallback() -> void:
	var silent_p1: CharacterData = JOE.duplicate(true) as CharacterData
	var silent_p2: CharacterData = PEGGY.duplicate(true) as CharacterData
	silent_p1.intro_audio = null
	silent_p2.intro_audio = null
	var game_session: Node = root.get_node("GameSession")
	game_session.clear_campaign()
	game_session.selected_player_character = silent_p1
	game_session.selected_cpu_character = silent_p2
	var arena = ARENA_SCENE.instantiate()
	_check(is_equal_approx(arena.intro_fallback_duration, 3.0), "missing-audio fallback is not three seconds")
	arena.intro_fallback_duration = 0.15
	arena.intro_start_delay = 0.0
	arena.round_message_duration = 0.01
	arena.fight_message_duration = 0.01
	root.add_child(arena)
	current_scene = arena
	var fighter_1: Fighter = arena.get_node("Fighter1") as Fighter
	var fighter_2: Fighter = arena.get_node("Fighter2") as Fighter
	var bubble: PanelContainer = arena.get_node("HUD/Controls/IntroBubble") as PanelContainer
	var label: Label = arena.get_node("HUD/Controls/IntroBubble/Label") as Label
	var saw_p1_quote: bool = false
	var saw_p2_quote: bool = false
	var deadline_ms: int = Time.get_ticks_msec() + 3000
	while arena.match_state != arena.MatchState.FIGHTING and Time.get_ticks_msec() < deadline_ms:
		await process_frame
		if bubble.visible and label.text == silent_p1.intro_text:
			saw_p1_quote = true
		if bubble.visible and label.text == silent_p2.intro_text:
			saw_p2_quote = true
		if arena.match_state != arena.MatchState.FIGHTING:
			_check(not fighter_1.controls_enabled and not fighter_2.controls_enabled, "combat enabled during missing-audio fallback")
	_check(arena.match_state == arena.MatchState.FIGHTING, "missing intro audio blocked match startup")
	_check(fighter_1.controls_enabled and fighter_2.controls_enabled, "controls stayed locked after missing-audio fallback")
	_check(saw_p1_quote and saw_p2_quote, "missing-audio fallback did not show both quotes")
	arena.queue_free()
	await process_frame


func _test_restart_during_intro() -> void:
	var game_session: Node = root.get_node("GameSession")
	game_session.clear_campaign()
	game_session.selected_player_character = JOE
	game_session.selected_cpu_character = PEGGY
	var arena = ARENA_SCENE.instantiate()
	arena.intro_start_delay = 0.0
	root.add_child(arena)
	current_scene = arena
	var voice: AudioStreamPlayer = arena.get_node("IntroVoicePlayer") as AudioStreamPlayer
	var deadline_ms: int = Time.get_ticks_msec() + 2000
	while not voice.playing and Time.get_ticks_msec() < deadline_ms:
		await process_frame
	_check(voice.playing and voice.stream == JOE.intro_audio, "restart test did not reach P1 intro")
	var previous_sequence_id: int = arena.intro_sequence_id
	arena._start_round()
	_check(arena.intro_sequence_id == previous_sequence_id + 1, "restart did not invalidate the old intro sequence")
	_check(not voice.playing and voice.stream == null, "restart did not stop and clear the old intro voice")
	deadline_ms = Time.get_ticks_msec() + 2000
	while not voice.playing and Time.get_ticks_msec() < deadline_ms:
		await process_frame
	_check(voice.playing and voice.stream == JOE.intro_audio, "restart did not begin a fresh P1 intro")
	arena.queue_free()
	await process_frame
	_check(not is_instance_valid(voice), "intro player survived arena teardown")
