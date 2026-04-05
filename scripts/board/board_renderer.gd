extends Node2D
class_name BoardRenderer

## Rendu visuel du plateau de jeu Power - version polie.


const CELL_SIZE := 55.0
const CELL_PADDING := 2.0
# Le grille va de (0,0) à (7,7) pour les territoires, le centre logique est (3.75, 3.5)
# Zone utile écran: X=[0, 1015], Y=[42, 670] → centre ~(507, 356)
# BOARD_ORIGIN = centre_écran - centre_grille * CELL_SIZE
# Pour SubViewport 1024x1024: centrer la grille (~11x10 cellules)
# Centre grille logique: (3.75, 3.5). Centre viewport: (512, 512)
const BOARD_ORIGIN := Vector2(512 - 3.75 * 55.0, 512 - 3.5 * 55.0)
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

func _ready() -> void:
	board_data = BoardData.new()
	_calculate_sector_positions()

func _calculate_sector_positions() -> void:
	var territory_origins := {
		"V": Vector2(0, 0),
		"B": Vector2(5, 0),
		"J": Vector2(0, 5),
		"R": Vector2(5, 5),
	}

	for prefix in territory_origins:
		var origin: Vector2 = territory_origins[prefix]
		for i in range(9):
			var col := i % 3
			var row := i / 3
			var grid_pos := origin + Vector2(col, row)
			var pixel_pos := BOARD_ORIGIN + grid_pos * CELL_SIZE + Vector2(CELL_SIZE / 2, CELL_SIZE / 2)
			var sector_id := "%s%d" % [prefix, i]
			sector_positions[sector_id] = pixel_pos
			sector_rects[sector_id] = Rect2(
				pixel_pos - Vector2(CELL_SIZE / 2, CELL_SIZE / 2),
				Vector2(CELL_SIZE, CELL_SIZE))

	# QG
	var hq_data := {
		"HQ_V": Vector2(-1, -0.5),
		"HQ_B": Vector2(8, -0.5),
		"HQ_J": Vector2(-1, 7.5),
		"HQ_R": Vector2(8, 7.5),
	}
	for hq_id in hq_data:
		var pixel_pos: Vector2 = BOARD_ORIGIN + Vector2(hq_data[hq_id]) * CELL_SIZE + Vector2(CELL_SIZE / 2, CELL_SIZE / 2)
		sector_positions[hq_id] = pixel_pos
		sector_rects[hq_id] = Rect2(
			pixel_pos - Vector2(CELL_SIZE / 2, CELL_SIZE / 2),
			Vector2(CELL_SIZE, CELL_SIZE))

	# Secteurs maritimes
	var sea_grid := {
		"S5": Vector2(3.5, -0.5), "S1": Vector2(4.5, -0.5),
		"S6": Vector2(4, 2), "S4": Vector2(-0.5, 1.5),
		"S12": Vector2(-0.5, 5.5), "S3": Vector2(3, 3.5),
		"S9": Vector2(5, 3.5), "S2": Vector2(8.5, 1.5),
		"S10": Vector2(8.5, 5.5), "S8": Vector2(4, 5),
		"S11": Vector2(3.5, 7.5), "S7": Vector2(4.5, 7.5),
	}
	for sea_id in sea_grid:
		var pixel_pos: Vector2 = BOARD_ORIGIN + Vector2(sea_grid[sea_id]) * CELL_SIZE + Vector2(CELL_SIZE / 2, CELL_SIZE / 2)
		sector_positions[sea_id] = pixel_pos
		sector_rects[sea_id] = Rect2(
			pixel_pos - Vector2(CELL_SIZE / 2, CELL_SIZE / 2),
			Vector2(CELL_SIZE, CELL_SIZE))

	# Îles
	var island_grid := {
		"IN": Vector2(4, 0.5), "IS": Vector2(4, 6.5),
		"IW": Vector2(1.5, 3.5), "IE": Vector2(6.5, 3.5),
		"IX": Vector2(4, 3.5),
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

	# Overlays interactifs
	_draw_highlights()

func _draw_ocean_background() -> void:
	var board_rect := Rect2(
		BOARD_ORIGIN + Vector2(-2, -1.5) * CELL_SIZE,
		Vector2(11, 10) * CELL_SIZE)
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
		_:
			_draw_land_sector(inner, sector, sector_id)

func _draw_land_sector(rect: Rect2, sector: Sector, sector_id: String) -> void:
	var prefix := sector_id.left(1)
	var colors: Array = TERRITORY_COLORS.get(prefix, [Color.GRAY, Color.DIM_GRAY])
	var fill: Color = colors[0]
	var edge: Color = colors[1]

	# Secteur central (4) légèrement plus foncé
	var num := sector_id.right(1).to_int() if sector_id.length() > 1 else -1
	if num == 4:
		fill = fill.darkened(0.1)

	# Fond avec bordure arrondie simulée
	draw_rect(rect, edge)
	var inner := Rect2(rect.position + Vector2(2, 2), rect.size - Vector2(4, 4))
	draw_rect(inner, fill)

	# Reflet subtil en haut
	var shine := Rect2(inner.position, Vector2(inner.size.x, 3))
	draw_rect(shine, Color(1, 1, 1, 0.08))

	# Label
	_draw_sector_label(rect, sector_id, COLOR_LABEL, 10)

func _draw_sea_sector(rect: Rect2, sector_id: String) -> void:
	draw_rect(rect, COLOR_SEA_LIGHT)
	# Petites vagues
	var center := rect.get_center()
	draw_line(center + Vector2(-8, -2), center + Vector2(8, -2), Color(0.3, 0.5, 0.8, 0.3), 1.0)
	draw_line(center + Vector2(-6, 2), center + Vector2(6, 2), Color(0.3, 0.5, 0.8, 0.2), 1.0)
	_draw_sector_label(rect, sector_id, Color(0.7, 0.8, 1.0, 0.6), 9)

func _draw_island_sector(rect: Rect2, sector_id: String) -> void:
	# Bordure de plage
	draw_rect(rect, Color(0.75, 0.70, 0.50))
	var inner := Rect2(rect.position + Vector2(3, 3), rect.size - Vector2(6, 6))
	draw_rect(inner, COLOR_ISLAND)
	# Petite touffe de vert
	var shine := Rect2(inner.position + Vector2(2, 2), Vector2(inner.size.x - 4, 3))
	draw_rect(shine, Color(0.5, 0.75, 0.4, 0.3))
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

	# Lueur extérieure
	var glow := Rect2(rect.position - Vector2(2, 2), rect.size + Vector2(4, 4))
	draw_rect(glow, Color(edge.r, edge.g, edge.b, 0.25))

	# Fond
	draw_rect(rect, colors[1])
	var inner := Rect2(rect.position + Vector2(2, 2), rect.size - Vector2(4, 4))
	draw_rect(inner, fill)

	# Bordure dorée
	draw_rect(rect, edge, false, 2.5)

	# Texte HQ
	var font := ThemeDB.fallback_font
	var text := "QG"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
	var text_pos := rect.position + (rect.size - text_size) / 2 + Vector2(0, text_size.y * 0.7)
	# Ombre
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
