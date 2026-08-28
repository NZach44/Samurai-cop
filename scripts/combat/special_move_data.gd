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

enum SpecialBehavior {
	MELEE,
	FLYING_KICK,
	PROJECTILE,
}

enum AttackLevel {
	MID,
	LOW,
}

@export var special_id: StringName = &"special_move"
@export var display_title: String = "Special Move"
@export var command: Array[CommandToken] = []
@export var behavior: SpecialBehavior = SpecialBehavior.MELEE
@export var damage: int = 15
@export var startup_time: float = 0.20
@export var active_time: float = 0.12
@export var recovery_time: float = 0.30
@export var hit_stun_duration: float = 0.25
@export var block_stun_duration: float = 0.16
@export var knockback: float = 360.0
@export var attack_level: AttackLevel = AttackLevel.MID
@export var hitbox_width: float = 64.0
@export var hitbox_height: float = 44.0
@export var hitbox_offset_x: float = 56.0
@export var hitbox_offset_y: float = -24.0
@export var animation_name: StringName = &"special_1"
@export var movement_speed: float = 0.0
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 240.0
@export var projectile_lifetime: float = 2.0
@export var projectile_max_distance: float = 420.0
@export var projectile_damage: int = 0
@export var projectile_size: Vector2 = Vector2(28.0, 18.0)
@export var projectile_color: Color = Color(1.0, 0.75, 0.2, 1.0)
@export var projectile_texture: Texture2D
@export var projectile_visual_size: Vector2 = Vector2.ZERO
