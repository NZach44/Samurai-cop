extends RefCounted
class_name ArenaCatalog

const DEFAULT_ARENA_ID: StringName = &"default"

const ARENAS: Dictionary = {
	&"stage_01": {
		"display_name": "Lion Head Room",
		"background_path": "res://assets/backgrounds/stage_01/background.png",
	},
	&"stage_02": {
		"display_name": "Chief's House",
		"background_path": "res://assets/backgrounds/stage_02/background.png",
	},
	&"stage_03": {
		"display_name": "Parking",
		"background_path": "res://assets/backgrounds/stage_03/background.png",
	},
	&"stage_04": {
		"display_name": "Outlands",
		"background_path": "res://assets/backgrounds/stage_04/background.png",
	},
	&"stage_05": {
		"display_name": "Outlands 2",
		"background_path": "res://assets/backgrounds/stage_05/background.png",
	},
	&"stage_06": {
		"display_name": "Police Station",
		"background_path": "res://assets/backgrounds/stage_06/background.png",
	},
	&"stage_07": {
		"display_name": "Hospital",
		"background_path": "res://assets/backgrounds/stage_07/background.png",
	},
}


static func arena_id_for_opponent(opponent: CharacterData) -> StringName:
	if opponent == null or not ARENAS.has(opponent.home_arena_id):
		return DEFAULT_ARENA_ID
	return opponent.home_arena_id


static func get_display_name(arena_id: StringName) -> String:
	var definition: Dictionary = _get_definition(arena_id)
	return definition.get("display_name", "Test Arena") as String


static func get_background_path(arena_id: StringName) -> String:
	return _get_definition(arena_id).get("background_path", "") as String


static func get_background_texture(arena_id: StringName) -> Texture2D:
	var background_path: String = get_background_path(arena_id)
	if background_path.is_empty() or not ResourceLoader.exists(background_path, "Texture2D"):
		return null
	return load(background_path) as Texture2D


static func get_background_scale(arena_id: StringName) -> float:
	return _get_definition(arena_id).get("background_scale", 1.0) as float


static func get_background_offset(arena_id: StringName) -> Vector2:
	return _get_definition(arena_id).get("background_offset", Vector2.ZERO) as Vector2


static func get_background_modulate(arena_id: StringName) -> Color:
	return _get_definition(arena_id).get("background_modulate", Color.WHITE) as Color


static func _get_definition(arena_id: StringName) -> Dictionary:
	return ARENAS.get(arena_id, {}) as Dictionary
