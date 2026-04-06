extends Node2D
class_name UnitRenderer

## Affiche les unités sur le plateau avec des icônes géométriques distinctes.
## Chaque type d'unité a une forme unique, colorée selon le joueur.
## Redessiné pour être fidèle aux pièces meeple du jeu original Spear's 1981.

var board_renderer: BoardRenderer
var board_3d  # Board3D — set by main.gd
var game_state: GameState

const ICON_SIZE := 20.0      # Rayon de base des icônes
const ICON_SPACING := 32.0   # Espace entre icônes dans un secteur
const MAX_PER_ROW := 3       # Max icônes par ligne dans un secteur

# Position tracking pour hit-testing
var _icon_positions: Array = []

# Unité sélectionnée (définie par main.gd)
var selected_unit: UnitData = null

func update_display() -> void:
	queue_redraw()

func _process(_delta: float) -> void:
	if board_3d != null and game_state != null and board_3d.camera != null:
		if board_3d.camera.is_inside_tree() and board_3d.camera.is_current():
			queue_redraw()

func _draw() -> void:
	if game_state == null:
		return

	_icon_positions.clear()

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
	# Réduction dynamique pour secteurs encombrés
	if count > 9:
		spacing *= 0.75
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

		# Enregistrer la position pour le hit-testing
		_icon_positions.append({pos = pos, unit = unit, radius = ICON_SIZE * scale_factor})

		_draw_unit_icon(pos, unit.unit_type, color, unit.owner, scale_factor, unit)

## Retourne l'unité la plus proche de la position écran donnée, ou null
func get_unit_at_screen_pos(screen_pos: Vector2) -> UnitData:
	var meilleur_unit: UnitData = null
	var meilleure_dist: float = INF
	for entry in _icon_positions:
		var dist: float = screen_pos.distance_to(entry.pos)
		if dist < entry.radius * 1.5 and dist < meilleure_dist:
			meilleure_dist = dist
			meilleur_unit = entry.unit
	return meilleur_unit

func _draw_unit_icon(pos: Vector2, unit_type: GameEnums.UnitType, color: Color, owner: GameEnums.PlayerColor, sf: float = 1.0, unit: UnitData = null) -> void:
	# Halo de sélection
	if unit != null and unit == selected_unit:
		var glow_radius: float = ICON_SIZE * 1.4 * sf
		draw_circle(pos, glow_radius, Color(1.0, 1.0, 0.6, 0.35))
		draw_circle(pos, glow_radius * 0.85, Color(1.0, 1.0, 0.8, 0.25))

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
# Silhouette accroupie avec fusil

func _draw_soldier(pos: Vector2, color: Color, shadow: Vector2, is_big: bool, sf: float = 1.0) -> void:
	var s: float = ICON_SIZE * (1.3 if is_big else 1.0) * sf
	var dark := color.darkened(0.3)

	# Ombre du corps
	draw_circle(pos + shadow + Vector2(0, -s * 0.3), s * 0.4, Color(0, 0, 0, 0.3))

	# Corps — silhouette accroupie (polygone 7 points)
	var corps := PackedVector2Array([
		pos + Vector2(-s * 0.45, s * 0.55),   # Pied gauche
		pos + Vector2(-s * 0.35, s * 0.1),    # Genou gauche
		pos + Vector2(-s * 0.2, -s * 0.05),   # Taille gauche
		pos + Vector2(-s * 0.35, -s * 0.3),   # Épaule gauche
		pos + Vector2(s * 0.35, -s * 0.3),    # Épaule droite
		pos + Vector2(s * 0.2, -s * 0.05),    # Taille droite
		pos + Vector2(s * 0.35, s * 0.1),     # Genou droit
		pos + Vector2(s * 0.5, s * 0.55),     # Pied droit
	])
	draw_colored_polygon(corps, dark)

	# Tête (cercle)
	var tete_pos := pos + Vector2(0, -s * 0.5)
	draw_circle(tete_pos, s * 0.25, color)
	draw_arc(tete_pos, s * 0.25, 0, TAU, 16, color.lightened(0.3), 1.0 * sf)

	# Fusil — ligne inclinée depuis l'épaule droite
	var fusil_base := pos + Vector2(s * 0.25, -s * 0.3)
	var fusil_bout := pos + Vector2(s * 0.55, -s * 0.7)
	draw_line(fusil_base, fusil_bout, dark.darkened(0.2), 2.0 * sf)

	if is_big:
		# Chevron V pour régiment
		var chev_y: float = s * 0.7
		draw_line(pos + Vector2(-s * 0.3, chev_y), pos + Vector2(0, chev_y + s * 0.15),
			color.lightened(0.4), 2.0 * sf)
		draw_line(pos + Vector2(0, chev_y + s * 0.15), pos + Vector2(s * 0.3, chev_y),
			color.lightened(0.4), 2.0 * sf)

