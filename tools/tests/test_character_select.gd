extends SceneTree

const CHARACTER_SELECT: PackedScene = preload("res://scenes/ui/character_select.tscn")
const FIGHTERS: Array[CharacterData] = [
	preload("res://data/fighters/joe_marshall.tres"),
	preload("res://data/fighters/frank_washington.tres"),
	preload("res://data/fighters/fujiyama.tres"),
	preload("res://data/fighters/yamashita.tres"),
	preload("res://data/fighters/okamura.tres"),
	preload("res://data/fighters/jennifer.tres"),
	preload("res://data/fighters/peggy.tres"),
	preload("res://data/fighters/nurse.tres"),
]

var failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	root.size = Vector2i(1152, 648)
	var screen: Control = CHARACTER_SELECT.instantiate() as Control
	root.add_child(screen)
	await process_frame

	var grid: GridContainer = screen.get_node("%CharacterGrid") as GridContainer
	var preview: TextureRect = screen.get_node("%Preview") as TextureRect
	var selected_name: Label = screen.get_node("%SelectedNameLabel") as Label
	var game_title: Label = screen.get_node("Margin/MainColumn/Title") as Label
	var selection_title: Label = screen.get_node("Margin/MainColumn/SelectionTitle") as Label
	var special_instructions: Label = screen.get_node("Margin/MainColumn/SpecialInstructions") as Label
	var easy_button: Button = screen.get_node("%EasyButton") as Button
	var music: AudioStreamPlayer = screen.get_node("SelectionMusic") as AudioStreamPlayer
	_check(game_title.text == "Samurai Cop: the game", "game title must be displayed")
	_check(selection_title.text == "CHOOSE YOUR PLAYER", "selection heading must be displayed")
	_check(
		special_instructions.text.contains("FORWARD, FORWARD, PUNCH (J)"),
		"Special 1 keyboard command is not shown"
	)
	_check(
		special_instructions.text.contains("DOWN, FORWARD, KICK (K)"),
		"Special 2 keyboard command is not shown"
	)
	_check(_action_uses_physical_key(&"p1_punch", KEY_J), "P1 punch must use J")
	_check(_action_uses_physical_key(&"p1_kick", KEY_K), "P1 kick must use K")
	_check(_action_uses_physical_key(&"p1_block", KEY_L), "P1 block must use L")
	_check(not _action_uses_physical_key(&"p1_punch", KEY_F), "P1 punch must no longer use F")
	_check(not _action_uses_physical_key(&"p1_kick", KEY_G), "P1 kick must no longer use G")
	_check(not _action_uses_physical_key(&"p1_block", KEY_H), "P1 block must no longer use H")
	_check(screen.selected_difficulty_index == 0, "character select must default to Easy")
	_check(easy_button.button_pressed, "Easy difficulty button is not initially selected")
	var game_session: Node = root.get_node("GameSession")
	game_session.clear_campaign()
	_check(game_session.selected_difficulty.profile_name == "EASY", "GameSession fallback difficulty must be Easy")
	_check(AudioServer.get_bus_index(&"Music") >= 0, "Music audio bus is missing")
	_check(music.bus == &"Music", "selection theme is not routed to Music")
	_check(music.stream != null, "selection theme is missing")
	if music.stream != null:
		_check(
			music.stream.resource_path == "res://assets/audio/music/retro_action_theme.ogg",
			"selection screen uses the wrong theme"
		)
		var music_stream := music.stream as AudioStreamOggVorbis
		_check(music_stream != null and music_stream.loop, "selection theme is not looping")
	screen.call("_start_selection_music")
	await process_frame
	_check(music.playing, "selection theme did not start")
	_check(grid.get_child_count() == FIGHTERS.size(), "roster must create one card per fighter")
	_check(grid.columns == 4, "roster must remain a 4x2 grid")

	for fighter: CharacterData in FIGHTERS:
		_check(fighter.profile_portrait != null, "%s profile portrait is missing" % fighter.display_name)
		if fighter.profile_portrait != null:
			_check(
				fighter.profile_portrait.get_size() == Vector2(512.0, 512.0),
				"%s profile portrait must be 512x512" % fighter.display_name
			)

	_check(preview.texture == FIGHTERS[0].profile_portrait, "initial preview must use Joe's profile portrait")
	screen.call("_select_character", 5)
	_check(selected_name.text == "Jennifer", "selection must update the displayed fighter name")
	_check(preview.texture == FIGHTERS[5].profile_portrait, "selection must update the large portrait")
	screen.call("_select_character", 7)
	_check(selected_name.text == "Wild Nurse", "last roster entry must remain selectable")

	_check(screen.get_combined_minimum_size().x <= 1152.0, "screen minimum width exceeds the development viewport")
	_check(screen.get_combined_minimum_size().y <= 648.0, "screen minimum height exceeds the development viewport")

	screen.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	if failures.is_empty():
		print("PASS character select controls, special instructions, profiles, roster, music, and layout")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _action_uses_physical_key(action: StringName, key: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		var key_event := event as InputEventKey
		if key_event != null and key_event.physical_keycode == key:
			return true
	return false
