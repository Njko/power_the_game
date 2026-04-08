extends Node2D
class_name BoardRenderer

## Rendu visuel du plateau de jeu Power - version polie.


const CELL_SIZE := 55.0
const CELL_PADDING := 2.0
# La grille va de (0,0) à (8,8) — plateau 9×9 avec bandes maritimes
# Pour SubViewport 1024x1024: centrer la grille sur GRID_CENTER=(4.0, 4.0)
# Le pixel (512, 512) correspond à la position 3D (0,0,0) = grille (4.0, 4.0)
const BOARD_ORIGIN := Vector2(512 - 4.0 * 55.0 - 27.5, 512 - 4.0 * 55.0 - 27.5)  # (264.5, 264.5)
const CORNER_RADIUS := 6.0

# Palette
const COLOR_SEA_DEEP := Color(0.10, 0.22, 0.45)
const COLOR_SEA_LIGHT := Color(0.18, 0.35, 0.60)
const COLOR_ISLAND := Color(0.45, 0.68, 0.38)
const COLOR_ISLAND_EDGE := Color(0.35, 0.55, 0.30)
const COLOR_HQ_GLOW := Color(1.0, 0.85, 0.3, 0.7)
const COLOR_GRID_LINE := Color(0.0, 0.0, 0.0, 0.15)
const COLOR_HIGHLIGHT := Color(1.0, 1.0, 0.4, 0.35)
const COLOR_SELECTED := Color(0.3, 1.0, 0.3, 0.45)
const COLOR_REACHABLE := Color(0.3, 0.6, 1.0, 0.25)
const COLOR_LABEL_SHADOW := Color(0, 0, 0, 0.5)
const COLOR_LABEL := Color(0.95, 0.95, 0.95)
const COLOR_LABEL_DARK := Color(0.15, 0.15, 0.15)
const COLOR_SAND := Color(0.82, 0.75, 0.55)
const COLOR_WAVE_COAST := Color(0.3, 0.5, 0.8, 0.25)

# Couleurs de territoire (base + bordure)
const TERRITORY_COLORS := {
	"V": [Color(0.28, 0.62, 0.28), Color(0.20, 0.48, 0.20)],  # Vert forêt
	"B": [Color(0.52, 0.58, 0.78), Color(0.40, 0.45, 0.65)],  # Bleu glacier
	"J": [Color(0.80, 0.68, 0.32), Color(0.65, 0.52, 0.22)],  # Jaune sable
	"R": [Color(0.72, 0.32, 0.30), Color(0.55, 0.22, 0.20)],  # Rouge brique
}

var board_data: BoardData
var board_3d  # Board3D — set by Board3D._setup_subviewport()
var sector_rects: Dictionary = {}
var hovered_sector: String = ""
var selected_sector: String = ""
var highlighted_sectors: Array[String] = []
var sector_positions: Dictionary = {}
var debug_adjacency: bool = true  # Afficher les lignes d'adjacence (debug)

func _ready() -> void:
	board_data = BoardData.new()
	_calculate_sector_positions()