# ===== TANK / CHAR D'ASSAUT =====
# Profil de véhicule compact

func _draw_tank(pos: Vector2, color: Color, shadow: Vector2, is_big: bool, sf: float = 1.0) -> void:
	var s: float = ICON_SIZE * (1.3 if is_big else 1.0) * sf
	var dark := color.darkened(0.3)

	# Ombre
	draw_rect(Rect2(pos + shadow - Vector2(s * 0.6, s * 0.3), Vector2(s * 1.2, s * 0.7)),
		Color(0, 0, 0, 0.3))

	# Chenille haute (rectangle arrondi sombre)
	var chenille_h := Rect2(pos - Vector2(s * 0.65, s * 0.4), Vector2(s * 1.3, s * 0.22))
	draw_rect(chenille_h, dark.darkened(0.2))
	# Chenille basse
	var chenille_b := Rect2(pos + Vector2(-s * 0.65, s * 0.2), Vector2(s * 1.3, s * 0.22))
	draw_rect(chenille_b, dark.darkened(0.2))

	# Châssis trapézoïdal (plus étroit à droite/avant)
	var chassis := PackedVector2Array([
		pos + Vector2(-s * 0.6, -s * 0.18),   # Arrière haut
		pos + Vector2(s * 0.5, -s * 0.12),    # Avant haut
		pos + Vector2(s * 0.55, s * 0.2),     # Avant bas
		pos + Vector2(-s * 0.6, s * 0.2),     # Arrière bas
	])
	draw_colored_polygon(chassis, color)

	# Tourelle (carré arrondi centré)
	var tourelle_w: float = s * (0.5 if is_big else 0.4)
	var tourelle_h: float = s * 0.3
	var tourelle_rect := Rect2(pos - Vector2(tourelle_w * 0.5, tourelle_h * 0.7), Vector2(tourelle_w, tourelle_h))
	draw_rect(tourelle_rect, color.lightened(0.15))

	# Canon
	var canon_len: float = s * (1.0 if is_big else 0.7)
	var canon_y: float = -s * 0.15
	draw_line(pos + Vector2(tourelle_w * 0.3, canon_y),
		pos + Vector2(tourelle_w * 0.3 + canon_len, canon_y),
		dark, (2.5 if is_big else 2.0) * sf)
	# Frein de bouche
	var muzzle_x: float = tourelle_w * 0.3 + canon_len
	draw_rect(Rect2(pos + Vector2(muzzle_x - s * 0.04, canon_y - s * 0.06), Vector2(s * 0.08, s * 0.12)),
		dark)

	if is_big:
		# Emblème étoile sur tourelle
		draw_circle(pos + Vector2(0, -s * 0.15), s * 0.1, color.lightened(0.4))

# ===== CHASSEUR / BOMBARDIER =====
# Avion à ailes delta / B-52

