extends Resource
class_name CpuDifficultyProfile

@export var profile_name: String = "MEDIUM"
@export var decision_interval_min: float = 0.14
@export var decision_interval_max: float = 0.22
@export_range(0.0, 1.0, 0.05) var attack_probability: float = 0.72
@export var attack_cooldown: float = 0.42
@export var punch_weight: float = 5.0
@export var kick_weight: float = 4.5
@export var special_weight: float = 1.2
@export var defensive_reaction_min: float = 0.065
@export var defensive_reaction_max: float = 0.11
@export_range(0.0, 1.0, 0.05) var block_probability: float = 0.76
@export var block_hold_min: float = 0.30
@export var block_hold_max: float = 0.48
@export var preferred_distance_multiplier: float = 1.35
@export_range(0.0, 1.0, 0.05) var retreat_probability: float = 0.42
@export_range(0.0, 1.0, 0.05) var repeat_attack_penalty: float = 0.28
@export_range(0.0, 1.0, 0.05) var pressure_response_probability: float = 0.72
@export_range(0.0, 1.0, 0.05) var counterattack_probability: float = 0.80
@export var special_cooldown: float = 2.4