func _calculate_sector_positions() -> void:
	var territory_origins := {
		"V": Vector2(1, 1),
		"B": Vector2(5, 1),
		"J": Vector2(1, 5),
		"R": Vector2(5, 5),
	}

	# Flip par territoire pour que secteur 0 = coin le plus proche de IX
	var territory_flips := {
		"V": [true, true],    # flip_x et flip_y
		"B": [false, true],   # flip_y seulement
		"J": [true, false],   # flip_x seulement
		"R": [false, false],  # aucun flip
	}

	# Numérotation diagonale: secteur → position locale (col, row)
	# 0  2  5
	# 1  4  7
	# 3  6  8
	var sector_local := [
		Vector2(0, 0), Vector2(0, 1), Vector2(1, 0),
		Vector2(0, 2), Vector2(1, 1), Vector2(2, 0),
		Vector2(1, 2), Vector2(2, 1), Vector2(2, 2),
	]

	for prefix in territory_origins:
		var origin: Vector2 = territory_origins[prefix]
		var flips: Array = territory_flips[prefix]
		var flip_x: bool = flips[0]
		var flip_y: bool = flips[1]
		for i in range(9):
			var local: Vector2 = sector_local[i]
			var col: int = int(local.x)
			var row: int = int(local.y)
			if flip_x:
				col = 2 - col
			if flip_y:
				row = 2 - row
			var grid_pos := origin + Vector2(col, row)
			var pixel_pos := BOARD_ORIGIN + grid_pos * CELL_SIZE + Vector2(CELL_SIZE / 2, CELL_SIZE / 2)
			var sector_id := "%s%d" % [prefix, i]
			sector_positions[sector_id] = pixel_pos
			sector_rects[sector_id] = Rect2(
				pixel_pos - Vector2(CELL_SIZE / 2, CELL_SIZE / 2),
				Vector2(CELL_SIZE, CELL_SIZE))

	# QG aux 4 coins de la grille 9×9
	var hq_data := {
		"HQ_V": Vector2(0, 0),
		"HQ_B": Vector2(8, 0),
		"HQ_J": Vector2(0, 8),
		"HQ_R": Vector2(8, 8),
	}
	var hq_size := CELL_SIZE * 2  # QG 2× plus grand que les autres cases
	for hq_id in hq_data:
		var grid_pos: Vector2 = hq_data[hq_id]
		var pixel_pos: Vector2 = BOARD_ORIGIN + grid_pos * CELL_SIZE + Vector2(CELL_SIZE / 2, CELL_SIZE / 2)
		sector_positions[hq_id] = pixel_pos
		# Étendre le QG vers l'extérieur du plateau (coin)
		var rect_origin: Vector2
		match hq_id:
			"HQ_V": rect_origin = BOARD_ORIGIN + grid_pos * CELL_SIZE + Vector2(CELL_SIZE - hq_size, CELL_SIZE - hq_size)
			"HQ_B": rect_origin = BOARD_ORIGIN + grid_pos * CELL_SIZE + Vector2(0, CELL_SIZE - hq_size)
			"HQ_J": rect_origin = BOARD_ORIGIN + grid_pos * CELL_SIZE + Vector2(CELL_SIZE - hq_size, 0)
			"HQ_R": rect_origin = BOARD_ORIGIN + grid_pos * CELL_SIZE
		sector_rects[hq_id] = Rect2(rect_origin, Vector2(hq_size, hq_size))

	# Secteurs maritimes en bande (3 cellules chacun)
	var sea_strips := {
		# id: [center_grid, is_horizontal]
		"S5": [Vector2(2, 0), true],    # Haut gauche, horizontal 3×1
		"S1": [Vector2(6, 0), true],    # Haut droit, horizontal 3×1
		"S4": [Vector2(0, 2), false],   # Gauche haut, vertical 1×3
		"S2": [Vector2(8, 2), false],   # Droit haut, vertical 1×3
		"S6": [Vector2(4, 2), false],   # Centre haut, vertical 1×3
		"S3": [Vector2(2, 4), true],    # Centre gauche, horizontal 3×1
		"S9": [Vector2(6, 4), true],    # Centre droit, horizontal 3×1
		"S8": [Vector2(4, 6), false],   # Centre bas, vertical 1×3
		"S12": [Vector2(0, 6), false],  # Gauche bas, vertical 1×3
		"S10": [Vector2(8, 6), false],  # Droit bas, vertical 1×3
		"S11": [Vector2(2, 8), true],   # Bas gauche, horizontal 3×1
		"S7": [Vector2(6, 8), true],    # Bas droit, horizontal 3×1
	}
	for sea_id in sea_strips:
		var data: Array = sea_strips[sea_id]
		var grid_center: Vector2 = data[0]
		var is_horizontal: bool = data[1]
		var pixel_center: Vector2 = BOARD_ORIGIN + grid_center * CELL_SIZE + Vector2(CELL_SIZE / 2, CELL_SIZE / 2)
		sector_positions[sea_id] = pixel_center
		# Le rect couvre 3 cellules
		if is_horizontal:
			sector_rects[sea_id] = Rect2(
				BOARD_ORIGIN + Vector2(grid_center.x - 1, grid_center.y) * CELL_SIZE,
				Vector2(CELL_SIZE * 3, CELL_SIZE))
		else:
			sector_rects[sea_id] = Rect2(
				BOARD_ORIGIN + Vector2(grid_center.x, grid_center.y - 1) * CELL_SIZE,
				Vector2(CELL_SIZE, CELL_SIZE * 3))

	# Îles
	var island_grid := {
		"IN": Vector2(4, 0),
		"IS": Vector2(4, 8),
		"IW": Vector2(0, 4),
		"IE": Vector2(8, 4),
		"IX": Vector2(4, 4),
	}
	for island_id in island_grid:
		var pixel_pos: Vector2 = BOARD_ORIGIN + Vector2(island_grid[island_id]) * CELL_SIZE + Vector2(CELL_SIZE / 2, CELL_SIZE / 2)
		sector_positions[island_id] = pixel_pos
		sector_rects[island_id] = Rect2(
			pixel_pos - Vector2(CELL_SIZE / 2, CELL_SIZE / 2),
			Vector2(CELL_SIZE, CELL_SIZE))

