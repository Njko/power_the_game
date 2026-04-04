class_name GameState
extends RefCounted

## État complet d'une partie de Power.

var board: BoardData
var players: Dictionary = {}  # PlayerColor -> PlayerData
var all_units: Array = []     # Toutes les unités en jeu
var current_phase: GameEnums.GamePhase = GameEnums.GamePhase.SETUP
var current_round: int = 0
var arbiter_index: int = 0    # Index du joueur arbitre (rotation)
var player_order: Array[GameEnums.PlayerColor] = []  # Ordre des joueurs
var game_start_time: float = 0.0
var game_duration_limit: float = 7200.0  # 2 heures en secondes
var num_players: int = 4

func _init() -> void:
	board = BoardData.new()

func setup_game(p_num_players: int) -> void:
	num_players = p_num_players
	player_order = _get_player_colors()

	for color in player_order:
		players[color] = PlayerData.new(color)

	_place_starting_units()
	current_phase = GameEnums.GamePhase.PLANNING
	current_round = 1

func _get_player_colors() -> Array[GameEnums.PlayerColor]:
	match num_players:
		2:
			# Chaque joueur contrôle 2 territoires adjacents
			return [
				GameEnums.PlayerColor.GREEN,
				GameEnums.PlayerColor.RED,
			]
		3:
			return [
				GameEnums.PlayerColor.GREEN,
				GameEnums.PlayerColor.BLUE,
				GameEnums.PlayerColor.RED,
			]
		_:  # 4 joueurs
			return [
				GameEnums.PlayerColor.GREEN,
				GameEnums.PlayerColor.BLUE,
				GameEnums.PlayerColor.YELLOW,
				GameEnums.PlayerColor.RED,
			]

func _place_starting_units() -> void:
	## Place les unités de départ dans chaque QG.
	## Effectifs: 1 Drapeau, 2 Soldats, 2 Tanks, 2 Chasseurs, 2 Destroyers
	var colors_to_setup: Array[GameEnums.PlayerColor] = []

	match num_players:
		2:
			# Joueur 1: V + B, Joueur 2: J + R
			colors_to_setup = [
				GameEnums.PlayerColor.GREEN,
				GameEnums.PlayerColor.BLUE,
				GameEnums.PlayerColor.YELLOW,
				GameEnums.PlayerColor.RED,
			]
		3:
			colors_to_setup = [
				GameEnums.PlayerColor.GREEN,
				GameEnums.PlayerColor.BLUE,
				GameEnums.PlayerColor.YELLOW,  # Mercenaire
				GameEnums.PlayerColor.RED,
			]
		_:
			colors_to_setup = player_order.duplicate()

	for color in colors_to_setup:
		var prefix := board.get_territory_prefix(color)
		var hq_id := "HQ_" + prefix

		# Drapeau
		_create_and_place_unit(GameEnums.UnitType.FLAG, color, hq_id)

		# 2 Soldats
		for i in range(2):
			_create_and_place_unit(GameEnums.UnitType.SOLDIER, color, hq_id)

		# 2 Tanks
		for i in range(2):
			_create_and_place_unit(GameEnums.UnitType.TANK, color, hq_id)

		# 2 Chasseurs
		for i in range(2):
			_create_and_place_unit(GameEnums.UnitType.FIGHTER, color, hq_id)

		# 2 Destroyers
		for i in range(2):
			_create_and_place_unit(GameEnums.UnitType.DESTROYER, color, hq_id)

func _create_and_place_unit(unit_type: GameEnums.UnitType, color: GameEnums.PlayerColor, sector_id: String) -> UnitData:
	var unit := UnitData.new(unit_type, color, sector_id)
	all_units.append(unit)
	var sector := board.get_sector(sector_id)
	if sector:
		sector.units.append(unit)
	return unit

func get_player(color: GameEnums.PlayerColor) -> PlayerData:
	return players.get(color)

func get_current_arbiter() -> GameEnums.PlayerColor:
	return player_order[arbiter_index % player_order.size()]

func advance_arbiter() -> void:
	arbiter_index = (arbiter_index + 1) % player_order.size()

func get_active_players() -> Array[GameEnums.PlayerColor]:
	var active: Array[GameEnums.PlayerColor] = []
	for color in player_order:
		if not players[color].is_eliminated:
			active.append(color)
	return active

func get_all_units_on_board(color: GameEnums.PlayerColor) -> Array:
	var result := []
	for unit in all_units:
		if unit.owner == color and not unit.in_reserve and unit.sector_id != "":
			result.append(unit)
	return result

func get_units_at_sector(sector_id: String) -> Array:
	var sector := board.get_sector(sector_id)
	if sector:
		return sector.units.duplicate()
	return []

func move_unit(unit: UnitData, to_sector_id: String) -> void:
	# Retirer du secteur actuel
	if unit.sector_id != "":
		var old_sector := board.get_sector(unit.sector_id)
		if old_sector:
			var idx := old_sector.units.find(unit)
			if idx >= 0:
				old_sector.units.remove_at(idx)

	# Placer dans le nouveau secteur
	unit.sector_id = to_sector_id
	var new_sector := board.get_sector(to_sector_id)
	if new_sector:
		new_sector.units.append(unit)

func remove_unit(unit: UnitData) -> void:
	# Retirer du secteur
	if unit.sector_id != "":
		var old_sector := board.get_sector(unit.sector_id)
		if old_sector:
			var idx := old_sector.units.find(unit)
			if idx >= 0:
				old_sector.units.remove_at(idx)

	# Retirer de la réserve si applicable
	for player in players.values():
		var idx := player.reserve.find(unit)
		if idx >= 0:
			player.reserve.remove_at(idx)

	# Retirer de la liste globale
	var global_idx := all_units.find(unit)
	if global_idx >= 0:
		all_units.remove_at(global_idx)

func convert_unit(unit: UnitData, new_owner: GameEnums.PlayerColor) -> void:
	unit.owner = new_owner

func calculate_player_total_power(color: GameEnums.PlayerColor) -> int:
	var total := 0
	# Unités sur le plateau
	for unit in all_units:
		if unit.owner == color:
			total += unit.get_power()
	# Power en réserve
	if color in players:
		total += players[color].get_total_power_value()
	return total
