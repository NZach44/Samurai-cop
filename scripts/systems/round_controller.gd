extends Node2D

enum MatchState {
	ROUND_START,
	FIGHTING,
	ROUND_OVER,
	MATCH_OVER,
}

const ROUNDS_TO_WIN: int = 2
const ARENA_SCENE: String = "res://scenes/arenas/test_arena.tscn"
const CHARACTER_SELECT_SCENE: String = "res://scenes/ui/character_select.tscn"

@export var round_message_duration: float = 0.8
@export var fight_message_duration: float = 1.0
@export var round_end_delay: float = 2.0
@export var match_end_delay: float = 3.0
@export var special_move_message_duration: float = 0.8
@export var intro_duration: float = 1.7
@export var intro_start_delay: float = 0.5
@export var intro_bubble_gap: float = 20.0
@export var intro_bubble_screen_margin: float = 16.0
@export var intro_bubble_hud_clearance: float = 96.0
@export var intro_bubble_min_width: float = 180.0
@export var intro_bubble_max_width: float = 320.0
@export var mobile_floor_clearance: float = 24.0

const HEALTH_GREEN: Color = Color("35c968")
const HEALTH_ORANGE: Color = Color("f0a43c")
const HEALTH_RED: Color = Color("e5484d")

@onready var fighter_1: Fighter = $Fighter1
@onready var fighter_2: Fighter = $Fighter2
@onready var floor_body: StaticBody2D = $Floor
@onready var floor_collision: CollisionShape2D = $Floor/CollisionShape2D
@onready var mobile_controls: CanvasLayer = $MobileControls
@onready var fighter_1_health_bar: ProgressBar = $HUD/Controls/Fighter1HealthBar
@onready var fighter_2_health_bar: ProgressBar = $HUD/Controls/Fighter2HealthBar
@onready var fighter_1_name_label: Label = $HUD/Controls/Fighter1Label
@onready var fighter_2_name_label: Label = $HUD/Controls/Fighter2Label
@onready var fighter_1_rounds_label: Label = $HUD/Controls/Fighter1RoundsLabel
@onready var fighter_2_rounds_label: Label = $HUD/Controls/Fighter2RoundsLabel
@onready var campaign_progress_label: Label = $HUD/Controls/CampaignProgressLabel
@onready var winner_label: Label = $HUD/Controls/WinnerLabel
@onready var special_move_label: Label = $HUD/Controls/SpecialMoveLabel
@onready var intro_bubble: PanelContainer = $HUD/Controls/IntroBubble
@onready var intro_label: Label = $HUD/Controls/IntroBubble/Label
@onready var intro_voice_player: AudioStreamPlayer = $IntroVoicePlayer

var fighter_1_spawn_position: Vector2
var fighter_2_spawn_position: Vector2
var fighter_1_round_wins: int = 0
var fighter_2_round_wins: int = 0
var round_number: int = 1
var match_state: MatchState = MatchState.ROUND_START
var special_message_sequence_id: int = 0
var desktop_floor_position: Vector2
var desktop_fighter_1_position: Vector2
var desktop_fighter_2_position: Vector2


func _enter_tree() -> void:
	var player_fighter: Fighter = get_node("Fighter1") as Fighter
	var cpu_fighter: Fighter = get_node("Fighter2") as Fighter
	var game_session: Node = get_node("/root/GameSession")
	if game_session.selected_player_character != null:
		player_fighter.character_data = game_session.selected_player_character
	if game_session.selected_cpu_character != null:
		cpu_fighter.character_data = game_session.selected_cpu_character
	if game_session.selected_difficulty != null:
		var controller: CPUController = cpu_fighter.get_node("CPUController") as CPUController
		controller.difficulty_profile = game_session.selected_difficulty


func _ready() -> void:
	desktop_floor_position = floor_body.position
	desktop_fighter_1_position = fighter_1.position
	desktop_fighter_2_position = fighter_2.position
	_apply_mobile_safe_area()
	fighter_1_spawn_position = fighter_1.position
	fighter_2_spawn_position = fighter_2.position

	fighter_1.health_changed.connect(_on_health_changed.bind(fighter_1_health_bar))
	fighter_2.health_changed.connect(_on_health_changed.bind(fighter_2_health_bar))
	fighter_1.defeated.connect(_on_fighter_defeated)
	fighter_2.defeated.connect(_on_fighter_defeated)
	fighter_1.special_move_started.connect(_on_special_move_started)
	fighter_2.special_move_started.connect(_on_special_move_started)

	_on_health_changed(fighter_1.current_health, fighter_1.max_health, fighter_1_health_bar)
	_on_health_changed(fighter_2.current_health, fighter_2.max_health, fighter_2_health_bar)
	fighter_1_name_label.text = fighter_1.get_display_name()
	fighter_2_name_label.text = fighter_2.get_display_name()
	_update_campaign_ui()
	_update_round_win_ui()
	_start_round()