# ===== DESSIN =====

func _draw() -> void:
	# Fond océan avec dégradé
	_draw_ocean_background()

	# Adjacences (lignes fines entre secteurs connectés)
	_draw_adjacency_lines()

	# Secteurs
	for sector_id in sector_positions:
		_draw_sector(sector_id)

	# Lignes d'adjacence debug (activé par debug_adjacency)
	if debug_adjacency:
		_draw_debug_adjacency()

	# Overlays interactifs
	_draw_highlights()

func _draw_ocean_background() -> void:
	var board_rect := Rect2(
		BOARD_ORIGIN + Vector2(-0.5, -0.5) * CELL_SIZE,
		Vector2(10, 10) * CELL_SIZE)
	# Fond
	draw_rect(board_rect, COLOR_SEA_DEEP)
	# Vagues subtiles (lignes horizontales semi-transparentes)
	var wave_color := Color(0.2, 0.4, 0.7, 0.08)
	for y_off in range(0, int(board_rect.size.y), 12):
		var y_pos := board_rect.position.y + y_off
		draw_line(
			Vector2(board_rect.position.x, y_pos),
			Vector2(board_rect.end.x, y_pos),
			wave_color, 1.0)

func _draw_adjacency_lines() -> void:
	if board_data == null:
		return
	var drawn: Dictionary = {}
	for sector_id in board_data.sectors:
		var sector: Sector = board_data.get_sector(sector_id)
		if sector == null:
			continue
		var pos_a: Vector2 = sector_positions.get(sector_id, Vector2.ZERO)
		if pos_a == Vector2.ZERO:
			continue
		for neighbor_id in sector.adjacent_sectors:
			var key: String = (sector_id + ":" + neighbor_id) if sector_id < neighbor_id else (neighbor_id + ":" + sector_id)
			if key in drawn:
				continue
			drawn[key] = true
			var pos_b: Vector2 = sector_positions.get(neighbor_id, Vector2.ZERO)
			if pos_b == Vector2.ZERO:
				continue
			# Ligne d'adjacence très discrète
			draw_line(pos_a, pos_b, Color(0.4, 0.5, 0.7, 0.08), 1.0)

func _draw_debug_adjacency() -> void:
	## Mode debug : dessine les connexions entre secteurs adjacents.
	## Couleur selon le type de terrain traversable :
	##   Vert = terrestre (terre/côtier/île)
	##   Bleu = maritime (mer/côtier)
	##   Blanc = aérien uniquement
	if board_data == null:
		return
	var drawn: Dictionary = {}
	var color_terre := Color(0.2, 0.9, 0.2, 0.4)
	var color_mer := Color(0.3, 0.5, 1.0, 0.4)
	var color_mixte := Color(0.9, 0.9, 0.3, 0.4)

	for sector_id in board_data.sectors:
		var sector: Sector = board_data.get_sector(sector_id)
		if sector == null:
			continue
		var pos_a: Vector2 = sector_positions.get(sector_id, Vector2.ZERO)
		if pos_a == Vector2.ZERO:
			continue

		for neighbor_id in sector.adjacent_sectors:
			var key: String = (sector_id + ":" + neighbor_id) if sector_id < neighbor_id else (neighbor_id + ":" + sector_id)
			if key in drawn:
				continue
			drawn[key] = true

			var pos_b: Vector2 = sector_positions.get(neighbor_id, Vector2.ZERO)
			if pos_b == Vector2.ZERO:
				continue

			var neighbor: Sector = board_data.get_sector(neighbor_id)
			if neighbor == null:
				continue

			# Déterminer quel type d'unité peut emprunter ce lien
			var terre_ok: bool = sector.is_accessible_by(GameEnums.UnitType.SOLDIER) and neighbor.is_accessible_by(GameEnums.UnitType.SOLDIER)
			var mer_ok: bool = sector.is_accessible_by(GameEnums.UnitType.DESTROYER) and neighbor.is_accessible_by(GameEnums.UnitType.DESTROYER)

			var line_color: Color
			if terre_ok and mer_ok:
				line_color = color_mixte
			elif terre_ok:
				line_color = color_terre
			elif mer_ok:
				line_color = color_mer
			else:
				line_color = Color(1, 1, 1, 0.2)  # Aérien seulement

			draw_line(pos_a, pos_b, line_color, 2.0)

			# Petit point au milieu du lien
			var mid := (pos_a + pos_b) / 2
			draw_circle(mid, 2.5, line_color)

