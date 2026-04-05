extends Node2D
class_name UnitRenderer

## Affiche les unités sur le plateau avec des icônes géométriques distinctes.
## Chaque type d'unité a une forme unique, colorée selon le joueur.

var board_renderer: BoardRenderer
var board_3d: Board3D
var game_state: GameState

const ICON_SIZE := 8.0       # Rayon de base des icônes
const ICON_SPACING := 18.0   # Espace entre icônes dans un secteur
const MAX_PER_ROW := 3       # Max icônes par ligne dans un secteur

func update_display() -> void:
	queue_redraw()

func _process(_delta: float) -> void:
	if board_3d != null and game_state != null:
		queue_redraw()

func _draw() -> void:
	if game_state == null:
		return

	var position_source_3d := board_3d != null
	var positions: Dictionary = {}

	if position_source_3d:
		for sector_id in board_3d.get_all_sector_ids():
			positions[sector_id] = board_3d.get_sector_screen_position(sector_id)
	elif board_renderer != null:
		positions = board_renderer.sector_positions

	for sector_id in positions:
		var sector: Sector = game_state.board.get_sector(sector_id)
		if sector == null or sector.units.is_empty():
			continue
		var base_pos: Vector2 = positions[sector_id]

		var scale_factor := 1.0
		if position_source_3d:
			scale_factor = board_3d.get_sector_screen_scale(sector_id)

		_draw_units_at_sector(sector.units, base_pos, scale_factor)

func _draw_units_at_sector(units: Array, base_pos: Vector2, scale_factor: float = 1.0) -> void:
	# Disposer les icônes en grille dans le secteur
	var count := units.size()
	if count == 0:
		return

	# Calculer la disposition
	var spacing := ICON_SPACING * scale_factor
	var cols: int = mini(count, MAX_PER_ROW)
	var rows: int = ceili(float(count) / cols)
	var start_x: float = -(cols - 1) * spacing * 0.5
	var start_y: float = -(rows - 1) * spacing * 0.5

	for i in range(count):
		var unit: UnitData = units[i]
		var col: int = i % cols
		var row: int = i / cols
		var offset := Vector2(start_x + col * spacing, start_y + row * spacing)
		var pos := base_pos + offset
		var color: Color = GameEnums.get_player_color(unit.owner)

		_draw_unit_icon(pos, unit.unit_type, color, unit.owner, scale_factor)

func _draw_unit_icon(pos: Vector2, unit_type: GameEnums.UnitType, color: Color, owner: GameEnums.PlayerColor, sf: float = 1.0) -> void:
	# Ombre
	var shadow_offset := Vector2(1, 1) * sf

	match unit_type:
		GameEnums.UnitType.SOLDIER:
			_draw_soldier(pos, color, shadow_offset, false, sf)
		GameEnums.UnitType.REGIMENT:
			_draw_soldier(pos, color, shadow_offset, true, sf)
		GameEnums.UnitType.TANK:
			_draw_tank(pos, color, shadow_offset, false, sf)
		GameEnums.UnitType.HEAVY_TANK:
			_draw_tank(pos, color, shadow_offset, true, sf)
		GameEnums.UnitType.FIGHTER:
			_draw_plane(pos, color, shadow_offset, false, sf)
		GameEnums.UnitType.BOMBER:
			_draw_plane(pos, color, shadow_offset, true, sf)
		GameEnums.UnitType.DESTROYER:
			_draw_ship(pos, color, shadow_offset, false, sf)
		GameEnums.UnitType.CRUISER:
			_draw_ship(pos, color, shadow_offset, true, sf)
		GameEnums.UnitType.FLAG:
			_draw_flag(pos, color, shadow_offset, sf)
		GameEnums.UnitType.POWER:
			_draw_power(pos, color, shadow_offset, sf)
		GameEnums.UnitType.MEGA_MISSILE:
			_draw_missile(pos, color, shadow_offset, sf)

# ===== SOLDAT / RÉGIMENT =====
# Cercle (tête) + corps triangulaire

func _draw_soldier(pos: Vector2, color: Color, shadow: Vector2, is_big: bool, sf: float = 1.0) -> void:
	var s: float = ICON_SIZE * (1.3 if is_big else 1.0) * sf
	var dark := color.darkened(0.3)

	# Ombre
	draw_circle(pos + shadow + Vector2(0, -s * 0.4), s * 0.35, Color(0, 0, 0, 0.3))

	# Corps (triangle)
	var body := PackedVector2Array([
		pos + Vector2(-s * 0.5, s * 0.5),
		pos + Vector2(s * 0.5, s * 0.5),
		pos + Vector2(0, -s * 0.1),
	])
	draw_colored_polygon(body, dark)

	# Tête (cercle)
	draw_circle(pos + Vector2(0, -s * 0.4), s * 0.35, color)

	# Contour tête
	draw_arc(pos + Vector2(0, -s * 0.4), s * 0.35, 0, TAU, 16, color.lightened(0.3), 1.0)

	if is_big:
		# Double barre pour régiment
		draw_line(pos + Vector2(-s * 0.6, s * 0.6), pos + Vector2(s * 0.6, s * 0.6),
			color.lightened(0.4), 2.0)
		draw_line(pos + Vector2(-s * 0.5, s * 0.75), pos + Vector2(s * 0.5, s * 0.75),
			color.lightened(0.4), 1.5)