func _draw_plane(pos: Vector2, color: Color, shadow: Vector2, is_big: bool, sf: float = 1.0) -> void:
	var s: float = ICON_SIZE * (1.3 if is_big else 1.0) * sf
	var dark := color.darkened(0.3)

	if is_big:
		# === BOMBARDIER (style B-52) ===
		# Ombre
		var ombre_bomb := PackedVector2Array([
			pos + shadow + Vector2(0, -s * 0.65),
			pos + shadow + Vector2(-s * 0.2, s * 0.4),
			pos + shadow + Vector2(s * 0.2, s * 0.4),
		])
		draw_colored_polygon(ombre_bomb, Color(0, 0, 0, 0.3))

		# Fuselage large et trapu
		var fuselage := PackedVector2Array([
			pos + Vector2(0, -s * 0.6),       # Nez
			pos + Vector2(-s * 0.18, s * 0.05),
			pos + Vector2(-s * 0.22, s * 0.4),
			pos + Vector2(s * 0.22, s * 0.4),
			pos + Vector2(s * 0.18, s * 0.05),
		])
		draw_colored_polygon(fuselage, color)

		# Ailes droites (non balayées) très larges
		var aile_g := PackedVector2Array([
			pos + Vector2(-s * 0.12, -s * 0.05),
			pos + Vector2(-s * 0.9, s * 0.05),
			pos + Vector2(-s * 0.85, s * 0.15),
			pos + Vector2(-s * 0.1, s * 0.1),
		])
		var aile_d := PackedVector2Array([
			pos + Vector2(s * 0.12, -s * 0.05),
			pos + Vector2(s * 0.9, s * 0.05),
			pos + Vector2(s * 0.85, s * 0.15),
			pos + Vector2(s * 0.1, s * 0.1),
		])
		draw_colored_polygon(aile_g, dark)
		draw_colored_polygon(aile_d, dark)

		# 4 moteurs (2 par aile)
		draw_circle(pos + Vector2(-s * 0.35, s * 0.07), s * 0.06, dark.darkened(0.3))
		draw_circle(pos + Vector2(-s * 0.6, s * 0.1), s * 0.06, dark.darkened(0.3))
		draw_circle(pos + Vector2(s * 0.35, s * 0.07), s * 0.06, dark.darkened(0.3))
		draw_circle(pos + Vector2(s * 0.6, s * 0.1), s * 0.06, dark.darkened(0.3))

		# Queue — stabilisateur vertical plus haut
		var queue := PackedVector2Array([
			pos + Vector2(-s * 0.08, s * 0.3),
			pos + Vector2(s * 0.08, s * 0.3),
			pos + Vector2(0, s * 0.6),
		])
		draw_colored_polygon(queue, dark)
		# Dérive verticale
		draw_line(pos + Vector2(0, s * 0.25), pos + Vector2(0, s * 0.6), dark.darkened(0.1), 2.0 * sf)

		# Cockpit
		draw_circle(pos + Vector2(0, -s * 0.45), s * 0.06, color.lightened(0.5))
	else:
		# === CHASSEUR (ailes delta) ===
		# Ombre
		var ombre_chass := PackedVector2Array([
			pos + shadow + Vector2(0, -s * 0.75),
			pos + shadow + Vector2(-s * 0.55, s * 0.45),
			pos + shadow + Vector2(s * 0.55, s * 0.45),
		])
		draw_colored_polygon(ombre_chass, Color(0, 0, 0, 0.3))

		# Fuselage étroit pointant vers le haut
		var fuselage := PackedVector2Array([
			pos + Vector2(0, -s * 0.75),      # Nez
			pos + Vector2(-s * 0.12, s * 0.1),
			pos + Vector2(-s * 0.15, s * 0.4),
			pos + Vector2(s * 0.15, s * 0.4),
			pos + Vector2(s * 0.12, s * 0.1),
		])
		draw_colored_polygon(fuselage, color)

		# Ailes delta balayées
		var aile_g := PackedVector2Array([
			pos + Vector2(-s * 0.1, -s * 0.1),
			pos + Vector2(-s * 0.7, s * 0.35),
			pos + Vector2(-s * 0.12, s * 0.2),
		])
		var aile_d := PackedVector2Array([
			pos + Vector2(s * 0.1, -s * 0.1),
			pos + Vector2(s * 0.7, s * 0.35),
			pos + Vector2(s * 0.12, s * 0.2),
		])
		draw_colored_polygon(aile_g, dark)
		draw_colored_polygon(aile_d, dark)

		# Queue — petit V inversé
		var queue := PackedVector2Array([
			pos + Vector2(-s * 0.2, s * 0.35),
			pos + Vector2(s * 0.2, s * 0.35),
			pos + Vector2(0, s * 0.55),
		])
		draw_colored_polygon(queue, dark)

		# Cockpit
		draw_circle(pos + Vector2(0, -s * 0.5), s * 0.06, color.lightened(0.5))

