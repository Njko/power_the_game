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
## Secteur 0 = coin le plus proche de IX (centre), secteur 8 = coin le plus proche du QG.
##
## Numérotation diagonale par territoire (depuis coin IX):
##   0  2  5     Secteur 0 = coin le plus proche de IX (4,4)
##   1  4  7     Secteur 4 = centre (LAND, inaccessible navires)
##   3  6  8     Secteur 8 = coin le plus proche du QG
##
## Chaque territoire applique un flip pour orienter le secteur 0 vers IX:
##   V (haut-gauche): flip XY → V0 en bas-droite (3,3)
##   B (haut-droite): flip Y  → B0 en bas-gauche (5,3)
##   J (bas-gauche):  flip X  → J0 en haut-droite (3,5)
##   R (bas-droite):  aucun   → R0 en haut-gauche (5,5)

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
	# flip_x/flip_y pour que secteur 0 soit au coin le plus proche de IX (4,4)
	_create_territory("V", GameEnums.PlayerColor.GREEN, Vector2(1, 1), true, true)    # QG en haut-gauche → flip les deux axes
	_create_territory("B", GameEnums.PlayerColor.BLUE, Vector2(5, 1), false, true)    # QG en haut-droite → flip Y seulement
	_create_territory("J", GameEnums.PlayerColor.YELLOW, Vector2(1, 5), true, false)  # QG en bas-gauche → flip X seulement
	_create_territory("R", GameEnums.PlayerColor.RED, Vector2(5, 5), false, false)    # QG en bas-droite → aucun flip

	_create_hqs()
	_create_islands()
	_create_sea_sectors()

## Mapping secteur → position locale (col, row) dans la grille 3×3.
## Numérotation diagonale depuis le coin IX (0,0) :
##   0  2  5
##   1  4  7
##   3  6  8
const SECTOR_LOCAL_POS := [
	Vector2(0, 0),  # 0
	Vector2(0, 1),  # 1
	Vector2(1, 0),  # 2
	Vector2(0, 2),  # 3
	Vector2(1, 1),  # 4 (centre)
	Vector2(2, 0),  # 5
	Vector2(1, 2),  # 6
	Vector2(2, 1),  # 7
	Vector2(2, 2),  # 8
]

func _create_territory(prefix: String, color: GameEnums.PlayerColor, origin: Vector2, flip_x: bool, flip_y: bool) -> void:
	for i in range(9):
		var local: Vector2 = SECTOR_LOCAL_POS[i]
		var col: int = int(local.x)
		var row: int = int(local.y)
		if flip_x:
			col = 2 - col
		if flip_y:
			row = 2 - row
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
	# Grille 3x3 avec numérotation diagonale et déplacement diagonal:
	# 0  2  5
	# 1  4  7
	# 3  6  8
	# Adjacences basées sur les positions (col, row) de SECTOR_LOCAL_POS
	var adj_map := {
		0: [1, 2, 4],           # (0,0) ↔ (0,1), (1,0), (1,1)
		1: [0, 2, 3, 4, 6],    # (0,1) ↔ (0,0), (1,0), (0,2), (1,1), (1,2)
		2: [0, 1, 4, 5, 7],    # (1,0) ↔ (0,0), (0,1), (1,1), (2,0), (2,1)
		3: [1, 4, 6],           # (0,2) ↔ (0,1), (1,1), (1,2)
		4: [0, 1, 2, 3, 5, 6, 7, 8],  # (1,1) centre: adjacent à tout
		5: [2, 4, 7],           # (2,0) ↔ (1,0), (1,1), (2,1)
		6: [1, 3, 4, 7, 8],    # (1,2) ↔ (0,1), (0,2), (1,1), (2,1), (2,2)
		7: [2, 4, 5, 6, 8],    # (2,1) ↔ (1,0), (1,1), (2,0), (1,2), (2,2)
		8: [4, 6, 7],           # (2,2) ↔ (1,1), (1,2), (2,1)
	}
	for sector_num: int in adj_map:
		var id: String = "%s%d" % [prefix, sector_num]
		for neighbor_num: int in adj_map[sector_num]:
			var neighbor_id: String = "%s%d" % [prefix, neighbor_num]
			_add_adjacency(id, neighbor_id)

