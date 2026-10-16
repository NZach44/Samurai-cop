extends SceneTree

const LADDER_SCENE: PackedScene = preload("res://scenes/ui/campaign_ladder.tscn")
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
	var game_session: Node = root.get_node("GameSession")
	_check(game_session.begin_campaign(FIGHTERS[0], FIGHTERS), "campaign setup failed")

	var ladder: Control = LADDER_SCENE.instantiate() as Control
	ladder.auto_advance = false
	root.add_child(ladder)
	await process_frame
	await process_frame

	_check(is_equal_approx(ladder.preview_duration, 4.0), "ladder preview must last four seconds")
	_check(ladder.opponent_cards.size() == 7, "ladder must show all seven opponents")
	_check(ladder.current_step == 0, "new campaign must begin on the first step")
	_check(ladder.player_marker != null, "player marker is missing")
	_check(ladder.step_centers.size() == 7, "ladder path must contain seven steps")
	_check(
		ladder.get_node("%NextOpponentLabel").text.contains(game_session.selected_cpu_character.display_name.to_upper()),
		"ladder does not identify the selected CPU opponent"
	)
	for index: int in ladder.opponent_cards.size():
		var card: PanelContainer = ladder.opponent_cards[index]
		var row: HBoxContainer = card.get_child(0) as HBoxContainer
		var portrait: TextureRect = row.get_child(0) as TextureRect
		_check(portrait.texture != null, "opponent %d portrait is missing" % (index + 1))
	for viewport_width: int in [1152, 1296, 1404, 1440]:
		root.size = Vector2i(viewport_width, 648)
		await process_frame
		ladder.call("_layout_ladder")
		var path_layer: Control = ladder.get_node("%PathLayer") as Control
		for card: PanelContainer in ladder.opponent_cards:
			_check(
				Rect2(Vector2.ZERO, path_layer.size).encloses(Rect2(card.position, card.size)),
				"opponent card leaves the ladder at %dx648" % viewport_width
			)
		_check(
			Rect2(Vector2.ZERO, path_layer.size).encloses(
				Rect2(ladder.player_marker.position, ladder.player_marker.size)
			),
			"player marker leaves the ladder at %dx648" % viewport_width
		)

	ladder.queue_free()
	await process_frame
	_check(game_session.advance_campaign(), "campaign did not advance")

	var advanced_ladder: Control = LADDER_SCENE.instantiate() as Control
	advanced_ladder.auto_advance = false
	root.add_child(advanced_ladder)
	await process_frame
	await process_frame
	_check(advanced_ladder.current_step == 1, "player marker did not climb after a victory")
	var defeated_status: Label = advanced_ladder.opponent_cards[0].find_child("Status", true, false) as Label
	var current_status: Label = advanced_ladder.opponent_cards[1].find_child("Status", true, false) as Label
	_check(defeated_status.text == "DEFEATED", "completed opponent is not marked defeated")
	_check(current_status.text == "NEXT OPPONENT", "new opponent is not highlighted")

	advanced_ladder.queue_free()
	game_session.clear_campaign()
	await process_frame
	if failures.is_empty():
		print("PASS campaign ladder roster, portraits, progress, and four-second timing")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
