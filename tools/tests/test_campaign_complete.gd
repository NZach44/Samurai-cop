extends SceneTree

const COMPLETE_SCENE: PackedScene = preload("res://scenes/ui/campaign_complete.tscn")
const EXPECTED_MESSAGE: String = "Congratulations! You fought like a man and beat everyone"

var failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var screen: Control = COMPLETE_SCENE.instantiate() as Control
	screen.auto_restart = false
	root.size = Vector2i(1152, 648)
	root.add_child(screen)
	await process_frame

	var artwork: TextureRect = screen.get_node("%EndingArtwork") as TextureRect
	var message: Label = screen.get_node("%Message") as Label
	_check(is_equal_approx(screen.display_duration, 4.0), "reward must remain visible for four seconds")
	_check(message.text == EXPECTED_MESSAGE, "completion message changed")
	_check(message.uppercase, "completion message must use the stylized uppercase treatment")
	_check(artwork.texture != null, "completion artwork is missing")
	_check(
		artwork.texture.resource_path == "res://assets/ui/campaign_complete/finish.png",
		"completion screen uses the wrong artwork"
	)
	_check(
		artwork.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED,
		"completion artwork must preserve aspect ratio and cover the viewport"
	)
	for viewport_size: Vector2i in [
		Vector2i(1152, 648),
		Vector2i(1296, 648),
		Vector2i(1404, 648),
		Vector2i(1440, 648),
	]:
		root.size = viewport_size
		await process_frame
		_check(screen.size == Vector2(viewport_size), "reward screen does not fill %s" % viewport_size)

	screen.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS campaign-completion artwork, message, timing, and responsive cover")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
