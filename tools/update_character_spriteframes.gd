extends SceneTree

const MANIFEST_PATH := "res://data/character_art_manifest.json"

var _dry_run := false
var _failures := 0


func _initialize() -> void:
	var manifest := _load_manifest()
	if manifest.is_empty():
		quit(1)
		return
	var arguments := OS.get_cmdline_user_args()
	_dry_run = arguments.has("--dry-run")
	var targets: Array[String] = _resolve_targets(arguments, manifest)
	if targets.is_empty():
		_print_usage()
		quit(2)
		return
	for character_id in targets:
		_update_character(character_id, manifest)
	if _failures > 0:
		push_error("SpriteFrames update completed with %d error(s)." % _failures)
	else:
		print("SpriteFrames update complete. Incomplete animations were preserved.")
	quit(1 if _failures > 0 else 0)


func _load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_error("Character art manifest not found: %s" % MANIFEST_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Character art manifest is not valid JSON.")
		return {}
	return parsed as Dictionary


func _resolve_targets(arguments: PackedStringArray, manifest: Dictionary) -> Array[String]:
	var targets: Array[String] = []
	var characters: Dictionary = manifest.get("characters", {})
	if arguments.has("--all"):
		for character_value: Variant in characters.keys():
			targets.append(String(character_value))
		return targets
	for argument in arguments:
		if argument.begins_with("--"):
			continue
		if characters.has(argument):
			targets.append(argument)
		else:
			push_error("Unknown character id: %s" % argument)
			_failures += 1
	return targets


func _update_character(character_id: String, manifest: Dictionary) -> void:
	var characters: Dictionary = manifest["characters"]
	var character_config: Dictionary = characters[character_id]
	var frames_path: String = character_config["sprite_frames"]
	var sprite_frames := load(frames_path) as SpriteFrames
	if sprite_frames == null:
		push_error("[%s] Could not load %s" % [character_id, frames_path])
		_failures += 1
		return
	var changed := false
	var defaults: Dictionary = manifest["animations"]
	var overrides: Dictionary = character_config.get("animations", {})
	var animation_order: Array = manifest["animation_order"]
	var allowed_animations := _requested_animations(OS.get_cmdline_user_args())
	for animation_value: Variant in animation_order:
		var animation_name := String(animation_value)
		if not allowed_animations.is_empty() and not allowed_animations.has(animation_name):
			continue
		var config: Dictionary = defaults[animation_name].duplicate(true)
		if overrides.has(animation_name):
			var animation_override: Dictionary = overrides[animation_name]
			for key: Variant in animation_override.keys():
				config[key] = animation_override[key]
		var textures := _load_complete_animation(character_id, animation_name, int(config["frame_count"]), _dry_run)
		if textures.is_empty():
			print("SKIP [%s] %s: production set incomplete; existing animation preserved." % [character_id, animation_name])
			continue
		if _dry_run:
			print("READY [%s] %s: %d ordered frames, %.1f FPS, loop=%s" % [character_id, animation_name, textures.size(), float(config["fps"]), str(config["loop"])])
			continue
		var animation_key := StringName(animation_name)
		if not sprite_frames.has_animation(animation_key):
			sprite_frames.add_animation(animation_key)
		sprite_frames.clear(animation_key)
		sprite_frames.set_animation_speed(animation_key, float(config["fps"]))
		sprite_frames.set_animation_loop(animation_key, bool(config["loop"]))
		for texture in textures:
			sprite_frames.add_frame(animation_key, texture)
		changed = true
		print("UPDATED [%s] %s" % [character_id, animation_name])
	if changed and not _dry_run:
		var save_error := ResourceSaver.save(sprite_frames, frames_path)
		if save_error != OK:
			push_error("[%s] Could not save %s (error %d)" % [character_id, frames_path, save_error])
			_failures += 1


func _requested_animations(arguments: PackedStringArray) -> Array[String]:
	var requested: Array[String] = []
	for argument: String in arguments:
		if not argument.begins_with("--animations="):
			continue
		for animation: String in argument.trim_prefix("--animations=").split(",", false):
			requested.append(animation)
	return requested


func _load_complete_animation(character_id: String, animation_name: String, frame_count: int, dry_run: bool) -> Array[Texture2D]:
	var paths: Array[String] = []
	for frame_number in range(1, frame_count + 1):
		var frame_path := "res://assets/characters/%s/sprites/%s/%s_%03d.png" % [character_id, animation_name, animation_name, frame_number]
		if not FileAccess.file_exists(frame_path):
			return []
		paths.append(frame_path)
	if dry_run:
		var placeholders: Array[Texture2D] = []
		placeholders.resize(paths.size())
		return placeholders
	var textures: Array[Texture2D] = []
	for frame_path in paths:
		var texture := load(frame_path) as Texture2D
		if texture == null:
			push_error("Could not import texture: %s" % frame_path)
			_failures += 1
			return []
		textures.append(texture)
	return textures


func _print_usage() -> void:
	print("Usage:")
	print("  godot --headless --path . --script tools/update_character_spriteframes.gd -- <character_id> [--dry-run]")
	print("  godot --headless --path . --script tools/update_character_spriteframes.gd -- --all [--dry-run]")
