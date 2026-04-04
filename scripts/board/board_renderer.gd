extends Node2D
class_name BoardRenderer

## Rendu visuel du plateau de jeu Power.
## Dessine les secteurs, les îles, la mer et les QG.

signal sector_clicked(sector_id: String)
signal sector_hovered(sector_id: String)

const CELL_SIZE := 64.0
const BOARD_ORIGIN := Vector2(80, 40)

# Couleurs du plateau
const COLOR_SEA := Color(0.15, 0.35, 0.65)
const COLOR_ISLAND := Color(0.55, 0.75, 0.45)
const COLOR_LAND_V := Color(0.3, 0.7, 0.3)     # Vert
const COLOR_LAND_B := Color(0.6, 0.65, 0.85)    # Bleu/glace
const COLOR_LAND_J := Color(0.85, 0.7, 0.35)    # Jaune/sable
const COLOR_LAND_R := Color(0.35, 0.65, 0.35)   # Rouge/tropical
const COLOR_HQ_BORDER := Color(0.9, 0.85, 0.2)
const COLOR_GRID := Color(0.2, 0.2, 0.2, 0.4)
const COLOR_HIGHLIGHT := Color(1.0, 1.0, 0.5, 0.4)
const COLOR_SELECTED := Color(0.2, 0.8, 0.2, 0.5)

var board_data: BoardData
var sector_rects: Dictionary = {}  # sector_id -> Rect2 (hitbox)
var hovered_sector: String = ""
var selected_sector: String = ""
var highlighted_sectors: Array[String] = []

# Positions calculées pour chaque secteur (centre en pixels)
var sector_positions: Dictionary = {}

func _ready() -> void:
	board_data = BoardData.new()
	_calculate_sector_positions()

func _calculate_sector_positions() -> void:
	## Calcule les positions pixel de chaque secteur basé sur la disposition du plateau.
	## Disposition: 4 territoires (3x3) aux coins, canaux entre eux.

	# Origine des territoires (en cellules de grille)
	var territory_origins := {
		"V": Vector2(0, 0),   # Haut-gauche
		"B": Vector2(5, 0),   # Haut-droite
		"J": Vector2(0, 5),   # Bas-gauche
		"R": Vector2(5, 5),   # Bas-droite
	}

	# Secteurs de territoire
	for prefix in territory_origins:
		var origin: Vector2 = territory_origins[prefix]
		for i in range(9):
			var col := i % 3
			var row := i / 3
			var grid_pos := origin + Vector2(col, row)
			var pixel_pos := BOARD_ORIGIN + grid_pos * CELL_SIZE + Vector2(CELL_SIZE / 2, CELL_SIZE / 2)
			var sector_id := "%s%d" % [prefix, i]
			sector_positions[sector_id] = pixel_pos
			sector_rects[sector_id] = Rect2(pixel_pos - Vector2(CELL_SIZE / 2, CELL_SIZE / 2), Vector2(CELL_SIZE, CELL_SIZE))

	# QG (à côté du coin de chaque territoire)
	sector_positions["HQ_V"] = BOARD_ORIGIN + Vector2(-1, -0.5) * CELL_SIZE + Vector2(CELL_SIZE / 2, CELL_SIZE / 2)
	sector_positions["HQ_B"] = BOARD_ORIGIN + Vector2(8, -0.5) * CELL_SIZE + Vector2(CELL_SIZE / 2, CELL_SIZE / 2)
	sector_positions["HQ_J"] = BOARD_ORIGIN + Vector2(-1, 7.5) * CELL_SIZE + Vector2(CELL_SIZE / 2, CELL_SIZE / 2)
	sector_positions["HQ_R"] = BOARD_ORIGIN + Vector2(8, 7.5) * CELL_SIZE + Vector2(CELL_SIZE / 2, CELL_SIZE / 2)

	for hq_id in ["HQ_V", "HQ_B", "HQ_J", "HQ_R"]:
		sector_rects[hq_id] = Rect2(sector_positions[hq_id] - Vector2(CELL_SIZE / 2, CELL_SIZE / 2), Vector2(CELL_SIZE, CELL_SIZE))

	# Secteurs maritimes
	var sea_positions_grid := {
		"S5": Vector2(3.5, -0.5),    # Nord, côté V
		"S1": Vector2(4.5, -0.5),    # Nord, côté B
		"S6": Vector2(4, 2),         # Nord-centre
		"S4": Vector2(-0.5, 1.5),    # Ouest, côté V
		"S12": Vector2(-0.5, 5.5),   # Ouest, côté J
		"S3": Vector2(3, 3.5),       # Ouest-centre
		"S9": Vector2(5, 3.5),       # Est-centre
		"S2": Vector2(8.5, 1.5),     # Est, côté B
		"S10": Vector2(8.5, 5.5),    # Est, côté R
		"S8": Vector2(4, 5),         # Sud-centre
		"S11": Vector2(3.5, 7.5),    # Sud, côté J
		"S7": Vector2(4.5, 7.5),     # Sud, côté R
	}

	for sea_id in sea_positions_grid:
		var grid_pos: Vector2 = sea_positions_grid[sea_id]
		var pixel_pos := BOARD_ORIGIN + grid_pos * CELL_SIZE + Vector2(CELL_SIZE / 2, CELL_SIZE / 2)
		sector_positions[sea_id] = pixel_pos
		sector_rects[sea_id] = Rect2(pixel_pos - Vector2(CELL_SIZE / 2, CELL_SIZE / 2), Vector2(CELL_SIZE, CELL_SIZE))

	# Îles
	var island_positions_grid := {
		"IN": Vector2(4, 0.5),     # Île Nord
		"IS": Vector2(4, 6.5),     # Île Sud
		"IW": Vector2(1.5, 3.5),   # Île Ouest
		"IE": Vector2(6.5, 3.5),   # Île Est
		"IX": Vector2(4, 3.5),     # Île Centre
	}

	for island_id in island_positions_grid:
		var grid_pos: Vector2 = island_positions_grid[island_id]
		var pixel_pos := BOARD_ORIGIN + grid_pos * CELL_SIZE + Vector2(CELL_SIZE / 2, CELL_SIZE / 2)
		sector_positions[island_id] = pixel_pos
		sector_rects[island_id] = Rect2(pixel_pos - Vector2(CELL_SIZE / 2, CELL_SIZE / 2), Vector2(CELL_SIZE, CELL_SIZE))

