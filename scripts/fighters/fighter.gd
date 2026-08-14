extends CharacterBody2D

@export var move_speed: float = 240.0


func _physics_process(delta: float) -> void:
	var move_direction: float = Input.get_axis("p1_left", "p1_right")
	velocity.x = move_direction * move_speed

	# Gravity keeps the fighter resting on arena collision without adding jumping.
	if not is_on_floor():
		velocity += get_gravity() * delta

	move_and_slide()
