class_name UnitData
extends RefCounted

var unit_type: GameEnums.UnitType
var owner: GameEnums.PlayerColor
var sector_id: String  # Secteur actuel ("" si en réserve)
var in_reserve: bool = false
var moved_this_turn: bool = false
var rebounded_this_turn: bool = false

func _init(p_type: GameEnums.UnitType, p_owner: GameEnums.PlayerColor, p_sector: String = "") -> void:
	unit_type = p_type
	owner = p_owner
	sector_id = p_sector

func get_power() -> int:
	return GameEnums.get_unit_power(unit_type)

func get_max_move() -> int:
	return GameEnums.get_unit_max_move(unit_type)

func get_display_name() -> String:
	return GameEnums.get_unit_name(unit_type)
