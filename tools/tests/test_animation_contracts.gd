extends SceneTree

const CHARACTERS: Array[CharacterData] = [
	preload("res://data/fighters/joe_marshall.tres"),
	preload("res://data/fighters/frank_washington.tres"),
	preload("res://data/fighters/yamashita.tres"),
	preload("res://data/fighters/fujiyama.tres"),
	preload("res://data/fighters/jennifer.tres"),
	preload("res://data/fighters/peggy.tres"),
	preload("res://data/fighters/okamura.tres"),
	preload("res://data/fighters/nurse.tres"),
]

const ANIMATION_CONTRACT: Dictionary = {
	&"idle": {"frames": 4, "speed": 6.0, "loop": true},
	&"walk": {"frames": 6, "speed": 9.0, "loop": true},
	&"punch": {"frames": 5, "speed": 12.0, "loop": false},
	&"kick": {"frames": 6, "speed": 12.0, "loop": false},
	&"crouch": {"frames": 3, "speed": 8.0, "loop": false},
	&"crouch_punch": {"frames": 5, "speed": 12.0, "loop": false},
	&"crouch_kick": {"frames": 6, "speed": 12.0, "loop": false},
	&"block": {"frames": 3, "speed": 8.0, "loop": false},
	&"crouch_block": {"frames": 3, "speed": 8.0, "loop": false},
	&"jump": {"frames": 5, "speed": 10.0, "loop": false},
	&"hurt": {"frames": 3, "speed": 10.0, "loop": false},
	&"special_1": {"frames": 8, "speed": 12.0, "loop": false},
	&"special_2": {"frames": 8, "speed": 12.0, "loop": false},
	&"ko": {"frames": 8, "speed": 10.0, "loop": false},
}

var failures: PackedStringArray = []


func _initialize() -> void:
	for character: CharacterData in CHARACTERS:
		_check_character(character)
	if failures.is_empty():
		print("PASS all fighter animation contracts")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _check_character(character: CharacterData) -> void:
	var frames := character.sprite_frames
	if frames == null:
		failures.append("%s has no SpriteFrames resource" % character.display_name)
		return
	var total_frames: int = 0
	for animation: StringName in ANIMATION_CONTRACT:
		var expected: Dictionary = ANIMATION_CONTRACT[animation]
		if not frames.has_animation(animation):
			failures.append("%s is missing %s" % [character.display_name, animation])
			continue
		var frame_count := frames.get_frame_count(animation)
		total_frames += frame_count
		if frame_count != expected["frames"]:
			failures.append(
				"%s %s has %d frames; expected %d"
				% [character.display_name, animation, frame_count, expected["frames"]]
			)
		if not is_equal_approx(frames.get_animation_speed(animation), expected["speed"]):
			failures.append(
				"%s %s runs at %.2f FPS; expected %.2f"
				% [character.display_name, animation, frames.get_animation_speed(animation), expected["speed"]]
			)
		if frames.get_animation_loop(animation) != expected["loop"]:
			failures.append("%s %s loop setting is incorrect" % [character.display_name, animation])
	if total_frames != 73:
		failures.append("%s has %d production frames; expected 73" % [character.display_name, total_frames])
