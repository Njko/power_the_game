extends PanelContainer
class_name UnitInfoPanel

## Panneau latéral affichant les détails d'une unité sélectionnée.
## Construit dynamiquement (pas de .tscn). Style sombre/doré cohérent avec OrderPanel.

var _nom_label: Label
var _puissance_label: Label
var _deplacement_label: Label
var _terrain_label: Label
var _groupe_label: Label
var _icone: IconeUnite


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(180, 0)

	# Style du PanelContainer
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.09, 0.16, 0.95)
	panel_style.border_color = Color(0.35, 0.40, 0.55, 0.6)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", panel_style)

	# MarginContainer
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	# VBoxContainer
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Couleur de police par défaut
	var couleur_texte := Color(0.95, 0.95, 1.0)

	# Nom de l'unité
	_nom_label = Label.new()
	_nom_label.add_theme_font_size_override("font_size", 18)
	_nom_label.add_theme_color_override("font_color", couleur_texte)
	_nom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_nom_label)

	vbox.add_child(HSeparator.new())

	# Icône de l'unité
	_icone = IconeUnite.new()
	_icone.custom_minimum_size = Vector2(80, 80)
	vbox.add_child(_icone)

	vbox.add_child(HSeparator.new())

	# Puissance
	_puissance_label = Label.new()
	_puissance_label.add_theme_font_size_override("font_size", 14)
	_puissance_label.add_theme_color_override("font_color", couleur_texte)
	vbox.add_child(_puissance_label)

	# Déplacement
	_deplacement_label = Label.new()
	_deplacement_label.add_theme_font_size_override("font_size", 14)
	_deplacement_label.add_theme_color_override("font_color", couleur_texte)
	vbox.add_child(_deplacement_label)

	# Terrain
	_terrain_label = Label.new()
	_terrain_label.add_theme_font_size_override("font_size", 12)
	_terrain_label.add_theme_color_override("font_color", couleur_texte)
	_terrain_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_terrain_label)

	vbox.add_child(HSeparator.new())

	# Groupe
	_groupe_label = Label.new()
	_groupe_label.add_theme_font_size_override("font_size", 11)
	_groupe_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(_groupe_label)


func afficher_unite(unite: UnitData) -> void:
	_nom_label.text = unite.get_display_name()
	_nom_label.add_theme_color_override("font_color", GameEnums.get_player_color(unite.owner))
	_puissance_label.text = "Puissance : %d" % GameEnums.get_unit_power(unite.unit_type)
	_deplacement_label.text = "Déplacement : %d" % GameEnums.get_unit_max_move(unite.unit_type)
	_terrain_label.text = "Terrain : %s" % _get_texte_terrain(unite.unit_type)
	_groupe_label.text = _get_texte_groupe(unite.unit_type)
	_icone.type_unite = unite.unit_type
	_icone.couleur_joueur = GameEnums.get_player_color(unite.owner)
	_icone.proprietaire = unite.owner
	_icone.queue_redraw()
	visible = true


func cacher() -> void:
	visible = false


func _get_texte_terrain(type: GameEnums.UnitType) -> String:
	if GameEnums.is_land_unit(type):
		return "Terre, Côte, Île, QG"
	elif GameEnums.is_air_unit(type):
		return "Tout sauf Mer"
	elif GameEnums.is_naval_unit(type):
		return "Mer, Côte"
	else:
		return "—"


func _get_texte_groupe(type: GameEnums.UnitType) -> String:
	var groupe: int = GameEnums.get_unit_group(type)
	if groupe == 1:
		return "Groupe 1 (base)"
	elif groupe == 2:
		return "Groupe 2 (élite)"
	else:
		return "Spécial"


# =============================================================================
# Classe interne : IconeUnite — dessine l'unité en grand dans le panneau
# =============================================================================