# ===== DESTROYER / CROISEUR =====
# Profil latéral de navire de guerre

func _draw_ship(pos: Vector2, color: Color, shadow: Vector2, is_big: bool, sf: float = 1.0) -> void:
	var s: float = ICON_SIZE * (1.3 if is_big else 1.0) * sf
	var dark := color.darkened(0.3)

	if is_big:
		# === CROISEUR ===
		# Ombre
		var ombre_coque := PackedVector2Array([
			pos + shadow + Vector2(-s * 0.85, s * 0.05),  # Poupe
			pos + shadow + Vector2(-s * 0.7, -s * 0.25),
			pos + shadow + Vector2(s * 0.6, -s * 0.25),
			pos + shadow + Vector2(s * 0.9, s * 0.05),    # Proue
			pos + shadow + Vector2(s * 0.5, s * 0.3),
			pos + shadow + Vector2(-s * 0.7, s * 0.3),
		])
		draw_colored_polygon(ombre_coque, Color(0, 0, 0, 0.3))

		# Coque longue
		var coque := PackedVector2Array([
			pos + Vector2(-s * 0.85, s * 0.05),   # Poupe
			pos + Vector2(-s * 0.7, -s * 0.25),
			pos + Vector2(s * 0.6, -s * 0.25),
			pos + Vector2(s * 0.9, s * 0.05),     # Proue pointue
			pos + Vector2(s * 0.5, s * 0.3),
			pos + Vector2(-s * 0.7, s * 0.3),
		])
		draw_colored_polygon(coque, color)

		# Pont (ligne horizontale)
		draw_line(pos + Vector2(-s * 0.65, -s * 0.05), pos + Vector2(s * 0.6, -s * 0.05),
			dark, 1.5 * sf)

		# Deux blocs superstructure (avant et arrière)
		draw_rect(Rect2(pos + Vector2(-s * 0.35, -s * 0.25), Vector2(s * 0.25, s * 0.2)),
			dark.lightened(0.1))
		draw_rect(Rect2(pos + Vector2(s * 0.1, -s * 0.25), Vector2(s * 0.25, s * 0.2)),
			dark.lightened(0.1))

		# Tourelles de canon (cercles avant et arrière)
		draw_circle(pos + Vector2(-s * 0.5, -s * 0.12), s * 0.08, dark.darkened(0.1))
		draw_circle(pos + Vector2(s * 0.45, -s * 0.12), s * 0.08, dark.darkened(0.1))

		# Deux mâts
		draw_line(pos + Vector2(-s * 0.22, -s * 0.25), pos + Vector2(-s * 0.22, -s * 0.55),
			dark, 1.5 * sf)
		draw_line(pos + Vector2(s * 0.22, -s * 0.25), pos + Vector2(s * 0.22, -s * 0.55),
			dark, 1.5 * sf)

		# Ligne de flottaison
		draw_line(pos + Vector2(-s * 0.7, s * 0.18), pos + Vector2(s * 0.6, s * 0.18),
			color.lightened(0.3), 1.0 * sf)
	else:
		# === DESTROYER ===
		# Ombre
		var ombre_coque := PackedVector2Array([
			pos + shadow + Vector2(-s * 0.75, s * 0.05),
			pos + shadow + Vector2(-s * 0.55, -s * 0.3),
			pos + shadow + Vector2(s * 0.5, -s * 0.3),
			pos + shadow + Vector2(s * 0.8, s * 0.05),
			pos + shadow + Vector2(s * 0.4, s * 0.3),
			pos + shadow + Vector2(-s * 0.55, s * 0.3),
		])
		draw_colored_polygon(ombre_coque, Color(0, 0, 0, 0.3))

		# Coque — proue pointue à droite, poupe arrondie à gauche
		var coque := PackedVector2Array([
			pos + Vector2(-s * 0.75, s * 0.05),   # Poupe
			pos + Vector2(-s * 0.55, -s * 0.3),
			pos + Vector2(s * 0.5, -s * 0.3),
			pos + Vector2(s * 0.8, s * 0.05),     # Proue
			pos + Vector2(s * 0.4, s * 0.3),
			pos + Vector2(-s * 0.55, s * 0.3),
		])
		draw_colored_polygon(coque, color)

		# Pont
		draw_line(pos + Vector2(-s * 0.5, -s * 0.05), pos + Vector2(s * 0.5, -s * 0.05),
			dark, 1.5 * sf)

		# Superstructure centrale
		draw_rect(Rect2(pos + Vector2(-s * 0.15, -s * 0.3), Vector2(s * 0.3, s * 0.22)),
			dark.lightened(0.1))

		# Mât unique
		draw_line(pos + Vector2(0, -s * 0.3), pos + Vector2(0, -s * 0.6),
			dark, 2.0 * sf)