func _apply_mobile_safe_area() -> void:
	floor_body.position = desktop_floor_position
	fighter_1.position = desktop_fighter_1_position
	fighter_2.position = desktop_fighter_2_position
	if (
		not mobile_controls.has_method("is_touch_layout_active")
		or not mobile_controls.is_touch_layout_active()
	):
		return

	var floor_shape: RectangleShape2D = floor_collision.shape as RectangleShape2D
	if floor_shape == null:
		return
	var viewport_height: float = get_viewport_rect().size.y
	var reserved_height: float = mobile_controls.get_reserved_control_height(viewport_height)
	var floor_surface_y: float = viewport_height - reserved_height - mobile_floor_clearance
	floor_body.position.y = floor_surface_y + floor_shape.size.y * 0.5
	var mobile_vertical_offset: float = floor_body.position.y - desktop_floor_position.y
	fighter_1.position.y += mobile_vertical_offset
	fighter_2.position.y += mobile_vertical_offset


func _on_health_changed(current_health: int, max_health: int, health_bar: ProgressBar) -> void:
	health_bar.max_value = max_health
	health_bar.value = current_health
	var health_ratio: float = (
		float(current_health) / float(max_health) if max_health > 0 else 0.0
	)
	var health_color: Color = HEALTH_RED
	if health_ratio >= 0.60:
		health_color = HEALTH_GREEN
	elif health_ratio >= 0.30:
		health_color = HEALTH_ORANGE
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = health_color
	fill_style.corner_radius_top_left = 4
	fill_style.corner_radius_top_right = 4
	fill_style.corner_radius_bottom_left = 4
	fill_style.corner_radius_bottom_right = 4
	health_bar.add_theme_stylebox_override("fill", fill_style)


func _on_special_move_started(move_name: String) -> void:
	special_message_sequence_id += 1
	var current_message_id: int = special_message_sequence_id
	special_move_label.text = move_name
	special_move_label.show()
	await get_tree().create_timer(special_move_message_duration).timeout
	if current_message_id == special_message_sequence_id:
		special_move_label.hide()


func _on_fighter_defeated(loser: Fighter) -> void:
	# Only the first defeat signal in active play can award this round.
	if match_state != MatchState.FIGHTING:
		return

	match_state = MatchState.ROUND_OVER
	_set_fighter_controls_enabled(false)
	var winner: Fighter = fighter_2 if loser == fighter_1 else fighter_1
	var winner_number: int = 2 if winner == fighter_2 else 1
	if winner == fighter_1:
		fighter_1_round_wins += 1
	else:
		fighter_2_round_wins += 1
	_update_round_win_ui()

	winner_label.text = "PLAYER %d WINS ROUND" % winner_number
	winner_label.show()
	print("ROUND %d: %s wins; %s is defeated" % [
		round_number,
		winner.get_display_name(),
		loser.get_display_name(),
	])

	await get_tree().create_timer(round_end_delay).timeout
	if _get_round_wins(winner) >= ROUNDS_TO_WIN:
		_finish_match(winner, winner_number)
	else:
		round_number += 1
		_start_round()


func _start_round() -> void:
	match_state = MatchState.ROUND_START
	_set_fighter_controls_enabled(false)
	fighter_1.reset_for_round(fighter_1_spawn_position)
	fighter_2.reset_for_round(fighter_2_spawn_position)
	winner_label.hide()
	intro_bubble.hide()

	await get_tree().create_timer(intro_start_delay).timeout
	if match_state != MatchState.ROUND_START:
		return
	await _play_fighter_intro(fighter_1)
	if match_state != MatchState.ROUND_START:
		return
	await _play_fighter_intro(fighter_2)
	if match_state != MatchState.ROUND_START:
		return

	winner_label.text = "ROUND %d" % round_number
	winner_label.show()
	await get_tree().create_timer(round_message_duration).timeout
	if match_state != MatchState.ROUND_START:
		return

	winner_label.text = "FIGHT!"
	await get_tree().create_timer(fight_message_duration).timeout
	if match_state != MatchState.ROUND_START:
		return

	winner_label.hide()
	match_state = MatchState.FIGHTING
	_set_fighter_controls_enabled(true)


func _play_fighter_intro(fighter: Fighter) -> void:
	var data: CharacterData = fighter.character_data
	if data == null or (data.intro_text.is_empty() and data.intro_audio == null):
		return

	intro_voice_player.stop()
	intro_voice_player.stream = data.intro_audio
	if data.intro_audio != null:
		intro_voice_player.play()

	if not data.intro_text.is_empty():
		_configure_intro_bubble_text(data.intro_text)
		# Container sizing is deferred; wait one locked frame before using final bounds.
		await get_tree().process_frame
		_position_intro_bubble(fighter)
		intro_bubble.show()

	await get_tree().create_timer(intro_duration).timeout
	intro_bubble.hide()
	intro_voice_player.stop()
	intro_voice_player.stream = null


