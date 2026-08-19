extends Control

const ARENA_SCENE: String = "res://scenes/arenas/test_arena.tscn"
const GRID_COLUMNS: int = 4
const BASE_MOVE_SPEED: float = 240.0
const ROSTER: Array[CharacterData] = [
	preload("res://data/fighters/joe_marshall.tres"),
	preload("res://data/fighters/frank_washington.tres"),
	preload("res://data/fighters/fujiyama.tres"),
	preload("res://data/fighters/yamashita.tres"),
	preload("res://data/fighters/okamura.tres"),
	preload("res://data/fighters/jennifer.tres"),
	preload("res://data/fighters/peggy.tres"),
	preload("res://data/fighters/nurse.tres"),
]

@onready var character_grid: GridContainer = %CharacterGrid
@onready var preview: TextureRect = %Preview
@onready var selected_name_label: Label = %SelectedNameLabel
@onready var speed_label: Label = %SpeedLabel
@onready var power_label: Label = %PowerLabel
@onready var jump_label: Label = %JumpLabel
@onready var special_1_label: Label = %Special1Label
@onready var special_2_label: Label = %Special2Label
@onready var confirm_button: Button = %ConfirmButton

var selected_index: int = 0
var character_buttons: Array[Button] = []
var character_name_labels: Array[Label] = []
var is_transitioning: bool = false


func _ready() -> void:
	for index: int in ROSTER.size():
		var character: CharacterData = ROSTER[index]
		var option: Button = _create_character_button(character)
		option.pressed.connect(_select_character.bind(index))
		character_grid.add_child(option)
		character_buttons.append(option)

	confirm_button.pressed.connect(_confirm_selection)
	_select_character(0)
	character_buttons[0].grab_focus()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		var viewport: Viewport = get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		_confirm_selection()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("p1_left"):
		_move_selection(-1, 0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("p1_right"):
		_move_selection(1, 0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("p1_up"):
		_move_selection(0, -1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("p1_down"):
		_move_selection(0, 1)
		get_viewport().set_input_as_handled()


func _select_character(index: int) -> void:
	selected_index = clampi(index, 0, ROSTER.size() - 1)
	for button_index: int in character_buttons.size():
		var is_selected: bool = button_index == selected_index
		character_buttons[button_index].button_pressed = is_selected
		character_name_labels[button_index].text = (
			"✓ %s" % ROSTER[button_index].display_name
			if is_selected
			else ROSTER[button_index].display_name
		)
	_update_details(ROSTER[selected_index])


func _move_selection(horizontal: int, vertical: int) -> void:
	var row_count: int = ceili(float(ROSTER.size()) / float(GRID_COLUMNS))
	var column: int = selected_index % GRID_COLUMNS
	var row: int = selected_index / GRID_COLUMNS
	column = wrapi(column + horizontal, 0, GRID_COLUMNS)
	row = wrapi(row + vertical, 0, row_count)
	var next_index: int = mini(row * GRID_COLUMNS + column, ROSTER.size() - 1)
	_select_character(next_index)
	character_buttons[selected_index].grab_focus()


func _update_details(character: CharacterData) -> void:
	selected_name_label.text = character.display_name
	preview.texture = _get_preview_texture(character)
	speed_label.text = "Speed: %s" % _relative_speed(character.move_speed)
	power_label.text = "Power: %s" % _relative_power(character.power_multiplier)
	jump_label.text = "Jump: %s" % _relative_jump(character.jump_velocity)
	special_1_label.text = "Special 1: %s" % _special_name(character.special_move_1)
	special_2_label.text = "Special 2: %s" % _special_name(character.special_move_2)


func _confirm_selection() -> void:
	if is_transitioning or ROSTER.is_empty():
		return
	is_transitioning = true
	confirm_button.disabled = true
	var game_session: Node = get_node("/root/GameSession")
	if not game_session.begin_campaign(ROSTER[selected_index], ROSTER):
		is_transitioning = false
		confirm_button.disabled = false
		return
	get_tree().change_scene_to_file(ARENA_SCENE)


func _get_preview_texture(character: CharacterData) -> Texture2D:
	if character.sprite_frames == null or not character.sprite_frames.has_animation(&"idle"):
		return null
	if character.sprite_frames.get_frame_count(&"idle") == 0:
		return null
	return character.sprite_frames.get_frame_texture(&"idle", 0)


func _create_character_button(character: CharacterData) -> Button:
	var option := Button.new()
	option.custom_minimum_size = Vector2(125.0, 132.0)
	option.toggle_mode = true

	var card := VBoxContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	option.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.offset_left = 6.0
	card.offset_top = 6.0
	card.offset_right = -6.0
	card.offset_bottom = -6.0

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(48.0, 84.0)
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait.texture = _get_preview_texture(character)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(portrait)

	var name_label := Label.new()
	name_label.text = character.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_label)
	character_name_labels.append(name_label)
	return option


func _special_name(special_move: SpecialMoveData) -> String:
	return special_move.display_name if special_move != null else "Unavailable"


func _relative_speed(value: float) -> String:
	if value >= BASE_MOVE_SPEED * 1.05:
		return "Fast"
	if value <= BASE_MOVE_SPEED * 0.95:
		return "Measured"
	return "Balanced"


func _relative_power(value: float) -> String:
	if value >= 1.08:
		return "Strong"
	if value <= 0.94:
		return "Light"
	return "Balanced"


func _relative_jump(value: float) -> String:
	if value >= 610.0:
		return "High"
	if value <= 590.0:
		return "Low"
	return "Balanced"
