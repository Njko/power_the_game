class_name Sector
extends RefCounted

var id: String                          # Ex: "R0", "HQ_R", "S1", "IN" (Île Nord)
var sector_type: GameEnums.SectorType
var owner_territory: GameEnums.PlayerColor  # À quel territoire appartient ce secteur
var display_name: String
var position: Vector2                   # Position sur le plateau en pixels
var adjacent_sectors: Array[String]     # IDs des secteurs adjacents
var units: Array = []                   # Unités présentes sur ce secteur

func _init(p_id: String, p_type: GameEnums.SectorType, p_owner: GameEnums.PlayerColor, p_pos: Vector2, p_name: String = "") -> void:
	id = p_id
	sector_type = p_type
	owner_territory = p_owner
	position = p_pos
	display_name = p_name if p_name != "" else p_id
	adjacent_sectors = []

func add_adjacent(sector_id: String) -> void:
	if sector_id not in adjacent_sectors:
		adjacent_sectors.append(sector_id)

func is_accessible_by(unit_type: GameEnums.UnitType) -> bool:
	match sector_type:
		GameEnums.SectorType.LAND:
			return not GameEnums.is_naval_unit(unit_type)
		GameEnums.SectorType.COASTAL:
			return true  # Accessible par tous
		GameEnums.SectorType.SEA:
			return GameEnums.is_naval_unit(unit_type)
		GameEnums.SectorType.ISLAND:
			return not GameEnums.is_naval_unit(unit_type)
		GameEnums.SectorType.HQ:
			return not GameEnums.is_naval_unit(unit_type)
	return false

func get_player_power(player: GameEnums.PlayerColor) -> int:
	var total := 0
	for unit in units:
		if unit.owner == player:
			total += GameEnums.get_unit_power(unit.unit_type)
	return total

func has_units_of_player(player: GameEnums.PlayerColor) -> bool:
	for unit in units:
		if unit.owner == player:
			return true
	return false

func get_units_of_player(player: GameEnums.PlayerColor) -> Array:
	var result := []
	for unit in units:
		if unit.owner == player:
			result.append(unit)
	return result

func get_players_present() -> Array[GameEnums.PlayerColor]:
	var players: Array[GameEnums.PlayerColor] = []
	for unit in units:
		if unit.owner not in players and unit.unit_type != GameEnums.UnitType.FLAG:
			players.append(unit.owner)
	return players