# ===== DRAPEAU =====
# Base carrée + mât + fanion ondulant

func _draw_flag(pos: Vector2, color: Color, shadow: Vector2, sf: float = 1.0) -> void:
	var s: float = ICON_SIZE * sf

	# Base carrée
	var base_size: float = s * 0.3
	draw_rect(Rect2(pos + Vector2(-base_size * 0.5, s * 0.45), Vector2(base_size, base_size)),
		Color(0.35, 0.25, 0.15))

	# Mât — ombre puis mât
	draw_line(pos + shadow + Vector2(-s * 0.05, s * 0.5), pos + shadow + Vector2(-s * 0.05, -s * 0.75),
		Color(0, 0, 0, 0.3), 2.0 * sf)
	draw_line(pos + Vector2(-s * 0.05, s * 0.5), pos + Vector2(-s * 0.05, -s * 0.75),
		Color(0.4, 0.3, 0.2), 2.0 * sf)

	# Fanion ondulant (polygone 5-6 points avec forme de vague)
	var drapeau := PackedVector2Array([
		pos + Vector2(-s * 0.05, -s * 0.75),   # Haut du mât
		pos + Vector2(s * 0.55, -s * 0.6),     # Pointe haute
		pos + Vector2(s * 0.65, -s * 0.45),    # Creux de vague
		pos + Vector2(s * 0.5, -s * 0.3),      # Pointe basse
		pos + Vector2(-s * 0.05, -s * 0.35),   # Retour au mât
	])
	draw_colored_polygon(drapeau, color)
	# Bordure du drapeau
	draw_polyline(drapeau, color.lightened(0.3), 1.0 * sf)

# ===== POWER (éclair) =====

func _draw_power(pos: Vector2, _color: Color, shadow: Vector2, sf: float = 1.0) -> void:
	var s: float = ICON_SIZE * 0.8 * sf
	var gold := Color(1.0, 0.85, 0.2)

	# Halo subtil semi-transparent
	_draw_lightning(pos, s * 1.15, Color(1.0, 0.9, 0.3, 0.3))
	# Ombre
	_draw_lightning(pos + shadow, s, Color(0, 0, 0, 0.3))
	# Éclair doré
	_draw_lightning(pos, s, gold)