func _draw_sector(sector_id: String) -> void:
	if sector_id not in sector_rects:
		return
	var rect: Rect2 = sector_rects[sector_id]
	var sector: Sector = board_data.get_sector(sector_id) if board_data else null
	if sector == null:
		return

	var inner := Rect2(
		rect.position + Vector2(CELL_PADDING, CELL_PADDING),
		rect.size - Vector2(CELL_PADDING * 2, CELL_PADDING * 2))

	match sector.sector_type:
		GameEnums.SectorType.SEA:
			_draw_sea_sector(inner, sector_id)
		GameEnums.SectorType.ISLAND:
			_draw_island_sector(inner, sector_id)
		GameEnums.SectorType.HQ:
			_draw_hq_sector(inner, sector)
		GameEnums.SectorType.COASTAL:
			_draw_coastal_sector(inner, sector, sector_id)
		_:
			_draw_land_sector(inner, sector, sector_id)

func _draw_land_sector(rect: Rect2, sector: Sector, sector_id: String) -> void:
	var prefix := sector_id.left(1)
	var colors: Array = TERRITORY_COLORS.get(prefix, [Color.GRAY, Color.DIM_GRAY])
	var fill: Color = colors[0]
	var edge: Color = colors[1]

	var num := sector_id.right(1).to_int() if sector_id.length() > 1 else -1
	var is_hill := (num == 4)
	if is_hill:
		fill = fill.darkened(0.1)

	# Fond avec bordure
	draw_rect(rect, edge)
	var inner := Rect2(rect.position + Vector2(2, 2), rect.size - Vector2(4, 4))
	draw_rect(inner, fill)

	# Reflet subtil en haut
	var shine := Rect2(inner.position, Vector2(inner.size.x, 3))
	draw_rect(shine, Color(1, 1, 1, 0.08))

	# Colline centrale: courbes de niveau + sommet
	if is_hill:
		var c := rect.get_center()
		var hw := rect.size.x * 0.5
		var contour_color := Color(edge.r, edge.g, edge.b, 0.3)
		# 3 ellipses concentriques
		for i in range(3):
			var r: float = hw * (0.35 + 0.2 * i)
			draw_arc(c, r, 0, TAU, 24, contour_color, 1.0)
		# Symbole sommet (petit triangle)
		var ts := 5.0  # taille du triangle
		var peak_color := fill.lightened(0.25)
		var triangle := PackedVector2Array([
			c + Vector2(0, -ts),
			c + Vector2(-ts * 0.8, ts * 0.6),
			c + Vector2(ts * 0.8, ts * 0.6),
		])
		draw_colored_polygon(triangle, peak_color)

	_draw_sector_label(rect, sector_id, COLOR_LABEL, 10)

