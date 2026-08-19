extends Node

const CAMPAIGN_LENGTH: int = 7
const GOOD_FINAL_OPPONENT_ID: StringName = &"yamashita"
const BAD_FINAL_OPPONENT_ID: StringName = &"joe_marshall"
const DEFAULT_DIFFICULTY: CpuDifficultyProfile = preload(
	"res://data/difficulties/medium.tres"
)

var selected_player_character: CharacterData
var selected_cpu_character: CharacterData
var campaign_opponents: Array[CharacterData] = []
var current_campaign_index: int = 0
var selected_difficulty: CpuDifficultyProfile = DEFAULT_DIFFICULTY


func begin_campaign(
	player_character: CharacterData,
	roster: Array[CharacterData],
	difficulty: CpuDifficultyProfile = DEFAULT_DIFFICULTY
) -> bool:
	clear_campaign()
	if player_character == null:
		return false
	selected_difficulty = difficulty if difficulty != null else DEFAULT_DIFFICULTY

	var final_opponent_id: StringName = (
		GOOD_FINAL_OPPONENT_ID
		if player_character.alignment == CharacterData.Alignment.GOOD
		else BAD_FINAL_OPPONENT_ID
	)
	var final_opponent: CharacterData
	var opponents_by_tier: Array = [[], [], []]
	var opponent_ids: Dictionary = {}

	for character: CharacterData in roster:
		if character == null or character.character_id == player_character.character_id:
			continue
		if opponent_ids.has(character.character_id):
			push_error("Campaign roster contains duplicate character ID: %s" % character.character_id)
			return false
		opponent_ids[character.character_id] = true
		if character.character_id == final_opponent_id:
			final_opponent = character
		else:
			opponents_by_tier[character.campaign_tier].append(character)

	if final_opponent == null or opponent_ids.size() != CAMPAIGN_LENGTH:
		push_error("Campaign requires seven unique opponents and a configured final opponent.")
		return false

	selected_player_character = player_character
	for tier: Array in opponents_by_tier:
		tier.shuffle()
		for opponent: CharacterData in tier:
			campaign_opponents.append(opponent)
	campaign_opponents.append(final_opponent)
	current_campaign_index = 0
	selected_cpu_character = campaign_opponents[0]
	return campaign_opponents.size() == CAMPAIGN_LENGTH


func advance_campaign() -> bool:
	if current_campaign_index + 1 >= campaign_opponents.size():
		return false
	current_campaign_index += 1
	selected_cpu_character = campaign_opponents[current_campaign_index]
	return true


func is_campaign_active() -> bool:
	return (
		selected_player_character != null
		and selected_cpu_character != null
		and campaign_opponents.size() == CAMPAIGN_LENGTH
	)


func is_final_fight() -> bool:
	return is_campaign_active() and current_campaign_index == campaign_opponents.size() - 1


func clear_campaign() -> void:
	selected_player_character = null
	selected_cpu_character = null
	campaign_opponents.clear()
	current_campaign_index = 0
	selected_difficulty = DEFAULT_DIFFICULTY
