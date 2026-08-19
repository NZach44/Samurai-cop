extends Resource
class_name CharacterData

enum Alignment {
	GOOD,
	BAD,
}

enum CampaignTier {
	EARLY,
	MEDIUM,
	LATE,
}

@export var character_id: StringName = &"fighter"
@export var display_name: String = "Fighter"
@export var alignment: Alignment = Alignment.GOOD
@export var campaign_tier: CampaignTier = CampaignTier.EARLY
@export var intro_text: String = ""
@export var intro_audio: AudioStream
@export var sprite_frames: SpriteFrames
@export var move_speed: float = 240.0
@export var jump_velocity: float = 600.0
@export_range(0.1, 3.0, 0.05) var power_multiplier: float = 1.0
@export var special_move_1: SpecialMoveData
@export var special_move_2: SpecialMoveData
