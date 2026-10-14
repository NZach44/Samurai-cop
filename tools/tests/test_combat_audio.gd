extends SceneTree

const FIGHTER_SCENE: PackedScene = preload("res://scenes/fighters/fighter.tscn")
const JOE: CharacterData = preload("res://data/fighters/joe_marshall.tres")
const PUNCH_HITS: AudioStreamRandomizer = preload("res://assets/audio/combat/punch_hits.tres")
const KICK_HITS: AudioStreamRandomizer = preload("res://assets/audio/combat/kick_hits.tres")
const BLOCK_HITS: AudioStreamRandomizer = preload("res://assets/audio/combat/block_hits.tres")

var failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	_test_resources()
	await _test_runtime_routing()

	if failures.is_empty():
		print("PASS combat punch, kick, and block impact audio")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_resources() -> void:
	_check(AudioServer.get_bus_index(&"SFX") >= 0, "SFX audio bus is missing")
	for entry: Dictionary in [
		{"name": "punch", "stream": PUNCH_HITS},
		{"name": "kick", "stream": KICK_HITS},
		{"name": "block", "stream": BLOCK_HITS},
	]:
		var randomizer: AudioStreamRandomizer = entry["stream"]
		_check(randomizer.get_streams_count() == 3, "%s pool must contain three variants" % entry["name"])
		for stream_index: int in range(randomizer.get_streams_count()):
			var stream: AudioStream = randomizer.get_stream(stream_index)
			_check(stream != null, "%s variant %d is missing" % [entry["name"], stream_index + 1])
			if stream != null:
				_check(stream.get_length() > 0.0, "%s variant %d is empty" % [entry["name"], stream_index + 1])


func _test_runtime_routing() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var attacker: Fighter = FIGHTER_SCENE.instantiate() as Fighter
	var target: Fighter = FIGHTER_SCENE.instantiate() as Fighter
	attacker.character_data = JOE
	target.character_data = JOE
	world.add_child(attacker)
	world.add_child(target)
	attacker.set_physics_process(false)
	target.set_physics_process(false)
	attacker.global_position = Vector2(-100.0, 0.0)
	target.global_position = Vector2(100.0, 0.0)
	attacker.opponent = target
	target.opponent = attacker
	var player: AudioStreamPlayer = target.get_node("CombatImpactPlayer") as AudioStreamPlayer
	_check(player != null, "fighter CombatImpactPlayer is missing")
	_check(player.bus == &"SFX", "combat impact player is not routed to SFX")

	target._resolve_normal_hit(1, 0.0, attacker, "Punch", Fighter.AttackLevel.MID, 0.01, Fighter.ImpactSound.PUNCH)
	_check(player.playing, "confirmed punch did not play an impact")
	_check(player.stream == PUNCH_HITS, "confirmed punch used the wrong impact pool")
	player.stop()
	target._resolve_normal_hit(1, 0.0, attacker, "Kick", Fighter.AttackLevel.MID, 0.01, Fighter.ImpactSound.KICK)
	_check(player.playing, "confirmed kick did not play an impact")
	_check(player.stream == KICK_HITS, "confirmed kick used the wrong impact pool")
	player.stop()
	target._resolve_block(1, 0.0, attacker, "Punch", 0.01)
	_check(player.playing, "blocked attack did not play an impact")
	_check(player.stream == BLOCK_HITS, "blocked attack used a body impact instead of wood")
	player.stop()
	target._resolve_normal_hit(1, 0.0, attacker, "Projectile", Fighter.AttackLevel.MID, 0.01, Fighter.ImpactSound.NONE)
	_check(not player.playing, "projectile incorrectly inherited a punch or kick impact")

	attacker.request_punch()
	await create_timer(0.13).timeout
	var attacker_player: AudioStreamPlayer = attacker.get_node("CombatImpactPlayer") as AudioStreamPlayer
	_check(not attacker_player.playing, "whiffed punch incorrectly played an impact")
	await create_timer(0.35).timeout

	player.stop()
	player.stream = null
	attacker_player.stop()
	attacker_player.stream = null
	world.queue_free()
	await process_frame
	await process_frame
