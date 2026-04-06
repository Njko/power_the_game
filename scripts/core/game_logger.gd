class_name GameLogger
extends RefCounted

## Journal de partie structuré, écrit tour par tour dans user://game_log.txt.

var _actif: bool
var _lignes: Array[String] = []
var _messages_tour: Array[String] = []
var _snapshot_debut: Dictionary = {}  # PlayerColor -> {board_power: int, reserve_count: int}

func _init(actif: bool = true) -> void:
	_actif = actif
	if not _actif:
		return
	var fichier := FileAccess.open("user://game_log.txt", FileAccess.WRITE)
	if fichier:
		var horodatage: String = Time.get_datetime_string_from_system(false, true)
		fichier.store_line("=== Journal de partie Power — %s ===" % horodatage)
		fichier.store_line("")
		fichier.close()

func log_debut_tour(tour: int, game_state: GameState) -> void:
	if not _actif:
		return
	_lignes.clear()
	_messages_tour.clear()

	_lignes.append("========== TOUR %d ==========" % tour)
	_lignes.append("[ÉTAT DÉBUT DE TOUR]")
	_ecrire_snapshot(game_state)
	_ecrire_positions_detaillees(game_state)

	# Stocker snapshot pour le diff
	_snapshot_debut = _snapshot_joueurs(game_state)

func log_message(message: String) -> void:
	if not _actif:
		return
	_messages_tour.append(message)

func log_fin_tour(tour: int, game_state: GameState) -> void:
	if not _actif:
		return

	# Messages accumulés
	_lignes.append("[MESSAGES]")
	for msg in _messages_tour:
		_lignes.append("  %s" % msg)

	# État fin de tour
	_lignes.append("[ÉTAT FIN DE TOUR]")
	_ecrire_snapshot(game_state)

	# Diff
	var snapshot_fin: Dictionary = _snapshot_joueurs(game_state)
	_lignes.append("[DIFF]")
	for color in game_state.player_order:
		var player: PlayerData = game_state.get_player(color)
		var nom: String = _nom_couleur(color)
		if player.is_eliminated:
			if not _snapshot_debut.has(color) or _snapshot_debut[color].get("elimine", false):
				continue
			_lignes.append("  %s: éliminé ce tour" % nom)
			continue
		if not _snapshot_debut.has(color):
			continue
		var debut: Dictionary = _snapshot_debut[color]
		if debut.get("elimine", false):
			continue
		var fin: Dictionary = snapshot_fin.get(color, {})
		var bp_avant: int = debut.get("board_power", 0)
		var bp_apres: int = fin.get("board_power", 0)
		var rv_avant: int = debut.get("reserve_count", 0)
		var rv_apres: int = fin.get("reserve_count", 0)
		var diff_bp: int = bp_apres - bp_avant
		var diff_rv: int = rv_apres - rv_avant
		var signe_bp: String = "+" if diff_bp >= 0 else ""
		var signe_rv: String = "+" if diff_rv >= 0 else ""
		_lignes.append("  %s: power plateau %d→%d (%s%d), réserve %d→%d (%s%d)" % [
			nom, bp_avant, bp_apres, signe_bp, diff_bp,
			rv_avant, rv_apres, signe_rv, diff_rv])

	_lignes.append("")
	_ecrire_fichier()

# --- Helpers privés ---

func _ecrire_snapshot(game_state: GameState) -> void:
	for color in game_state.player_order:
		var player: PlayerData = game_state.get_player(color)
		var nom: String = _nom_couleur(color)
		if player.is_eliminated:
			_lignes.append("  %s: éliminé" % nom)
			continue

		var nb_plateau: int = 0
		var power_plateau: int = 0
		var nb_reserve: int = 0
		for unit in game_state.all_units:
			if unit.owner != color:
				continue
			if unit.unit_type == GameEnums.UnitType.FLAG or unit.unit_type == GameEnums.UnitType.POWER:
				continue
			if unit.in_reserve:
				nb_reserve += 1
			elif unit.sector_id != "":
				nb_plateau += 1
				power_plateau += GameEnums.get_unit_power(unit.unit_type)

		# Contenu du QG
		var prefix: String = game_state.board.get_territory_prefix(color)
		var hq_id: String = "HQ_" + prefix
		var hq_sector: Sector = game_state.board.get_sector(hq_id)
		var hq_desc: String = "vide"
		if hq_sector:
			var hq_parts: Array[String] = []
			for unit in hq_sector.units:
				if unit.owner == color and unit.unit_type != GameEnums.UnitType.FLAG and unit.unit_type != GameEnums.UnitType.POWER:
					hq_parts.append("%s(%d)" % [GameEnums.get_unit_name(unit.unit_type), GameEnums.get_unit_power(unit.unit_type)])
			if hq_parts.size() > 0:
				hq_desc = ", ".join(hq_parts)

		_lignes.append("  %s: %d unités plateau (power=%d), %d réserve | QG: %s" % [
			nom, nb_plateau, power_plateau, nb_reserve, hq_desc])

func _ecrire_positions_detaillees(game_state: GameState) -> void:
	_lignes.append("  [Positions détaillées]")
	var secteurs_ids: Array = game_state.board.sectors.keys()
	secteurs_ids.sort()
	for sector_id in secteurs_ids:
		var sector: Sector = game_state.board.get_sector(sector_id)
		if sector.units.size() == 0:
			continue
		var parties: Array[String] = []
		for unit in sector.units:
			if unit.unit_type == GameEnums.UnitType.FLAG or unit.unit_type == GameEnums.UnitType.POWER:
				continue
			parties.append("%s(%s)" % [GameEnums.get_unit_name(unit.unit_type), _nom_couleur(unit.owner)])
		if parties.size() > 0:
			_lignes.append("    %s: %s" % [sector_id, ", ".join(parties)])

func _snapshot_joueurs(game_state: GameState) -> Dictionary:
	var result: Dictionary = {}
	for color in game_state.player_order:
		var player: PlayerData = game_state.get_player(color)
		if player.is_eliminated:
			result[color] = {"elimine": true, "board_power": 0, "reserve_count": 0}
			continue
		var board_power: int = 0
		var reserve_count: int = 0
		for unit in game_state.all_units:
			if unit.owner != color:
				continue
			if unit.unit_type == GameEnums.UnitType.FLAG or unit.unit_type == GameEnums.UnitType.POWER:
				continue
			if unit.in_reserve:
				reserve_count += 1
			elif unit.sector_id != "":
				board_power += GameEnums.get_unit_power(unit.unit_type)
		result[color] = {"elimine": false, "board_power": board_power, "reserve_count": reserve_count}
	return result

func _ecrire_fichier() -> void:
	var fichier := FileAccess.open("user://game_log.txt", FileAccess.READ_WRITE)
	if fichier:
		fichier.seek_end(0)
		for ligne in _lignes:
			fichier.store_line(ligne)
		fichier.close()
	_lignes.clear()

func _nom_couleur(c: GameEnums.PlayerColor) -> String:
	match c:
		GameEnums.PlayerColor.GREEN: return "Vert"
		GameEnums.PlayerColor.BLUE: return "Bleu"
		GameEnums.PlayerColor.YELLOW: return "Jaune"
		GameEnums.PlayerColor.RED: return "Rouge"
		_: return "?"