func _draw_coastal_sector(rect: Rect2, sector: Sector, sector_id: String) -> void:
	var prefix := sector_id.left(1)
	var colors: Array = TERRITORY_COLORS.get(prefix, [Color.GRAY, Color.DIM_GRAY])
	var fill: Color = colors[0]
	var edge: Color = colors[1]

	# Fond de base (comme land)
	draw_rect(rect, edge)
	var inner := Rect2(rect.position + Vector2(2, 2), rect.size - Vector2(4, 4))
	draw_rect(inner, fill)

	# Reflet subtil en haut
	var shine := Rect2(inner.position, Vector2(inner.size.x, 3))
	draw_rect(shine, Color(1, 1, 1, 0.08))

	# Détecter les bords adjacents à la mer/île par intersection géométrique
	var sand_color := Color(COLOR_SAND.r, COLOR_SAND.g, COLOR_SAND.b, 0.55)
	var band := 5.0
	var probe := 6.0  # Distance de sonde au-delà du bord

	# Sondes pour chaque bord : petits rects qui dépassent de chaque côté
	var edge_probes := {
		"top": Rect2(rect.position.x, rect.position.y - probe, rect.size.x, probe),
		"bottom": Rect2(rect.position.x, rect.end.y, rect.size.x, probe),
		"left": Rect2(rect.position.x - probe, rect.position.y, probe, rect.size.y),
		"right": Rect2(rect.end.x, rect.position.y, probe, rect.size.y),
	}

	# Trouver quels bords touchent un secteur mer/île
	var sea_edges: Array[String] = []
	for edge_name in edge_probes:
		var probe_rect: Rect2 = edge_probes[edge_name]
		for other_id in sector_rects:
			if other_id == sector_id:
				continue
			var other_sector: Sector = board_data.get_sector(other_id) if board_data else null
			if other_sector == null:
				continue
			if other_sector.sector_type != GameEnums.SectorType.SEA and other_sector.sector_type != GameEnums.SectorType.ISLAND:
				continue
			if probe_rect.intersects(sector_rects[other_id]):
				sea_edges.append(edge_name)
				break

	# Dessiner la frange sable sur chaque bord détecté
	for edge_name in sea_edges:
		match edge_name:
			"top":
				draw_rect(Rect2(inner.position.x, inner.position.y, inner.size.x, band), sand_color)
			"bottom":
				draw_rect(Rect2(inner.position.x, inner.end.y - band, inner.size.x, band), sand_color)
			"left":
				draw_rect(Rect2(inner.position.x, inner.position.y, band, inner.size.y), sand_color)
			"right":
				draw_rect(Rect2(inner.end.x - band, inner.position.y, band, inner.size.y), sand_color)

	# Coins sable : si deux bords adjacents ont du sable, remplir le coin
	if "top" in sea_edges and "left" in sea_edges:
		draw_rect(Rect2(inner.position.x, inner.position.y, band, band), sand_color)
	if "top" in sea_edges and "right" in sea_edges:
		draw_rect(Rect2(inner.end.x - band, inner.position.y, band, band), sand_color)
	if "bottom" in sea_edges and "left" in sea_edges:
		draw_rect(Rect2(inner.position.x, inner.end.y - band, band, band), sand_color)
	if "bottom" in sea_edges and "right" in sea_edges:
		draw_rect(Rect2(inner.end.x - band, inner.end.y - band, band, band), sand_color)

	# Petites vagues le long des bords mer
	var wave_color := COLOR_WAVE_COAST
	for edge_name in sea_edges:
		match edge_name:
			"right":
				var wx: float = inner.end.x - 3.0
				for j in range(3):
					var wy: float = inner.position.y + inner.size.y * (0.25 + 0.25 * j)
					draw_arc(Vector2(wx, wy), 4.0, -PI * 0.5, PI * 0.5, 6, wave_color, 1.0)
			"left":
				var wx: float = inner.position.x + 3.0
				for j in range(3):
					var wy: float = inner.position.y + inner.size.y * (0.25 + 0.25 * j)
					draw_arc(Vector2(wx, wy), 4.0, PI * 0.5, PI * 1.5, 6, wave_color, 1.0)
			"bottom":
				var wy: float = inner.end.y - 3.0
				for j in range(3):
					var wx: float = inner.position.x + inner.size.x * (0.25 + 0.25 * j)
					draw_arc(Vector2(wx, wy), 4.0, 0, PI, 6, wave_color, 1.0)
			"top":
				var wy: float = inner.position.y + 3.0
				for j in range(3):
					var wx: float = inner.position.x + inner.size.x * (0.25 + 0.25 * j)
					draw_arc(Vector2(wx, wy), 4.0, PI, TAU, 6, wave_color, 1.0)

	_draw_sector_label(rect, sector_id, COLOR_LABEL, 10)

