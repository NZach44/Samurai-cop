extends Node

var selected_player_character: CharacterData
var selected_cpu_character: CharacterData


func begin_match(player_character: CharacterData, cpu_character: CharacterData) -> void:
	selected_player_character = player_character
	selected_cpu_character = cpu_character


func clear_match() -> void:
	selected_player_character = null
	selected_cpu_character = null
