extends CanvasLayer

@export var force_visible_for_testing: bool = false


func _ready() -> void:
	var is_mobile_web: bool = OS.has_feature("web_android") or OS.has_feature("web_ios")
	var is_editor_test: bool = force_visible_for_testing and OS.has_feature("editor")
	visible = is_editor_test or is_mobile_web or DisplayServer.is_touchscreen_available()