# ===== TANK / CHAR D'ASSAUT =====
# Rectangle (châssis) + ligne (canon)

func _draw_tank(pos: Vector2, color: Color, shadow: Vector2, is_big: bool, sf: float = 1.0) -> void:
	var s: float = ICON_SIZE * (1.3 if is_big else 1.0) * sf
	var dark := color.darkened(0.3)

	# Ombre
	draw_rect(Rect2(pos + shadow - Vector2(s * 0.6, s * 0.3), Vector2(s * 1.2, s * 0.7)),
		Color(0, 0, 0, 0.3))

	# Chenilles (rectangle foncé)
	draw_rect(Rect2(pos - Vector2(s * 0.7, s * 0.35), Vector2(s * 1.4, s * 0.8)), dark)

	# Châssis (rectangle principal)
	draw_rect(Rect2(pos - Vector2(s * 0.55, s * 0.25), Vector2(s * 1.1, s * 0.55)), color)

	# Tourelle (petit carré)
	draw_rect(Rect2(pos - Vector2(s * 0.25, s * 0.2), Vector2(s * 0.5, s * 0.35)),
		color.lightened(0.15))

	# Canon
	var canon_len: float = s * (1.0 if is_big else 0.7)
	draw_line(pos + Vector2(s * 0.1, -s * 0.05),
		pos + Vector2(s * 0.1 + canon_len, -s * 0.05),
		dark, 2.5 if is_big else 2.0)

	if is_big:
		# Étoile sur la tourelle pour char d'assaut
		draw_circle(pos, s * 0.12, color.lightened(0.4))

# ===== CHASSEUR / BOMBARDIER =====
# Triangle pointant vers le haut (forme d'avion)

func _draw_plane(pos: Vector2, color: Color, shadow: Vector2, is_big: bool, sf: float = 1.0) -> void:
	var s: float = ICON_SIZE * (1.3 if is_big else 1.0) * sf
	var dark := color.darkened(0.3)

	# Ombre
	var shadow_shape := PackedVector2Array([
		pos + shadow + Vector2(0, -s * 0.7),
		pos + shadow + Vector2(-s * 0.6, s * 0.5),
		pos + shadow + Vector2(s * 0.6, s * 0.5),
	])
	draw_colored_polygon(shadow_shape, Color(0, 0, 0, 0.3))

	# Fuselage (triangle principal - nez vers le haut)
	var fuselage := PackedVector2Array([
		pos + Vector2(0, -s * 0.7),    # Nez
		pos + Vector2(-s * 0.2, s * 0.4),
		pos + Vector2(s * 0.2, s * 0.4),
	])
	draw_colored_polygon(fuselage, color)

	# Ailes
	var left_wing := PackedVector2Array([
		pos + Vector2(-s * 0.15, 0),
		pos + Vector2(-s * 0.7, s * 0.3),
		pos + Vector2(-s * 0.1, s * 0.25),
	])
	var right_wing := PackedVector2Array([
		pos + Vector2(s * 0.15, 0),
		pos + Vector2(s * 0.7, s * 0.3),
		pos + Vector2(s * 0.1, s * 0.25),
	])
	draw_colored_polygon(left_wing, dark)
	draw_colored_polygon(right_wing, dark)

	# Queue
	var tail := PackedVector2Array([
		pos + Vector2(-s * 0.3, s * 0.4),
		pos + Vector2(s * 0.3, s * 0.4),
		pos + Vector2(0, s * 0.6),
	])
	draw_colored_polygon(tail, dark)

	if is_big:
		# Bombes sous les ailes pour bombardier
		draw_circle(pos + Vector2(-s * 0.35, s * 0.2), s * 0.08, Color.BLACK)
		draw_circle(pos + Vector2(s * 0.35, s * 0.2), s * 0.08, Color.BLACK)
		# Bande blanche
		draw_line(pos + Vector2(-s * 0.15, -s * 0.1), pos + Vector2(s * 0.15, -s * 0.1),
			color.lightened(0.5), 1.5)

# ===== DESTROYER / CROISEUR =====
# Forme de bateau (losange allongé horizontalement)

