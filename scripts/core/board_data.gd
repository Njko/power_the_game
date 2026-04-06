class_name BoardData
extends RefCounted

## Graph complet du plateau de jeu Power.
## Le plateau est composé de :
## - 4 territoires de 9 secteurs chacun (grille 3x3, numérotés 0-8)
## - 4 Quartiers Généraux (HQ), un par territoire
## - 5 îles : IN (Nord), IS (Sud), IE (Est), IW (Ouest), IX (Centre)
## - 12 secteurs maritimes : S1 à S12
##
## Disposition du plateau 9×9 (vue de dessus) :
##
## Col:  0    1    2    3    4    5    6    7    8
## R0: HQ_V S5   S5   S5   IN   S1   S1   S1   HQ_B
## R1: S4   V0   V1   V2   S6   B0   B1   B2   S2
## R2: S4   V3   V4   V5   S6   B3   B4   B5   S2
## R3: S4   V6   V7   V8   S6   B6   B7   B8   S2
## R4: IW   S3   S3   S3   IX   S9   S9   S9   IE
## R5: S12  J0   J1   J2   S8   R0   R1   R2   S10
## R6: S12  J3   J4   J5   S8   R3   R4   R5   S10
## R7: S12  J6   J7   J8   S8   R6   R7   R8   S10
## R8: HQ_J S11  S11  S11  IS   S7   S7   S7   HQ_R
##
## Territoires: V=Vert (haut-gauche), B=Bleu (haut-droite),
##              J=Jaune (bas-gauche), R=Rouge (bas-droite)

var sectors: Dictionary = {}  # id -> Sector
var _grid_positions: Dictionary = {}  # id -> Vector2 (position grille logique)

func _init() -> void:
	_create_all_sectors()
	_create_all_adjacencies()

# ===== CREATION DES SECTEURS =====

func _create_all_sectors() -> void:
	_create_territory("V", GameEnums.PlayerColor.GREEN, Vector2(1, 1))
	_create_territory("B", GameEnums.PlayerColor.BLUE, Vector2(5, 1))
	_create_territory("J", GameEnums.PlayerColor.YELLOW, Vector2(1, 5))
	_create_territory("R", GameEnums.PlayerColor.RED, Vector2(5, 5))

	_create_hqs()
	_create_islands()
	_create_sea_sectors()

func _create_territory(prefix: String, color: GameEnums.PlayerColor, origin: Vector2) -> void:
	for i in range(9):
		var col := i % 3
		var row := i / 3
		var pos := origin + Vector2(col, row)
		var sector_type: GameEnums.SectorType
		if i == 4:
			sector_type = GameEnums.SectorType.LAND  # Centre: inaccessible aux navires
		else:
			sector_type = GameEnums.SectorType.COASTAL
		var id := "%s%d" % [prefix, i]
		var sector := Sector.new(id, sector_type, color, pos, "%s %d" % [prefix, i])
		sectors[id] = sector
		_grid_positions[id] = pos

func _create_hqs() -> void:
	var hq_data := [
		["HQ_V", GameEnums.PlayerColor.GREEN, Vector2(0, 0)],
		["HQ_B", GameEnums.PlayerColor.BLUE, Vector2(8, 0)],
		["HQ_J", GameEnums.PlayerColor.YELLOW, Vector2(0, 8)],
		["HQ_R", GameEnums.PlayerColor.RED, Vector2(8, 8)],
	]
	for data in hq_data:
		var id: String = data[0]
		var color: GameEnums.PlayerColor = data[1] as GameEnums.PlayerColor
		var pos: Vector2 = data[2]
		var sector = Sector.new(id, GameEnums.SectorType.HQ, color, pos, id)
		sectors[id] = sector
		_grid_positions[id] = pos

