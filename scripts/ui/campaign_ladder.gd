extends Control

const ARENA_SCENE: String = "res://scenes/arenas/test_arena.tscn"
const CHARACTER_SELECT_SCENE: String = "res://scenes/ui/character_select.tscn"
const OPPONENT_CARD_SIZE: Vector2 = Vector2(218.0, 64.0)
const PLAYER_CARD_SIZE: Vector2 = Vector2(176.0, 64.0)

@export_range(0.1, 10.0, 0.1) var preview_duration: float = 4.0
@export var auto_advance: bool = true

@onready var path_layer: Control = %PathLayer
@onready var route_shadow: Line2D = %RouteShadow
@onready var route_line: Line2D = %RouteLine
@onready var progress_label: Label = %ProgressLabel
@onready var next_opponent_label: Label = %NextOpponentLabel

var opponent_cards: Array[PanelContainer] = []
var player_marker: PanelContainer
var step_centers: PackedVector2Array = PackedVector2Array()
var current_step: int = 0


func _ready() -> void:
	var game_session: Node = get_node_or_null("/root/GameSession")
	if game_session == null or not game_session.is_campaign_active():
		push_warning("Campaign ladder opened without an active campaign; returning to character select.")
		if auto_advance:
			call_deferred("_return_to_character_select")
		return

	current_step = game_session.current_campaign_index
	_build_ladder(game_session)
	resized.connect(_layout_ladder)
	call_deferred("_layout_ladder")
	if auto_advance:
		_show_then_start_fight()


func _build_ladder(game_session: Node) -> void:
	progress_label.text = "FIGHT %d OF %d" % [
		current_step + 1,
		game_session.campaign_opponents.size(),
	]
	next_opponent_label.text = "NEXT: %s" % game_session.selected_cpu_character.display_name.to_upper()

	for index: int in game_session.campaign_opponents.size():
		var opponent: CharacterData = game_session.campaign_opponents[index]
		var card: PanelContainer = _create_opponent_card(opponent, index)
		path_layer.add_child(card)
		opponent_cards.append(card)

	player_marker = _create_player_marker(game_session.selected_player_character)
	path_layer.add_child(player_marker)


func _create_opponent_card(character: CharacterData, index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Opponent%02d" % (index + 1)
	card.custom_minimum_size = OPPONENT_CARD_SIZE
	card.size = OPPONENT_CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", _opponent_style(index))
	if index < current_step:
		card.modulate = Color(0.48, 0.52, 0.6, 0.76)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(60.0, 60.0)
	portrait.texture = _get_profile_texture(character)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.alignment = BoxContainer.ALIGNMENT_CENTER
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_column)

	var name_label := Label.new()
	name_label.text = character.display_name.to_upper()
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color("fff0bd"))
	name_label.add_theme_color_override("font_outline_color", Color("150b18"))
	name_label.add_theme_constant_override("outline_size", 2)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(name_label)

	var status_label := Label.new()
	status_label.name = "Status"
	status_label.text = _step_status(index)
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override(
		"font_color",
		Color("ffcf45") if index == current_step else Color("91b7dd")
	)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(status_label)
	return card


func _create_player_marker(character: CharacterData) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "PlayerMarker"
	card.custom_minimum_size = PLAYER_CARD_SIZE
	card.size = PLAYER_CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override(
		"panel",
		_make_style(Color("173e70"), Color("5dd8ff"), 4, 10)
	)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(60.0, 60.0)
	portrait.texture = _get_profile_texture(character)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)

	var label := Label.new()
	label.text = "YOU\n%s" % character.display_name.to_upper()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("dff8ff"))
	label.add_theme_color_override("font_outline_color", Color("071224"))
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return card


func _layout_ladder() -> void:
	if opponent_cards.is_empty() or not is_instance_valid(player_marker):
		return
	var area: Vector2 = path_layer.size
	if area.x <= 0.0 or area.y <= 0.0:
		return

	step_centers.clear()
	var top_margin: float = 4.0
	var usable_height: float = maxf(area.y - OPPONENT_CARD_SIZE.y - top_margin * 2.0, 1.0)
	var step_gap: float = usable_height / maxf(float(opponent_cards.size() - 1), 1.0)
	var horizontal_swing: float = minf(area.x * 0.11, 108.0)
	var lane_center: float = area.x * 0.54

	for index: int in opponent_cards.size():
		var card: PanelContainer = opponent_cards[index]
		var center_x: float = lane_center + (-horizontal_swing if index % 2 == 0 else horizontal_swing)
		var y: float = area.y - OPPONENT_CARD_SIZE.y - top_margin - step_gap * index
		card.position = Vector2(center_x - OPPONENT_CARD_SIZE.x * 0.5, y)
		step_centers.append(Vector2(center_x, y + OPPONENT_CARD_SIZE.y * 0.5))

	var current_center: Vector2 = step_centers[current_step]
	var current_is_left: bool = current_step % 2 == 0
	var marker_x: float = (
		current_center.x + OPPONENT_CARD_SIZE.x * 0.5 + 20.0
		if current_is_left
		else current_center.x - OPPONENT_CARD_SIZE.x * 0.5 - PLAYER_CARD_SIZE.x - 20.0
	)
	player_marker.position = Vector2(
		clampf(marker_x, 4.0, area.x - PLAYER_CARD_SIZE.x - 4.0),
		current_center.y - PLAYER_CARD_SIZE.y * 0.5
	)
	route_shadow.points = step_centers
	route_line.points = step_centers


func _opponent_style(index: int) -> StyleBoxFlat:
	if index < current_step:
		return _make_style(Color("222b39"), Color("697380"), 2, 8)
	if index == current_step:
		return _make_style(Color("7b2029"), Color("ffd64e"), 4, 8)
	if index == GameSession.CAMPAIGN_LENGTH - 1:
		return _make_style(Color("42173e"), Color("d36ac8"), 3, 8)
	return _make_style(Color("24284d"), Color("6575a5"), 2, 8)


func _step_status(index: int) -> String:
	if index < current_step:
		return "DEFEATED"
	if index == current_step:
		return "NEXT OPPONENT"
	if index == 6:
		return "FINAL FIGHT"
	return "FIGHT %d" % (index + 1)


func _get_profile_texture(character: CharacterData) -> Texture2D:
	if character == null:
		return null
	if character.profile_portrait != null:
		return character.profile_portrait
	if character.sprite_frames == null or not character.sprite_frames.has_animation(&"idle"):
		return null
	return character.sprite_frames.get_frame_texture(&"idle", 0)


func _make_style(
	fill_color: Color,
	border_color: Color,
	border_width: int,
	corner_radius: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 2.0
	style.content_margin_top = 2.0
	style.content_margin_right = 6.0
	style.content_margin_bottom = 2.0
	return style


func _show_then_start_fight() -> void:
	await get_tree().create_timer(preview_duration).timeout
	if is_inside_tree():
		get_tree().change_scene_to_file(ARENA_SCENE)


func _return_to_character_select() -> void:
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)