func _create_hq_adjacencies() -> void:
	# Chaque QG est adjacent au secteur 8 de son territoire (coin le plus proche du QG)
	# et aux 2 secteurs maritimes les plus proches
	_add_adjacency("HQ_V", "V8")   # V8 à (1,1), coin le plus proche de HQ_V(0,0)
	_add_adjacency("HQ_V", "S5")
	_add_adjacency("HQ_V", "S4")

	_add_adjacency("HQ_B", "B8")   # B8 à (7,1), coin le plus proche de HQ_B(8,0)
	_add_adjacency("HQ_B", "S1")
	_add_adjacency("HQ_B", "S2")

	_add_adjacency("HQ_J", "J8")   # J8 à (1,7), coin le plus proche de HQ_J(0,8)
	_add_adjacency("HQ_J", "S12")
	_add_adjacency("HQ_J", "S11")

	_add_adjacency("HQ_R", "R8")   # R8 à (7,7), coin le plus proche de HQ_R(8,8)
	_add_adjacency("HQ_R", "S7")
	_add_adjacency("HQ_R", "S10")

func _create_territory_sea_adjacencies() -> void:
	# Positions après numérotation diagonale + flips:
	# V (flip XY): V8(1,1) V6(2,1) V3(3,1) / V7(1,2) V4(2,2) V1(3,2) / V5(1,3) V2(2,3) V0(3,3)
	# B (flip Y):  B3(5,1) B6(6,1) B8(7,1) / B1(5,2) B4(6,2) B7(7,2) / B0(5,3) B2(6,3) B5(7,3)
	# J (flip X):  J5(1,5) J2(2,5) J0(3,5) / J7(1,6) J4(2,6) J1(3,6) / J8(1,7) J6(2,7) J3(3,7)
	# R (aucun):   R0(5,5) R2(6,5) R5(7,5) / R1(5,6) R4(6,6) R7(7,6) / R3(5,7) R6(6,7) R8(7,7)

	# --- Territoire VERT ---
	# Bord haut (row 1) → S5, IN
	_add_adjacency("V8", "S5")   # (1,1)
	_add_adjacency("V6", "S5")   # (2,1)
	_add_adjacency("V3", "S5")   # (3,1)
	_add_adjacency("V3", "IN")   # (3,1) ↔ IN(4,0) diagonale
	# Bord gauche (col 1) → S4
	_add_adjacency("V8", "S4")   # (1,1)
	_add_adjacency("V7", "S4")   # (1,2)
	_add_adjacency("V5", "S4")   # (1,3)
	# Bord droit (col 3) → S6
	_add_adjacency("V3", "S6")   # (3,1)
	_add_adjacency("V1", "S6")   # (3,2)
	_add_adjacency("V0", "S6")   # (3,3)
	# Bord bas (row 3) → S3, IW, IX
	_add_adjacency("V5", "S3")   # (1,3)
	_add_adjacency("V5", "IW")   # (1,3) ↔ IW(0,4) diagonale
	_add_adjacency("V2", "S3")   # (2,3)
	_add_adjacency("V0", "S3")   # (3,3)
	_add_adjacency("V0", "IX")   # (3,3) ↔ IX(4,4) diagonale

	# --- Territoire BLEU ---
	# Bord haut (row 1) → S1, IN
	_add_adjacency("B3", "S1")   # (5,1)
	_add_adjacency("B3", "IN")   # (5,1) ↔ IN(4,0) diagonale
	_add_adjacency("B6", "S1")   # (6,1)
	_add_adjacency("B8", "S1")   # (7,1)
	# Bord gauche (col 5) → S6
	_add_adjacency("B3", "S6")   # (5,1)
	_add_adjacency("B1", "S6")   # (5,2)
	_add_adjacency("B0", "S6")   # (5,3)
	# Bord droit (col 7) → S2
	_add_adjacency("B8", "S2")   # (7,1)
	_add_adjacency("B7", "S2")   # (7,2)
	_add_adjacency("B5", "S2")   # (7,3)
	# Bord bas (row 3) → S9, IX, IE
	_add_adjacency("B0", "S9")   # (5,3)
	_add_adjacency("B0", "IX")   # (5,3) ↔ IX(4,4) diagonale
	_add_adjacency("B2", "S9")   # (6,3)
	_add_adjacency("B5", "S9")   # (7,3)
	_add_adjacency("B5", "IE")   # (7,3) ↔ IE(8,4) diagonale

	# --- Territoire JAUNE ---
	# Bord haut (row 5) → S3, IW, IX
	_add_adjacency("J5", "S3")   # (1,5)
	_add_adjacency("J5", "IW")   # (1,5) ↔ IW(0,4) diagonale
	_add_adjacency("J2", "S3")   # (2,5)
	_add_adjacency("J0", "S3")   # (3,5)
	_add_adjacency("J0", "IX")   # (3,5) ↔ IX(4,4) diagonale
	# Bord gauche (col 1) → S12
	_add_adjacency("J5", "S12")  # (1,5)
	_add_adjacency("J7", "S12")  # (1,6)
	_add_adjacency("J8", "S12")  # (1,7)
	# Bord droit (col 3) → S8
	_add_adjacency("J0", "S8")   # (3,5)
	_add_adjacency("J1", "S8")   # (3,6)
	_add_adjacency("J3", "S8")   # (3,7)
	# Bord bas (row 7) → S11, IS
	_add_adjacency("J8", "S11")  # (1,7)
	_add_adjacency("J6", "S11")  # (2,7)
	_add_adjacency("J3", "S11")  # (3,7)
	_add_adjacency("J3", "IS")   # (3,7) ↔ IS(4,8) diagonale

	# --- Territoire ROUGE (aucun flip) ---
	# Bord haut (row 5) → S9, IX, IE
	_add_adjacency("R0", "S9")   # (5,5)
	_add_adjacency("R0", "IX")   # (5,5) ↔ IX(4,4) diagonale
	_add_adjacency("R2", "S9")   # (6,5)
	_add_adjacency("R5", "S9")   # (7,5)
	_add_adjacency("R5", "IE")   # (7,5) ↔ IE(8,4) diagonale
	# Bord gauche (col 5) → S8
	_add_adjacency("R0", "S8")   # (5,5)
	_add_adjacency("R1", "S8")   # (5,6)
	_add_adjacency("R3", "S8")   # (5,7)
	# Bord droit (col 7) → S10
	_add_adjacency("R5", "S10")  # (7,5)
	_add_adjacency("R7", "S10")  # (7,6)
	_add_adjacency("R8", "S10")  # (7,7)
	# Bord bas (row 7) → S7, IS
	_add_adjacency("R3", "S7")   # (5,7)
	_add_adjacency("R3", "IS")   # (5,7) ↔ IS(4,8) diagonale
	_add_adjacency("R6", "S7")   # (6,7)
	_add_adjacency("R8", "S7")   # (7,7)

func _create_sea_island_adjacencies() -> void:
	# Règle: on ne peut pas passer d'un secteur maritime à un autre directement.
	# Il faut passer par une île ou un secteur côtier de territoire.
	# Seules les connexions S↔île sont conservées.

	# --- Canal Nord ---
	_add_adjacency("S5", "IN")
	_add_adjacency("IN", "S1")
	_add_adjacency("IN", "S6")

	# --- Canal Ouest ---
	_add_adjacency("S4", "IW")
	_add_adjacency("IW", "S12")
	_add_adjacency("IW", "S3")

	# --- Canal Est ---
	_add_adjacency("S2", "IE")
	_add_adjacency("IE", "S10")
	_add_adjacency("IE", "S9")

	# --- Canal Sud ---
	_add_adjacency("S11", "IS")
	_add_adjacency("IS", "S7")
	_add_adjacency("IS", "S8")

	# --- Anneau intérieur autour de IX ---
	_add_adjacency("S6", "IX")
	_add_adjacency("S3", "IX")
	_add_adjacency("S8", "IX")
	_add_adjacency("S9", "IX")

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