class IconeUnite extends Control:
	var type_unite: GameEnums.UnitType = GameEnums.UnitType.SOLDIER
	var couleur_joueur: Color = Color.WHITE
	var proprietaire: GameEnums.PlayerColor = GameEnums.PlayerColor.GREEN

	func _draw() -> void:
		var center := Vector2(size.x * 0.5, size.y * 0.5)
		var couleur := couleur_joueur
		var s: float = 24.0  # Taille de base (sera multipliée dans chaque méthode)

		match type_unite:
			GameEnums.UnitType.SOLDIER:
				_dessiner_soldat(center, couleur, s, false)
			GameEnums.UnitType.REGIMENT:
				_dessiner_soldat(center, couleur, s * 1.3, true)
			GameEnums.UnitType.TANK:
				_dessiner_tank(center, couleur, s, false)
			GameEnums.UnitType.HEAVY_TANK:
				_dessiner_tank(center, couleur, s * 1.3, true)
			GameEnums.UnitType.FIGHTER:
				_dessiner_avion(center, couleur, s, false)
			GameEnums.UnitType.BOMBER:
				_dessiner_avion(center, couleur, s * 1.3, true)
			GameEnums.UnitType.DESTROYER:
				_dessiner_navire(center, couleur, s, false)
			GameEnums.UnitType.CRUISER:
				_dessiner_navire(center, couleur, s * 1.3, true)
			GameEnums.UnitType.FLAG:
				_dessiner_drapeau(center, couleur, s)
			GameEnums.UnitType.POWER:
				_dessiner_power(center, s)
			GameEnums.UnitType.MEGA_MISSILE:
				_dessiner_missile(center, couleur, s * 1.3)

	# ----- Soldat / Régiment -----
	func _dessiner_soldat(pos: Vector2, color: Color, s: float, is_big: bool) -> void:
		var dark := color.darkened(0.3)

		# Corps — silhouette accroupie (polygone 8 points)
		var corps := PackedVector2Array([
			pos + Vector2(-s * 0.45, s * 0.55),
			pos + Vector2(-s * 0.35, s * 0.1),
			pos + Vector2(-s * 0.2, -s * 0.05),
			pos + Vector2(-s * 0.35, -s * 0.3),
			pos + Vector2(s * 0.35, -s * 0.3),
			pos + Vector2(s * 0.2, -s * 0.05),
			pos + Vector2(s * 0.35, s * 0.1),
			pos + Vector2(s * 0.5, s * 0.55),
		])
		draw_colored_polygon(corps, dark)

		# Tête (cercle)
		var tete_pos := pos + Vector2(0, -s * 0.5)
		draw_circle(tete_pos, s * 0.25, color)
		draw_arc(tete_pos, s * 0.25, 0, TAU, 16, color.lightened(0.3), 1.5)

		# Fusil
		var fusil_base := pos + Vector2(s * 0.25, -s * 0.3)
		var fusil_bout := pos + Vector2(s * 0.55, -s * 0.7)
		draw_line(fusil_base, fusil_bout, dark.darkened(0.2), 2.5)

		if is_big:
			# Chevron V pour régiment
			var chev_y: float = s * 0.7
			draw_line(pos + Vector2(-s * 0.3, chev_y), pos + Vector2(0, chev_y + s * 0.15),
				color.lightened(0.4), 2.5)
			draw_line(pos + Vector2(0, chev_y + s * 0.15), pos + Vector2(s * 0.3, chev_y),
				color.lightened(0.4), 2.5)

	# ----- Tank / Char d'Assaut -----
	func _dessiner_tank(pos: Vector2, color: Color, s: float, is_big: bool) -> void:
		var dark := color.darkened(0.3)

		# Chenille haute
		var chenille_h := Rect2(pos - Vector2(s * 0.65, s * 0.4), Vector2(s * 1.3, s * 0.22))
		draw_rect(chenille_h, dark.darkened(0.2))
		# Chenille basse
		var chenille_b := Rect2(pos + Vector2(-s * 0.65, s * 0.2), Vector2(s * 1.3, s * 0.22))
		draw_rect(chenille_b, dark.darkened(0.2))

		# Châssis trapézoïdal
		var chassis := PackedVector2Array([
			pos + Vector2(-s * 0.6, -s * 0.18),
			pos + Vector2(s * 0.5, -s * 0.12),
			pos + Vector2(s * 0.55, s * 0.2),
			pos + Vector2(-s * 0.6, s * 0.2),
		])
		draw_colored_polygon(chassis, color)

		# Tourelle
		var tourelle_w: float = s * (0.5 if is_big else 0.4)
		var tourelle_h: float = s * 0.3
		var tourelle_rect := Rect2(pos - Vector2(tourelle_w * 0.5, tourelle_h * 0.7), Vector2(tourelle_w, tourelle_h))
		draw_rect(tourelle_rect, color.lightened(0.15))

		# Canon
		var canon_len: float = s * (1.0 if is_big else 0.7)
		var canon_y: float = -s * 0.15
		draw_line(pos + Vector2(tourelle_w * 0.3, canon_y),
			pos + Vector2(tourelle_w * 0.3 + canon_len, canon_y),
			dark, 3.0 if is_big else 2.5)
		# Frein de bouche
		var muzzle_x: float = tourelle_w * 0.3 + canon_len
		draw_rect(Rect2(pos + Vector2(muzzle_x - s * 0.04, canon_y - s * 0.06), Vector2(s * 0.08, s * 0.12)),
			dark)

		if is_big:
			# Emblème étoile sur tourelle
			draw_circle(pos + Vector2(0, -s * 0.15), s * 0.1, color.lightened(0.4))

	# ----- Chasseur / Bombardier -----
	func _dessiner_avion(pos: Vector2, color: Color, s: float, is_big: bool) -> void:
		var dark := color.darkened(0.3)

		if is_big:
			# === BOMBARDIER (style B-52) ===
			# Fuselage large et trapu
			var fuselage := PackedVector2Array([
				pos + Vector2(0, -s * 0.6),
				pos + Vector2(-s * 0.18, s * 0.05),
				pos + Vector2(-s * 0.22, s * 0.4),
				pos + Vector2(s * 0.22, s * 0.4),
				pos + Vector2(s * 0.18, s * 0.05),
			])
			draw_colored_polygon(fuselage, color)

			# Ailes droites très larges
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

			# 4 moteurs
			draw_circle(pos + Vector2(-s * 0.35, s * 0.07), s * 0.06, dark.darkened(0.3))
			draw_circle(pos + Vector2(-s * 0.6, s * 0.1), s * 0.06, dark.darkened(0.3))
			draw_circle(pos + Vector2(s * 0.35, s * 0.07), s * 0.06, dark.darkened(0.3))
			draw_circle(pos + Vector2(s * 0.6, s * 0.1), s * 0.06, dark.darkened(0.3))

			# Queue — stabilisateur vertical
			var queue := PackedVector2Array([
				pos + Vector2(-s * 0.08, s * 0.3),
				pos + Vector2(s * 0.08, s * 0.3),
				pos + Vector2(0, s * 0.6),
			])
			draw_colored_polygon(queue, dark)
			draw_line(pos + Vector2(0, s * 0.25), pos + Vector2(0, s * 0.6), dark.darkened(0.1), 2.0)

			# Cockpit
			draw_circle(pos + Vector2(0, -s * 0.45), s * 0.06, color.lightened(0.5))
		else:
			# === CHASSEUR (ailes delta) ===
			# Fuselage étroit pointant vers le haut
			var fuselage := PackedVector2Array([
				pos + Vector2(0, -s * 0.75),
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

	# ----- Destroyer / Croiseur -----
	func _dessiner_navire(pos: Vector2, color: Color, s: float, is_big: bool) -> void:
		var dark := color.darkened(0.3)

		if is_big:
			# === CROISEUR ===
			# Coque longue
			var coque := PackedVector2Array([
				pos + Vector2(-s * 0.85, s * 0.05),
				pos + Vector2(-s * 0.7, -s * 0.25),
				pos + Vector2(s * 0.6, -s * 0.25),
				pos + Vector2(s * 0.9, s * 0.05),
				pos + Vector2(s * 0.5, s * 0.3),
				pos + Vector2(-s * 0.7, s * 0.3),
			])
			draw_colored_polygon(coque, color)

			# Pont
			draw_line(pos + Vector2(-s * 0.65, -s * 0.05), pos + Vector2(s * 0.6, -s * 0.05),
				dark, 1.5)

			# Deux blocs superstructure
			draw_rect(Rect2(pos + Vector2(-s * 0.35, -s * 0.25), Vector2(s * 0.25, s * 0.2)),
				dark.lightened(0.1))
			draw_rect(Rect2(pos + Vector2(s * 0.1, -s * 0.25), Vector2(s * 0.25, s * 0.2)),
				dark.lightened(0.1))

			# Tourelles de canon
			draw_circle(pos + Vector2(-s * 0.5, -s * 0.12), s * 0.08, dark.darkened(0.1))
			draw_circle(pos + Vector2(s * 0.45, -s * 0.12), s * 0.08, dark.darkened(0.1))

			# Deux mâts
			draw_line(pos + Vector2(-s * 0.22, -s * 0.25), pos + Vector2(-s * 0.22, -s * 0.55),
				dark, 1.5)
			draw_line(pos + Vector2(s * 0.22, -s * 0.25), pos + Vector2(s * 0.22, -s * 0.55),
				dark, 1.5)

			# Ligne de flottaison
			draw_line(pos + Vector2(-s * 0.7, s * 0.18), pos + Vector2(s * 0.6, s * 0.18),
				color.lightened(0.3), 1.0)
		else:
			# === DESTROYER ===
			# Coque
			var coque := PackedVector2Array([
				pos + Vector2(-s * 0.75, s * 0.05),
				pos + Vector2(-s * 0.55, -s * 0.3),
				pos + Vector2(s * 0.5, -s * 0.3),
				pos + Vector2(s * 0.8, s * 0.05),
				pos + Vector2(s * 0.4, s * 0.3),
				pos + Vector2(-s * 0.55, s * 0.3),
			])
			draw_colored_polygon(coque, color)

			# Pont
			draw_line(pos + Vector2(-s * 0.5, -s * 0.05), pos + Vector2(s * 0.5, -s * 0.05),
				dark, 1.5)

			# Superstructure centrale
			draw_rect(Rect2(pos + Vector2(-s * 0.15, -s * 0.3), Vector2(s * 0.3, s * 0.22)),
				dark.lightened(0.1))

			# Mât unique
			draw_line(pos + Vector2(0, -s * 0.3), pos + Vector2(0, -s * 0.6),
				dark, 2.0)

	# ----- Drapeau -----
	func _dessiner_drapeau(pos: Vector2, color: Color, s: float) -> void:
		# Base carrée
		var base_size: float = s * 0.3
		draw_rect(Rect2(pos + Vector2(-base_size * 0.5, s * 0.45), Vector2(base_size, base_size)),
			Color(0.35, 0.25, 0.15))

		# Mât
		draw_line(pos + Vector2(-s * 0.05, s * 0.5), pos + Vector2(-s * 0.05, -s * 0.75),
			Color(0.4, 0.3, 0.2), 2.5)

		# Fanion ondulant
		var drapeau := PackedVector2Array([
			pos + Vector2(-s * 0.05, -s * 0.75),
			pos + Vector2(s * 0.55, -s * 0.6),
			pos + Vector2(s * 0.65, -s * 0.45),
			pos + Vector2(s * 0.5, -s * 0.3),
			pos + Vector2(-s * 0.05, -s * 0.35),
		])
		draw_colored_polygon(drapeau, color)
		draw_polyline(drapeau, color.lightened(0.3), 1.5)

	# ----- Power (éclair) -----
	func _dessiner_power(pos: Vector2, s: float) -> void:
		var gold := Color(1.0, 0.85, 0.2)

		# Halo subtil
		_dessiner_eclair(pos, s * 0.8 * 1.15, Color(1.0, 0.9, 0.3, 0.3))
		# Éclair doré
		_dessiner_eclair(pos, s * 0.8, gold)

	func _dessiner_eclair(center: Vector2, s: float, color: Color) -> void:
		var bolt := PackedVector2Array([
			center + Vector2(-s * 0.1, -s * 0.7),
			center + Vector2(s * 0.3, -s * 0.7),
			center + Vector2(s * 0.05, -s * 0.15),
			center + Vector2(s * 0.35, -s * 0.15),
			center + Vector2(s * 0.1, s * 0.7),
			center + Vector2(-s * 0.15, s * 0.1),
			center + Vector2(-s * 0.35, s * 0.1),
			center + Vector2(-s * 0.1, -s * 0.25),
		])
		draw_colored_polygon(bolt, color)

	# ----- Méga-Missile -----
	func _dessiner_missile(pos: Vector2, color: Color, s: float) -> void:
		# Corps du missile
		var corps := PackedVector2Array([
			pos + Vector2(-s * 0.14, -s * 0.5),
			pos + Vector2(s * 0.14, -s * 0.5),
			pos + Vector2(s * 0.17, s * 0.35),
			pos + Vector2(-s * 0.17, s * 0.35),
		])
		draw_colored_polygon(corps, color)

		# Ogive
		var ogive := PackedVector2Array([
			pos + Vector2(0, -s * 0.85),
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

		# Flamme d'échappement
		var flamme := PackedVector2Array([
			pos + Vector2(-s * 0.1, s * 0.35),
			pos + Vector2(0, s * 0.6),
			pos + Vector2(s * 0.1, s * 0.35),
		])
		draw_colored_polygon(flamme, Color(1.0, 0.4, 0.1))

		# Symbole radioactif
		draw_circle(pos + Vector2(0, -s * 0.05), s * 0.12, Color(1.0, 0.9, 0.0))
