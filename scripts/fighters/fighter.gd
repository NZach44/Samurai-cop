extends CharacterBody2D

@export var move_speed: float = 240.0
@export var jump_velocity: float = 600.0


func _physics_process(delta: float) -> void:
	var move_direction: float = Input.get_axis("p1_left", "p1_right")
	velocity.x = move_direction * move_speed

	if not is_on_floor():
		velocity += get_gravity() * delta
	elif Input.is_action_just_pressed("p1_jump"):
		velocity.y = -jump_velocity

	move_and_slide()