func _draw_sea_sector(rect: Rect2, sector_id: String) -> void:
	draw_rect(rect, COLOR_SEA_LIGHT)
	# Petites vagues adaptées à la taille du rect
	var center := rect.get_center()
	var half_w := rect.size.x * 0.15
	var half_h := rect.size.y * 0.15
	if rect.size.x >= rect.size.y:
		# Horizontal ou carré: vagues horizontales
		draw_line(center + Vector2(-half_w, -2), center + Vector2(half_w, -2), Color(0.3, 0.5, 0.8, 0.3), 1.0)
		draw_line(center + Vector2(-half_w * 0.75, 2), center + Vector2(half_w * 0.75, 2), Color(0.3, 0.5, 0.8, 0.2), 1.0)
	else:
		# Vertical: vagues verticales
		draw_line(center + Vector2(-2, -half_h), center + Vector2(-2, half_h), Color(0.3, 0.5, 0.8, 0.3), 1.0)
		draw_line(center + Vector2(2, -half_h * 0.75), center + Vector2(2, half_h * 0.75), Color(0.3, 0.5, 0.8, 0.2), 1.0)
	_draw_sector_label(rect, sector_id, Color(0.7, 0.8, 1.0, 0.6), 9)

func _draw_island_sector(rect: Rect2, sector_id: String) -> void:
	# Octogone pour représenter les îles (fidèle au plateau original)
	var c := rect.get_center()
	var hw := rect.size.x / 2 - CELL_PADDING
	var hh := rect.size.y / 2 - CELL_PADDING
	var cut := hw * 0.35

	# Points de l'octogone (sens horaire depuis haut-gauche)
	var points := PackedVector2Array([
		c + Vector2(-hw + cut, -hh),
		c + Vector2(hw - cut, -hh),
		c + Vector2(hw, -hh + cut),
		c + Vector2(hw, hh - cut),
		c + Vector2(hw - cut, hh),
		c + Vector2(-hw + cut, hh),
		c + Vector2(-hw, hh - cut),
		c + Vector2(-hw, -hh + cut),
	])

	# Ombre portée (effet d'élévation)
	var shadow_points := PackedVector2Array()
	for p in points:
		shadow_points.append(p + Vector2(3, 3))
	draw_colored_polygon(shadow_points, Color(0, 0, 0, 0.3))

	# Bordure de plage (octogone extérieur)
	draw_colored_polygon(points, Color(0.75, 0.70, 0.50))

	# Île intérieure (octogone réduit)
	var inner_points := PackedVector2Array()
	for p in points:
		inner_points.append(c + (p - c) * 0.85)
	draw_colored_polygon(inner_points, COLOR_ISLAND)

	# Bordure épaisse
	draw_polyline(points, COLOR_ISLAND_EDGE, 2.0, true)
	draw_line(points[-1], points[0], COLOR_ISLAND_EDGE, 2.0)

	# Hachures rocheuses (lignes diagonales)
	var hatch_color := Color(COLOR_ISLAND_EDGE.r, COLOR_ISLAND_EDGE.g, COLOR_ISLAND_EDGE.b, 0.25)
	for i in range(4):
		var offset: float = -hw * 0.4 + hw * 0.2 * i
		var p1 := c + Vector2(offset, -hh * 0.4)
		var p2 := c + Vector2(offset + hw * 0.25, hh * 0.3)
		draw_line(p1, p2, hatch_color, 1.0)

	# Point culminant au centre
	draw_circle(c, 3.0, Color(0.6, 0.85, 0.5, 0.5))

	# Reflet subtil en haut
	var shine_points := PackedVector2Array([
		inner_points[0], inner_points[1], inner_points[2],
		c + Vector2(hw * 0.85, -hh * 0.85 + hh * 0.15),
		c + Vector2(-hw * 0.85, -hh * 0.85 + hh * 0.15),
		inner_points[7],
	])
	draw_colored_polygon(shine_points, Color(0.5, 0.75, 0.4, 0.2))

	_draw_sector_label(rect, sector_id, COLOR_LABEL, 10)

