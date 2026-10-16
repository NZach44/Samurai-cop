extends Control

const CHARACTER_SELECT_SCENE: String = "res://scenes/ui/character_select.tscn"

@export_range(0.1, 10.0, 0.1) var display_duration: float = 4.0
@export var auto_restart: bool = true

@onready var message_panel: PanelContainer = %MessagePanel


func _ready() -> void:
	message_panel.modulate.a = 0.0
	message_panel.position.y -= 16.0
	var intro_tween: Tween = create_tween().set_parallel()
	intro_tween.tween_property(message_panel, "modulate:a", 1.0, 0.35)
	intro_tween.tween_property(message_panel, "position:y", message_panel.position.y + 16.0, 0.35)
	if auto_restart:
		_restart_after_reward()


func _restart_after_reward() -> void:
	await get_tree().create_timer(display_duration).timeout
	if not is_inside_tree():
		return
	var game_session: Node = get_node_or_null("/root/GameSession")
	if game_session != null:
		game_session.clear_campaign()
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)