func _position_intro_bubble(fighter: Fighter) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var bubble_size: Vector2 = intro_bubble.size
	var visual_bounds: Rect2 = fighter.get_visual_bounds_in_canvas()
	var desired_position := Vector2(
		visual_bounds.get_center().x - bubble_size.x * 0.5,
		visual_bounds.position.y - intro_bubble_gap - bubble_size.y
	)
	var maximum_x: float = maxf(
		viewport_size.x - bubble_size.x - intro_bubble_screen_margin,
		intro_bubble_screen_margin
	)
	if desired_position.y < intro_bubble_hud_clearance:
		var place_on_right: bool = visual_bounds.get_center().x < viewport_size.x * 0.5
		desired_position.x = (
			visual_bounds.end.x + intro_bubble_gap
			if place_on_right
			else visual_bounds.position.x - bubble_size.x - intro_bubble_gap
		)
		desired_position.y = visual_bounds.position.y
	desired_position.x = clampf(
		desired_position.x,
		intro_bubble_screen_margin,
		maximum_x
	)
	desired_position.y = clampf(
		desired_position.y,
		intro_bubble_hud_clearance,
		maxf(
			viewport_size.y - bubble_size.y - intro_bubble_screen_margin,
			intro_bubble_hud_clearance
		)
	)
	intro_bubble.position = desired_position


func _configure_intro_bubble_text(text: String) -> void:
	var font: Font = intro_label.get_theme_font("font")
	var font_size: int = intro_label.get_theme_font_size("font_size")
	var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var bubble_width: float = clampf(
		text_width + 32.0,
		intro_bubble_min_width,
		intro_bubble_max_width
	)
	var available_text_width: float = maxf(bubble_width - 32.0, 1.0)
	var estimated_lines: int = maxi(ceili(text_width / available_text_width), 1)
	var bubble_height: float = clampf(
		float(estimated_lines * font.get_height(font_size)) + 24.0,
		72.0,
		160.0
	)
	intro_label.custom_minimum_size = Vector2(
		available_text_width,
		maxf(bubble_height - 24.0, 1.0)
	)
	intro_label.size = intro_label.custom_minimum_size
	intro_label.text = text
	intro_bubble.custom_minimum_size = Vector2(bubble_width, bubble_height)
	intro_bubble.size = intro_bubble.custom_minimum_size
	intro_bubble.queue_sort()


func _finish_match(winner: Fighter, winner_number: int) -> void:
	match_state = MatchState.MATCH_OVER
	_set_fighter_controls_enabled(false)
	var game_session: Node = get_node("/root/GameSession")
	var player_won: bool = winner == fighter_1
	var campaign_is_active: bool = game_session.is_campaign_active()
	var completed_campaign: bool = (
		campaign_is_active
		and player_won
		and game_session.is_final_fight()
	)
	if campaign_is_active and not player_won:
		winner_label.text = "GAME OVER"
	elif completed_campaign:
		winner_label.text = "CAMPAIGN COMPLETE"
	else:
		winner_label.text = "PLAYER %d WINS THE MATCH" % winner_number
	winner_label.show()
	print("MATCH OVER: %s wins the match" % winner.get_display_name())

	await get_tree().create_timer(match_end_delay).timeout
	if campaign_is_active and player_won and not completed_campaign:
		if game_session.advance_campaign():
			get_tree().change_scene_to_file(ARENA_SCENE)
			return
	game_session.clear_campaign()
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func _get_round_wins(fighter: Fighter) -> int:
	return fighter_1_round_wins if fighter == fighter_1 else fighter_2_round_wins


func _set_fighter_controls_enabled(enabled: bool) -> void:
	fighter_1.set_controls_enabled(enabled)
	fighter_2.set_controls_enabled(enabled)
	if not enabled:
		special_message_sequence_id += 1
		special_move_label.hide()


func _update_round_win_ui() -> void:
	fighter_1_rounds_label.text = "P1 ROUNDS: %d" % fighter_1_round_wins
	fighter_2_rounds_label.text = "P2 ROUNDS: %d" % fighter_2_round_wins


func _update_campaign_ui() -> void:
	var game_session: Node = get_node("/root/GameSession")
	if not game_session.is_campaign_active():
		campaign_progress_label.hide()
		return
	campaign_progress_label.show()
	if game_session.is_final_fight():
		campaign_progress_label.text = "FINAL FIGHT\n%s" % fighter_2.get_display_name().to_upper()
	else:
		campaign_progress_label.text = "FIGHT %d / %d\nVS %s" % [
			game_session.current_campaign_index + 1,
			game_session.campaign_opponents.size(),
			fighter_2.get_display_name().to_upper(),
		]