func _draw_hq_sector(rect: Rect2, sector: Sector) -> void:
	var prefix := ""
	match sector.owner_territory:
		GameEnums.PlayerColor.GREEN: prefix = "V"
		GameEnums.PlayerColor.BLUE: prefix = "B"
		GameEnums.PlayerColor.YELLOW: prefix = "J"
		GameEnums.PlayerColor.RED: prefix = "R"

	var colors: Array = TERRITORY_COLORS.get(prefix, [Color.GRAY, Color.DIM_GRAY])
	var fill: Color = colors[0].lightened(0.15)
	var edge: Color = COLOR_HQ_GLOW
	var wall_color: Color = colors[1].darkened(0.15)

	# Lueur extérieure
	var glow := Rect2(rect.position - Vector2(3, 3), rect.size + Vector2(6, 6))
	draw_rect(glow, Color(edge.r, edge.g, edge.b, 0.2))

	# Fond avec murs épais
	draw_rect(rect, wall_color)
	var inner := Rect2(rect.position + Vector2(4, 4), rect.size - Vector2(8, 8))
	draw_rect(inner, fill)

	# Bordure dorée épaisse
	draw_rect(rect, edge, false, 3.0)

	# Créneaux sur le bord supérieur
	var cren_h := 5.0
	var cren_w := 8.0
	var gap := 4.0
	var total_w: float = rect.size.x
	var num_crens: int = int(total_w / (cren_w + gap))
	var start_x: float = rect.position.x + (total_w - num_crens * (cren_w + gap) + gap) * 0.5
	for i in range(num_crens):
		var cx: float = start_x + i * (cren_w + gap)
		draw_rect(Rect2(cx, rect.position.y - cren_h, cren_w, cren_h), wall_color)
		draw_rect(Rect2(cx, rect.position.y - cren_h, cren_w, cren_h), edge, false, 1.0)

	# Créneaux sur le bord inférieur
	for i in range(num_crens):
		var cx: float = start_x + i * (cren_w + gap)
		draw_rect(Rect2(cx, rect.end.y, cren_w, cren_h), wall_color)
		draw_rect(Rect2(cx, rect.end.y, cren_w, cren_h), edge, false, 1.0)

	# Étoile dorée au-dessus du texte
	var star_center := Vector2(rect.get_center().x, rect.get_center().y - 12)
	var star_points := PackedVector2Array()
	for i in range(8):
		var angle: float = i * TAU / 8 - PI / 2
		var r: float = 5.0 if i % 2 == 0 else 2.5
		star_points.append(star_center + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(star_points, COLOR_HQ_GLOW)

	# Texte QG
	var font := ThemeDB.fallback_font
	var text := "QG"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
	var text_pos := rect.position + (rect.size - text_size) / 2 + Vector2(0, text_size.y * 0.7 + 4)
	draw_string(font, text_pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COLOR_LABEL_SHADOW)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COLOR_HQ_GLOW)

func _draw_highlights() -> void:
	for h_sector in highlighted_sectors:
		if h_sector in sector_rects:
			var rect: Rect2 = sector_rects[h_sector]
			draw_rect(rect, COLOR_REACHABLE)
			# Petite bordure
			draw_rect(rect, Color(0.4, 0.7, 1.0, 0.4), false, 1.5)

	if selected_sector != "" and selected_sector in sector_rects:
		var rect: Rect2 = sector_rects[selected_sector]
		draw_rect(rect, COLOR_SELECTED)
		draw_rect(rect, Color(0.2, 1.0, 0.2, 0.6), false, 2.0)

	if hovered_sector != "" and hovered_sector in sector_rects:
		var rect: Rect2 = sector_rects[hovered_sector]
		draw_rect(rect, COLOR_HIGHLIGHT)

func _draw_sector_label(rect: Rect2, label_text: String, color: Color, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := rect.position + (rect.size - text_size) / 2 + Vector2(0, text_size.y * 0.75)
	# Ombre
	draw_string(font, text_pos + Vector2(1, 1), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.35))
	draw_string(font, text_pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func get_sector_position(sector_id: String) -> Vector2:
	## Retourne la position écran projetée du secteur.
	## Si board_3d est disponible, projette via la caméra 3D.
	## Sinon, retourne la position pixel brute (fallback).
	if board_3d != null:
		return board_3d.get_sector_screen_position(sector_id)
	return sector_positions.get(sector_id, Vector2.ZERO)

func highlight_sectors(sector_ids: Array[String]) -> void:
	highlighted_sectors = sector_ids
	queue_redraw()

func clear_highlights() -> void:
	highlighted_sectors.clear()
	selected_sector = ""
	queue_redraw()