func _create_islands() -> void:
	var island_data := [
		["IN", Vector2(4, 0)],    # Île Nord (entre V et B)
		["IS", Vector2(4, 8)],    # Île Sud (entre J et R)
		["IW", Vector2(0, 4)],    # Île Ouest (entre V et J)
		["IE", Vector2(8, 4)],    # Île Est (entre B et R)
		["IX", Vector2(4, 4)],    # Île Centre
	]
	for data in island_data:
		var id: String = data[0]
		var pos: Vector2 = data[1]
		var sector = Sector.new(id, GameEnums.SectorType.ISLAND, GameEnums.PlayerColor.NONE, pos, id)
		sectors[id] = sector
		_grid_positions[id] = pos

func _create_sea_sectors() -> void:
	var sea_data := [
		# Canal Nord
		["S5", Vector2(2, 0)],    # Bande horizontale 3×1
		["S1", Vector2(6, 0)],    # Bande horizontale 3×1
		["S6", Vector2(4, 2)],    # Bande verticale 1×3

		# Canal Ouest
		["S4", Vector2(0, 2)],    # Bande verticale 1×3
		["S12", Vector2(0, 6)],   # Bande verticale 1×3
		["S3", Vector2(2, 4)],    # Bande horizontale 3×1

		# Canal Est
		["S2", Vector2(8, 2)],    # Bande verticale 1×3
		["S10", Vector2(8, 6)],   # Bande verticale 1×3
		["S9", Vector2(6, 4)],    # Bande horizontale 3×1

		# Canal Sud
		["S11", Vector2(2, 8)],   # Bande horizontale 3×1
		["S7", Vector2(6, 8)],    # Bande horizontale 3×1
		["S8", Vector2(4, 6)],    # Bande verticale 1×3
	]
	for data in sea_data:
		var id: String = data[0]
		var pos: Vector2 = data[1]
		var sector = Sector.new(id, GameEnums.SectorType.SEA, GameEnums.PlayerColor.NONE, pos, id)
		sectors[id] = sector
		_grid_positions[id] = pos

# ===== CREATION DES ADJACENCES =====

func _create_all_adjacencies() -> void:
	_create_territory_internal_adjacencies("V")
	_create_territory_internal_adjacencies("B")
	_create_territory_internal_adjacencies("J")
	_create_territory_internal_adjacencies("R")

	_create_hq_adjacencies()
	_create_territory_sea_adjacencies()
	_create_sea_island_adjacencies()

func _create_territory_internal_adjacencies(prefix: String) -> void:
	# Grille 3x3 avec déplacement diagonal:
	# 0 1 2
	# 3 4 5
	# 6 7 8
	var adj_map := {
		0: [1, 3, 4],
		1: [0, 2, 3, 4, 5],
		2: [1, 4, 5],
		3: [0, 1, 4, 6, 7],
		4: [0, 1, 2, 3, 5, 6, 7, 8],  # Centre: adjacent à tout
		5: [1, 2, 4, 7, 8],
		6: [3, 4, 7],
		7: [3, 4, 5, 6, 8],
		8: [4, 5, 7],
	}
	for sector_num: int in adj_map:
		var id: String = "%s%d" % [prefix, sector_num]
		for neighbor_num: int in adj_map[sector_num]:
			var neighbor_id: String = "%s%d" % [prefix, neighbor_num]
			_add_adjacency(id, neighbor_id)

func _create_hq_adjacencies() -> void:
	# Chaque QG est adjacent au secteur de coin de son territoire
	# et aux 2 secteurs maritimes les plus proches
	_add_adjacency("HQ_V", "V0")
	_add_adjacency("HQ_V", "S5")
	_add_adjacency("HQ_V", "S4")

	_add_adjacency("HQ_B", "B2")
	_add_adjacency("HQ_B", "S1")
	_add_adjacency("HQ_B", "S2")

	_add_adjacency("HQ_J", "J6")
	_add_adjacency("HQ_J", "S12")
	_add_adjacency("HQ_J", "S11")

	_add_adjacency("HQ_R", "R8")
	_add_adjacency("HQ_R", "S7")
	_add_adjacency("HQ_R", "S10")

