extends CanvasLayer

@export var force_visible_for_testing: bool = false
@export_range(0.18, 0.25, 0.01) var control_zone_ratio: float = 0.25

@onready var control_zone: ColorRect = $Layout/ControlZone


func _ready() -> void:
	var is_mobile_web: bool = OS.has_feature("web_android") or OS.has_feature("web_ios")
	var is_editor_test: bool = force_visible_for_testing and OS.has_feature("editor")
	visible = is_editor_test or is_mobile_web or DisplayServer.is_touchscreen_available()
	control_zone.anchor_top = 1.0 - control_zone_ratio


func is_touch_layout_active() -> bool:
	return visible


func get_reserved_control_height(viewport_height: float) -> float:
	return viewport_height * control_zone_ratio if is_touch_layout_active() else 0.0
