extends Control
class_name ArenaBackground

@onready var fallback_background: ColorRect = $FallbackBackground
@onready var artwork: TextureRect = $Artwork

var active_arena_id: StringName = ArenaCatalog.DEFAULT_ARENA_ID
var active_arena_name: String = "Test Arena"
var background_scale: float = 1.0
var background_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	resized.connect(_apply_background_transform)
	_apply_background_transform()


func configure_for_opponent(opponent: CharacterData) -> void:
	active_arena_id = ArenaCatalog.arena_id_for_opponent(opponent)
	active_arena_name = ArenaCatalog.get_display_name(active_arena_id)
	artwork.texture = ArenaCatalog.get_background_texture(active_arena_id)
	background_scale = ArenaCatalog.get_background_scale(active_arena_id)
	background_offset = ArenaCatalog.get_background_offset(active_arena_id)
	artwork.modulate = ArenaCatalog.get_background_modulate(active_arena_id)
	artwork.visible = artwork.texture != null
	fallback_background.visible = not artwork.visible
	_apply_background_transform()
	if artwork.texture == null:
		push_warning("Arena '%s' has no loadable background at '%s'; using fallback." % [
			active_arena_id,
			ArenaCatalog.get_background_path(active_arena_id),
		])


func set_reserved_bottom_height(reserved_height: float) -> void:
	offset_bottom = -maxf(reserved_height, 0.0)


func is_using_fallback() -> bool:
	return not artwork.visible


func _apply_background_transform() -> void:
	artwork.pivot_offset = artwork.size * 0.5
	artwork.scale = Vector2.ONE * background_scale
	artwork.offset_left = background_offset.x
	artwork.offset_right = background_offset.x
	artwork.offset_top = background_offset.y
	artwork.offset_bottom = background_offset.y