func _create_territory_sea_adjacencies() -> void:
	# --- Territoire VERT (haut-gauche) à (1,1)-(3,3) ---
	# Bord haut (row 1) → S5 (row 0, cols 1-3)
	_add_adjacency("V0", "S5")
	_add_adjacency("V1", "S5")
	_add_adjacency("V2", "S5")
	# Bord droit (col 3) → S6 (col 4, rows 1-3)
	_add_adjacency("V2", "S6")  # V2(3,1) ↔ S6(4,1-3)
	_add_adjacency("V5", "S6")  # V5(3,2) ↔ S6(4,1-3)
	_add_adjacency("V8", "S6")  # V8(3,3) ↔ S6(4,1-3)
	# Bord gauche (col 1) → S4 (col 0, rows 1-3)
	_add_adjacency("V0", "S4")
	_add_adjacency("V3", "S4")
	_add_adjacency("V6", "S4")
	# Bord bas (row 3) → S3 (row 4, cols 1-3) et IW (col 0, row 4)
	_add_adjacency("V6", "S3")  # V6(1,3) ↔ S3(1-3,4)
	_add_adjacency("V6", "IW")  # V6(1,3) ↔ IW(0,4)
	_add_adjacency("V7", "S3")  # V7(2,3) ↔ S3(1-3,4)
	_add_adjacency("V8", "S3")  # V8(3,3) ↔ S3(1-3,4)

	# --- Territoire BLEU (haut-droite) à (5,1)-(7,3) ---
	# Bord haut (row 1) → S1 (row 0, cols 5-7)
	_add_adjacency("B0", "S1")
	_add_adjacency("B1", "S1")
	_add_adjacency("B2", "S1")
	# Bord gauche (col 5) → S6 (col 4, rows 1-3)
	_add_adjacency("B0", "S6")  # B0(5,1) ↔ S6(4,1-3)
	_add_adjacency("B3", "S6")  # B3(5,2) ↔ S6(4,1-3)
	_add_adjacency("B6", "S6")  # B6(5,3) ↔ S6(4,1-3)
	# Bord droit (col 7) → S2 (col 8, rows 1-3)
	_add_adjacency("B2", "S2")
	_add_adjacency("B5", "S2")
	_add_adjacency("B8", "S2")
	# Bord bas (row 3) → S9 (row 4, cols 5-7) et IE (col 8, row 4)
	_add_adjacency("B6", "S9")  # B6(5,3) ↔ S9(5-7,4)
	_add_adjacency("B7", "S9")  # B7(6,3) ↔ S9(5-7,4)
	_add_adjacency("B8", "S9")  # B8(7,3) ↔ S9(5-7,4)
	_add_adjacency("B8", "IE")  # B8(7,3) ↔ IE(8,4)

	# --- Territoire JAUNE (bas-gauche) à (1,5)-(3,7) ---
	# Bord gauche (col 1) → S12 (col 0, rows 5-7)
	_add_adjacency("J0", "S12")
	_add_adjacency("J3", "S12")
	_add_adjacency("J6", "S12")
	# Bord haut (row 5) → S3 (row 4, cols 1-3) et IW (col 0, row 4)
	_add_adjacency("J0", "S3")  # J0(1,5) ↔ S3(1-3,4)
	_add_adjacency("J0", "IW")  # J0(1,5) ↔ IW(0,4)
	_add_adjacency("J1", "S3")  # J1(2,5) ↔ S3(1-3,4)
	_add_adjacency("J2", "S3")  # J2(3,5) ↔ S3(1-3,4)
	# Bord droit (col 3) → S8 (col 4, rows 5-7)
	_add_adjacency("J2", "S8")  # J2(3,5) ↔ S8(4,5-7)
	_add_adjacency("J5", "S8")  # J5(3,6) ↔ S8(4,5-7)
	_add_adjacency("J8", "S8")  # J8(3,7) ↔ S8(4,5-7)
	# Bord bas (row 7) → S11 (row 8, cols 1-3)
	_add_adjacency("J6", "S11")
	_add_adjacency("J7", "S11")
	_add_adjacency("J8", "S11")

	# --- Territoire ROUGE (bas-droite) à (5,5)-(7,7) ---
	# Bord haut (row 5) → S9 (row 4, cols 5-7) et IE (col 8, row 4)
	_add_adjacency("R0", "S9")  # R0(5,5) ↔ S9(5-7,4)
	_add_adjacency("R1", "S9")  # R1(6,5) ↔ S9(5-7,4)
	_add_adjacency("R2", "S9")  # R2(7,5) ↔ S9(5-7,4)
	_add_adjacency("R2", "IE")  # R2(7,5) ↔ IE(8,4)
	# Bord gauche (col 5) → S8 (col 4, rows 5-7)
	_add_adjacency("R0", "S8")  # R0(5,5) ↔ S8(4,5-7)
	_add_adjacency("R3", "S8")  # R3(5,6) ↔ S8(4,5-7)
	_add_adjacency("R6", "S8")  # R6(5,7) ↔ S8(4,5-7)
	# Bord droit (col 7) → S10 (col 8, rows 5-7)
	_add_adjacency("R2", "S10")
	_add_adjacency("R5", "S10")
	_add_adjacency("R8", "S10")
	# Bord bas (row 7) → S7 (row 8, cols 5-7)
	_add_adjacency("R6", "S7")
	_add_adjacency("R7", "S7")
	_add_adjacency("R8", "S7")

