extends Resource
class_name SpecialMoveData

enum CommandToken {
	FORWARD,
	BACK,
	UP,
	DOWN,
	PUNCH,
	KICK,
	BLOCK,
}

@export var move_id: StringName = &"special_move"
@export var display_name: String = "Special Move"
@export var command: Array[CommandToken] = []
@export var damage: int = 15
@export var startup_time: float = 0.20
@export var active_time: float = 0.12
@export var recovery_time: float = 0.30
@export var knockback: float = 360.0
@export var hitbox_width: float = 64.0
@export var hitbox_height: float = 44.0
@export var hitbox_offset_x: float = 56.0