func _draw_lightning(center: Vector2, s: float, color: Color) -> void:
	# Forme d'éclair en zigzag vertical (8 points)
	var bolt := PackedVector2Array([
		center + Vector2(-s * 0.1, -s * 0.7),    # Sommet gauche
		center + Vector2(s * 0.3, -s * 0.7),     # Sommet droit
		center + Vector2(s * 0.05, -s * 0.15),   # Angle intérieur haut
		center + Vector2(s * 0.35, -s * 0.15),   # Pointe droite milieu
		center + Vector2(s * 0.1, s * 0.7),      # Pointe basse
		center + Vector2(-s * 0.15, s * 0.1),    # Angle intérieur bas
		center + Vector2(-s * 0.35, s * 0.1),    # Pointe gauche milieu
		center + Vector2(-s * 0.1, -s * 0.25),   # Retour haut
	])
	draw_colored_polygon(bolt, color)

# ===== MÉGA-MISSILE =====
# Fusée verticale plus haute

func _draw_missile(pos: Vector2, color: Color, shadow: Vector2, sf: float = 1.0) -> void:
	var s: float = ICON_SIZE * 1.3 * sf

	# Ombre
	draw_circle(pos + shadow, s * 0.3, Color(0, 0, 0, 0.3))

	# Corps du missile — rectangle vertical légèrement effilé
	var corps := PackedVector2Array([
		pos + Vector2(-s * 0.14, -s * 0.5),   # Haut gauche
		pos + Vector2(s * 0.14, -s * 0.5),    # Haut droit
		pos + Vector2(s * 0.17, s * 0.35),    # Bas droit (plus large)
		pos + Vector2(-s * 0.17, s * 0.35),   # Bas gauche
	])
	draw_colored_polygon(corps, color)

	# Ogive allongée (cône pointu)
	var ogive := PackedVector2Array([
		pos + Vector2(0, -s * 0.85),           # Pointe
		pos + Vector2(-s * 0.14, -s * 0.5),
		pos + Vector2(s * 0.14, -s * 0.5),
	])
	draw_colored_polygon(ogive, color.lightened(0.2))

	# Aileron gauche
	var aileron_g := PackedVector2Array([
		pos + Vector2(-s * 0.17, s * 0.2),
		pos + Vector2(-s * 0.45, s * 0.45),
		pos + Vector2(-s * 0.17, s * 0.35),
	])
	draw_colored_polygon(aileron_g, color.darkened(0.2))

	# Aileron droit
	var aileron_d := PackedVector2Array([
		pos + Vector2(s * 0.17, s * 0.2),
		pos + Vector2(s * 0.45, s * 0.45),
		pos + Vector2(s * 0.17, s * 0.35),
	])
	draw_colored_polygon(aileron_d, color.darkened(0.2))

	# Aileron central arrière
	var aileron_c := PackedVector2Array([
		pos + Vector2(-s * 0.06, s * 0.25),
		pos + Vector2(0, s * 0.5),
		pos + Vector2(s * 0.06, s * 0.25),
	])
	draw_colored_polygon(aileron_c, color.darkened(0.15))

	# Flamme d'échappement (triangle orange-rouge)
	var flamme := PackedVector2Array([
		pos + Vector2(-s * 0.1, s * 0.35),
		pos + Vector2(0, s * 0.6),
		pos + Vector2(s * 0.1, s * 0.35),
	])
	draw_colored_polygon(flamme, Color(1.0, 0.4, 0.1))

	# Symbole radioactif — cercle jaune au centre (légèrement plus grand)
	draw_circle(pos + Vector2(0, -s * 0.05), s * 0.12, Color(1.0, 0.9, 0.0))