func _create_sea_island_adjacencies() -> void:
	# --- Canal Nord ---
	_add_adjacency("S5", "IN")
	_add_adjacency("IN", "S1")
	_add_adjacency("IN", "S6")
	_add_adjacency("S5", "S6")
	_add_adjacency("S1", "S6")

	# --- Canal Ouest ---
	_add_adjacency("S4", "IW")
	_add_adjacency("IW", "S12")
	_add_adjacency("IW", "S3")
	_add_adjacency("S4", "S3")
	_add_adjacency("S12", "S3")

	# --- Canal Est ---
	_add_adjacency("S2", "IE")
	_add_adjacency("IE", "S10")
	_add_adjacency("IE", "S9")
	_add_adjacency("S2", "S9")
	_add_adjacency("S10", "S9")

	# --- Canal Sud ---
	_add_adjacency("S11", "IS")
	_add_adjacency("IS", "S7")
	_add_adjacency("IS", "S8")
	_add_adjacency("S11", "S8")
	_add_adjacency("S7", "S8")

	# --- Anneau intérieur autour de IX ---
	_add_adjacency("S6", "IX")
	_add_adjacency("S3", "IX")
	_add_adjacency("S8", "IX")
	_add_adjacency("S9", "IX")
	_add_adjacency("S6", "S3")
	_add_adjacency("S6", "S9")
	_add_adjacency("S3", "S8")
	_add_adjacency("S8", "S9")

	# --- Connexions coin extérieur (via zones HQ) ---
	_add_adjacency("S5", "S4")   # Coin HQ_V
	_add_adjacency("S1", "S2")   # Coin HQ_B
	_add_adjacency("S12", "S11") # Coin HQ_J
	_add_adjacency("S7", "S10")  # Coin HQ_R

func _add_adjacency(id_a: String, id_b: String) -> void:
	if id_a in sectors and id_b in sectors:
		sectors[id_a].add_adjacent(id_b)
		sectors[id_b].add_adjacent(id_a)

# ===== METHODES UTILITAIRES =====

func get_sector(id: String) -> Sector:
	return sectors.get(id)

func get_territory_sectors(color: GameEnums.PlayerColor) -> Array[Sector]:
	var result: Array[Sector] = []
	for sector in sectors.values():
		if sector.owner_territory == color and sector.sector_type != GameEnums.SectorType.HQ:
			result.append(sector)
	return result

func get_hq(color: GameEnums.PlayerColor) -> Sector:
	var prefix := _get_territory_prefix(color)
	return sectors.get("HQ_" + prefix)

