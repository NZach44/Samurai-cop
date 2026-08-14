extends CanvasLayer

@export var force_visible_for_testing: bool = false


func _ready() -> void:
	visible = force_visible_for_testing or DisplayServer.is_touchscreen_available()