func _draw() -> void:
	# Fond mer
	var board_rect := Rect2(
		BOARD_ORIGIN + Vector2(-1.5, -1.5) * CELL_SIZE,
		Vector2(10, 10) * CELL_SIZE
	)
	draw_rect(board_rect, COLOR_SEA)

	# Dessiner les secteurs
	for sector_id in sector_positions:
		_draw_sector(sector_id)

	# Dessiner la surbrillance
	if hovered_sector != "" and hovered_sector in sector_rects:
		draw_rect(sector_rects[hovered_sector], COLOR_HIGHLIGHT)

	if selected_sector != "" and selected_sector in sector_rects:
		draw_rect(sector_rects[selected_sector], COLOR_SELECTED)

	for h_sector in highlighted_sectors:
		if h_sector in sector_rects:
			draw_rect(sector_rects[h_sector], Color(0.3, 0.6, 1.0, 0.3))

func _draw_sector(sector_id: String) -> void:
	if sector_id not in sector_rects:
		return

	var rect: Rect2 = sector_rects[sector_id]
	var sector: Sector = board_data.get_sector(sector_id)
	if sector == null:
		return

	var fill_color := _get_sector_color(sector)
	var border_color := COLOR_GRID

	# Dessiner le fond
	draw_rect(rect, fill_color)

	# Bordure spéciale pour les QG
	if sector.sector_type == GameEnums.SectorType.HQ:
		draw_rect(rect, COLOR_HQ_BORDER, false, 3.0)
	else:
		draw_rect(rect, border_color, false, 1.0)

	# Label du secteur
	var font := ThemeDB.fallback_font
	var font_size := 11
	var label := sector.display_name
	if sector_id.begins_with("HQ"):
		label = "HQ"
		font_size = 14

	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := rect.position + (rect.size - text_size) / 2 + Vector2(0, text_size.y * 0.75)
	draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.1, 0.1, 0.1))

func _get_sector_color(sector: Sector) -> Color:
	match sector.sector_type:
		GameEnums.SectorType.SEA:
			return COLOR_SEA.lightened(0.1)
		GameEnums.SectorType.ISLAND:
			return COLOR_ISLAND
		GameEnums.SectorType.HQ:
			return _get_territory_color(sector.owner_territory).lightened(0.2)
		_:  # LAND ou COASTAL
			return _get_territory_color(sector.owner_territory)

func _get_territory_color(color: GameEnums.PlayerColor) -> Color:
	match color:
		GameEnums.PlayerColor.GREEN: return COLOR_LAND_V
		GameEnums.PlayerColor.BLUE: return COLOR_LAND_B
		GameEnums.PlayerColor.YELLOW: return COLOR_LAND_J
		GameEnums.PlayerColor.RED: return COLOR_LAND_R
		_: return Color(0.5, 0.5, 0.5)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var old_hovered := hovered_sector
		hovered_sector = _get_sector_at(event.position)
		if hovered_sector != old_hovered:
			if hovered_sector != "":
				sector_hovered.emit(hovered_sector)
			queue_redraw()

	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var clicked := _get_sector_at(event.position)
			if clicked != "":
				selected_sector = clicked
				sector_clicked.emit(clicked)
				queue_redraw()

func _get_sector_at(pos: Vector2) -> String:
	for sector_id in sector_rects:
		if sector_rects[sector_id].has_point(pos):
			return sector_id
	return ""

func get_sector_position(sector_id: String) -> Vector2:
	return sector_positions.get(sector_id, Vector2.ZERO)

func highlight_sectors(sector_ids: Array[String]) -> void:
	highlighted_sectors = sector_ids
	queue_redraw()

func clear_highlights() -> void:
	highlighted_sectors.clear()
	selected_sector = ""
	queue_redraw()