func get_territory_prefix(color: GameEnums.PlayerColor) -> String:
	return _get_territory_prefix(color)

func _get_territory_prefix(color: GameEnums.PlayerColor) -> String:
	match color:
		GameEnums.PlayerColor.GREEN: return "V"
		GameEnums.PlayerColor.BLUE: return "B"
		GameEnums.PlayerColor.YELLOW: return "J"
		GameEnums.PlayerColor.RED: return "R"
		_: return ""

## Trouve le plus court chemin entre deux secteurs pour un type d'unité donné.
## Retourne la liste des IDs de secteurs (incluant départ et arrivée),
## ou un tableau vide si aucun chemin n'existe.
func find_path(from_id: String, to_id: String, unit_type: GameEnums.UnitType) -> Array[String]:
	if from_id == to_id:
		return [from_id]

	var visited: Dictionary = {}
	var queue: Array = [[from_id]]
	visited[from_id] = true

	while queue.size() > 0:
		var path: Array = queue.pop_front()
		var current: String = path[-1]
		var sector: Sector = sectors.get(current)
		if sector == null:
			continue

		for neighbor_id in sector.adjacent_sectors:
			if neighbor_id in visited:
				continue
			var neighbor: Sector = sectors.get(neighbor_id)
			if neighbor == null:
				continue
			if not neighbor.is_accessible_by(unit_type):
				# Exception: les avions peuvent SURVOLER les îles sans s'y arrêter
				# mais on gère ça au niveau du moteur de jeu, pas ici
				continue

			var new_path: Array = path.duplicate()
			new_path.append(neighbor_id)

			if neighbor_id == to_id:
				var result: Array[String] = []
				for s in new_path:
					result.append(s)
				return result

			visited[neighbor_id] = true
			queue.append(new_path)

	return []

## Calcule la distance (nombre de pas) entre deux secteurs pour un type d'unité.
## Retourne -1 si pas de chemin.
func get_distance(from_id: String, to_id: String, unit_type: GameEnums.UnitType) -> int:
	var path := find_path(from_id, to_id, unit_type)
	if path.is_empty():
		return -1
	return path.size() - 1

## Retourne tous les secteurs atteignables depuis from_id en max_steps pas.
func get_reachable_sectors(from_id: String, unit_type: GameEnums.UnitType, max_steps: int) -> Array[String]:
	var result: Array[String] = []
	var visited: Dictionary = {}
	var queue: Array = [[from_id, 0]]
	visited[from_id] = true

	while queue.size() > 0:
		var entry: Array = queue.pop_front()
		var current_id: String = entry[0]
		var steps: int = entry[1]

		if steps > 0:
			result.append(current_id)

		if steps >= max_steps:
			continue

		var sector: Sector = sectors.get(current_id)
		if sector == null:
			continue

		# Règle d'arrêt: les unités terrestres ne peuvent pas traverser
		# une île ou un QG dans le même tour (elles doivent s'y arrêter).
		# Si on vient d'entrer sur une île/QG (steps > 0 et ce n'est pas le départ),
		# on ne peut pas continuer ce tour.
		var est_terrestre: bool = GameEnums.is_land_unit(unit_type)
		if est_terrestre and steps > 0 and current_id != from_id:
			if sector.sector_type == GameEnums.SectorType.ISLAND or sector.sector_type == GameEnums.SectorType.HQ:
				continue  # Arrêt forcé, pas d'exploration au-delà

		for neighbor_id in sector.adjacent_sectors:
			if neighbor_id in visited:
				continue
			var neighbor: Sector = sectors.get(neighbor_id)
			if neighbor == null:
				continue
			if not neighbor.is_accessible_by(unit_type):
				continue

			visited[neighbor_id] = true
			queue.append([neighbor_id, steps + 1])

	return result

func get_grid_position(sector_id: String) -> Vector2:
	return _grid_positions.get(sector_id, Vector2.ZERO)