func _draw_ship(pos: Vector2, color: Color, shadow: Vector2, is_big: bool, sf: float = 1.0) -> void:
	var s: float = ICON_SIZE * (1.3 if is_big else 1.0) * sf
	var dark := color.darkened(0.3)

	# Ombre
	var shadow_hull := PackedVector2Array([
		pos + shadow + Vector2(-s * 0.8, 0),
		pos + shadow + Vector2(-s * 0.3, -s * 0.35),
		pos + shadow + Vector2(s * 0.5, -s * 0.35),
		pos + shadow + Vector2(s * 0.8, 0),
		pos + shadow + Vector2(s * 0.5, s * 0.35),
		pos + shadow + Vector2(-s * 0.3, s * 0.35),
	])
	draw_colored_polygon(shadow_hull, Color(0, 0, 0, 0.3))

	# Coque (hexagone allongé, proue à droite)
	var hull := PackedVector2Array([
		pos + Vector2(-s * 0.8, 0),        # Poupe
		pos + Vector2(-s * 0.3, -s * 0.35),
		pos + Vector2(s * 0.5, -s * 0.35),
		pos + Vector2(s * 0.8, 0),         # Proue
		pos + Vector2(s * 0.5, s * 0.35),
		pos + Vector2(-s * 0.3, s * 0.35),
	])
	draw_colored_polygon(hull, color)

	# Pont (ligne centrale)
	draw_line(pos + Vector2(-s * 0.5, 0), pos + Vector2(s * 0.5, 0), dark, 1.5)

	# Cheminée / mât
	draw_line(pos + Vector2(0, 0), pos + Vector2(0, -s * 0.5), dark, 2.0)

	if is_big:
		# Croiseur: 2 cheminées + pont plus large
		draw_line(pos + Vector2(-s * 0.25, 0), pos + Vector2(-s * 0.25, -s * 0.4), dark, 1.5)
		draw_line(pos + Vector2(s * 0.25, 0), pos + Vector2(s * 0.25, -s * 0.4), dark, 1.5)
		# Ligne de flottaison
		draw_line(pos + Vector2(-s * 0.6, s * 0.15), pos + Vector2(s * 0.6, s * 0.15),
			color.lightened(0.3), 1.0)

# ===== DRAPEAU =====

func _draw_flag(pos: Vector2, color: Color, shadow: Vector2, sf: float = 1.0) -> void:
	var s: float = ICON_SIZE * sf

	# Mât
	draw_line(pos + shadow + Vector2(0, s * 0.6), pos + shadow + Vector2(0, -s * 0.7),
		Color(0, 0, 0, 0.3), 2.0)
	draw_line(pos + Vector2(0, s * 0.6), pos + Vector2(0, -s * 0.7),
		Color(0.4, 0.3, 0.2), 2.0)

	# Drapeau (rectangle ondulant)
	var flag := PackedVector2Array([
		pos + Vector2(0, -s * 0.7),
		pos + Vector2(s * 0.7, -s * 0.5),
		pos + Vector2(s * 0.6, -s * 0.2),
		pos + Vector2(0, -s * 0.3),
	])
	draw_colored_polygon(flag, color)
	# Bordure du drapeau
	draw_polyline(flag, color.lightened(0.3), 1.0)

# ===== POWER (étoile) =====

func _draw_power(pos: Vector2, color: Color, shadow: Vector2, sf: float = 1.0) -> void:
	var s: float = ICON_SIZE * 0.7 * sf
	_draw_star(pos + shadow, s, Color(0, 0, 0, 0.3))
	_draw_star(pos, s, Color(1.0, 0.85, 0.2))  # Toujours doré

func _draw_star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(10):
		var angle: float = -PI / 2 + i * TAU / 10
		var r: float = radius if i % 2 == 0 else radius * 0.45
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, color)

# ===== MÉGA-MISSILE =====

func _draw_missile(pos: Vector2, color: Color, shadow: Vector2, sf: float = 1.0) -> void:
	var s: float = ICON_SIZE * 1.2 * sf

	# Ombre
	draw_circle(pos + shadow, s * 0.3, Color(0, 0, 0, 0.3))

	# Corps du missile (rectangle vertical)
	var body := Rect2(pos - Vector2(s * 0.15, s * 0.6), Vector2(s * 0.3, s * 0.9))
	draw_rect(body, color)

	# Ogive (triangle)
	var tip := PackedVector2Array([
		pos + Vector2(0, -s * 0.8),
		pos + Vector2(-s * 0.15, -s * 0.6),
		pos + Vector2(s * 0.15, -s * 0.6),
	])
	draw_colored_polygon(tip, color.lightened(0.2))

	# Ailerons
	var fin_l := PackedVector2Array([
		pos + Vector2(-s * 0.15, s * 0.2),
		pos + Vector2(-s * 0.4, s * 0.4),
		pos + Vector2(-s * 0.15, s * 0.3),
	])
	var fin_r := PackedVector2Array([
		pos + Vector2(s * 0.15, s * 0.2),
		pos + Vector2(s * 0.4, s * 0.4),
		pos + Vector2(s * 0.15, s * 0.3),
	])
	draw_colored_polygon(fin_l, color.darkened(0.2))
	draw_colored_polygon(fin_r, color.darkened(0.2))

	# Symbole radioactif au centre
	draw_circle(pos, s * 0.1, Color(1.0, 0.9, 0.0))
