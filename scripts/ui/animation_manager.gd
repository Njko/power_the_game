extends Node2D
class_name AnimationManager

## Gère toutes les animations visuelles du jeu:
## - Déplacement d'unités (glissement)
## - Flash de combat
## - Capture de pièces
## - Explosion de Méga-Missile
## - Transition de phase

signal animation_finished

const MOVE_DURATION := 0.4       # secondes par déplacement
const COMBAT_FLASH_DURATION := 0.5
const CAPTURE_DURATION := 0.3
const PHASE_TRANSITION_DURATION := 0.6

var board_renderer: BoardRenderer
var _active_tweens: Array[Tween] = []
var _animation_queue: Array[Dictionary] = []
var _is_playing := false
var speed_multiplier := 1.0

# Icônes préchargées (remplacent les emojis pour compatibilité Web)
var _icon_rebound: Texture2D = preload("res://assets/icons/icon_rebound.png")
var _icon_combat: Texture2D = preload("res://assets/icons/icon_combat.png")
var _icon_explosion: Texture2D = preload("res://assets/icons/icon_explosion.png")

# Overlay monde (pour déplacements, combats — coordonnées plateau)
var _world_overlay: Node2D
# Overlay écran (pour titres, messages — coordonnées écran)
var _screen_overlay: CanvasLayer

func _ready() -> void:
	# Conteneur pour les animations en coordonnées monde (projetées par Board3D)
	_world_overlay = Node2D.new()
	add_child(_world_overlay)

	_screen_overlay = CanvasLayer.new()
	_screen_overlay.layer = 50
	add_child(_screen_overlay)

# ===== API PUBLIQUE =====

func play_move(unit_type: GameEnums.UnitType, owner: GameEnums.PlayerColor,
		from_sector: String, to_sector: String) -> void:
	_animation_queue.append({
		"type": "move",
		"unit_type": unit_type,
		"owner": owner,
		"from": from_sector,
		"to": to_sector,
	})

func play_combat(sector_id: String, winner: GameEnums.PlayerColor) -> void:
	_animation_queue.append({
		"type": "combat",
		"sector": sector_id,
		"winner": winner,
	})

func play_capture(sector_id: String, capturer: GameEnums.PlayerColor) -> void:
	_animation_queue.append({
		"type": "capture",
		"sector": sector_id,
		"capturer": capturer,
	})

func play_rebond(unit_type: GameEnums.UnitType, owner: GameEnums.PlayerColor,
		from_sector: String, to_sector: String) -> void:
	_animation_queue.append({
		"type": "rebond",
		"unit_type": unit_type,
		"owner": owner,
		"from": from_sector,
		"to": to_sector,
	})

func play_explosion(sector_id: String) -> void:
	_animation_queue.append({
		"type": "explosion",
		"sector": sector_id,
	})

func play_missile_strike(owner: GameEnums.PlayerColor, from_sector: String, to_sector: String) -> void:
	_animation_queue.append({
		"type": "missile_strike",
		"owner": owner,
		"from": from_sector,
		"to": to_sector,
	})

func play_flag_capture(capturer: GameEnums.PlayerColor, captured: GameEnums.PlayerColor) -> void:
	_animation_queue.append({
		"type": "flag",
		"capturer": capturer,
		"captured": captured,
	})

func play_phase_title(text: String) -> void:
	_animation_queue.append({
		"type": "phase_title",
		"text": text,
	})

func play_all() -> void:
	## Lance toutes les animations en file d'attente puis émet animation_finished.
	if _animation_queue.is_empty():
		# Différer l'émission pour que le await ait le temps de s'enregistrer
		_emit_finished_deferred.call_deferred()
		return
	_is_playing = true
	_play_next()

func _emit_finished_deferred() -> void:
	_is_playing = false
	animation_finished.emit()

func skip_all() -> void:
	## Saute toutes les animations restantes.
	_animation_queue.clear()
	for tween in _active_tweens:
		if tween and tween.is_valid():
			tween.kill()
	_active_tweens.clear()
	_cleanup_overlay()
	_is_playing = false
	animation_finished.emit()

func is_playing() -> bool:
	return _is_playing

# ===== LECTURE SÉQUENTIELLE =====

func _play_next() -> void:
	if _animation_queue.is_empty():
		_is_playing = false
		animation_finished.emit()
		return

	# Regrouper les rebonds consécutifs pour les jouer en parallèle
	if _animation_queue[0]["type"] == "rebond":
		var rebonds: Array[Dictionary] = []
		while not _animation_queue.is_empty() and _animation_queue[0]["type"] == "rebond":
			rebonds.append(_animation_queue.pop_front())
		_animate_rebonds_parallel(rebonds)
		return

	var anim: Dictionary = _animation_queue.pop_front()
	match anim["type"]:
		"move":
			_animate_move(anim)
		"combat":
			_animate_combat(anim)
		"capture":
			_animate_capture(anim)
		"explosion":
			_animate_explosion(anim)
		"missile_strike":
			_animate_missile_strike(anim)
		"flag":
			_animate_flag_capture(anim)
		"phase_title":
			_animate_phase_title(anim)
		_:
			_play_next()

# ===== ANIMATIONS INDIVIDUELLES =====

func _animate_move(anim: Dictionary) -> void:
	if board_renderer == null:
		_play_next()
		return

	var from_pos: Vector2 = board_renderer.get_sector_position(anim["from"])
	var to_pos: Vector2 = board_renderer.get_sector_position(anim["to"])
	var color: Color = GameEnums.get_player_color(anim["owner"])
	var abbr: String = GameEnums.get_unit_abbreviation(anim["unit_type"])

	# Créer un sprite temporaire
	var token: Node2D = _create_unit_token(abbr, color, from_pos)

	# Arc parabolique — hauteur = 3× taille du pion
	var size := 28.0
	if abbr == "M" or abbr == "RG" or abbr == "CR":
		size = 34.0
	elif abbr == "CL" or abbr == "BM" or abbr == "DS":
		size = 30.0
	var arc_height: float = size * 3.0

	# Flèche de trajectoire
	var arrow: Line2D = _create_move_arrow(from_pos, to_pos, arc_height, color)

	var duration: float = MOVE_DURATION / speed_multiplier
	var tween := create_tween()
	_active_tweens.append(tween)
	tween.tween_method(func(t: float) -> void:
		token.position = from_pos.lerp(to_pos, t) + Vector2(0, -arc_height * sin(t * PI))
	, 0.0, 1.0, duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(func():
		token.queue_free()
		arrow.queue_free()
		_active_tweens.erase(tween)
		_play_next()
	)

func _animate_rebonds_parallel(rebonds: Array[Dictionary]) -> void:
	## Joue tous les rebonds simultanément — chaque pièce fait un arc vers son origine.
	if board_renderer == null:
		_play_next()
		return

	var duration: float = MOVE_DURATION / speed_multiplier
	var tokens: Array[Node2D] = []
	var arrows: Array[Line2D] = []
	var state := {"finished": 0}
	var total: int = rebonds.size()

	for anim in rebonds:
		var from_pos: Vector2 = board_renderer.get_sector_position(anim["from"])
		var to_pos: Vector2 = board_renderer.get_sector_position(anim["to"])
		var color: Color = GameEnums.get_player_color(anim["owner"])
		var abbr: String = GameEnums.get_unit_abbreviation(anim["unit_type"])

		var token: Node2D = _create_unit_token(abbr, color, from_pos)
		token.modulate = Color(1.0, 0.6, 0.6)
		tokens.append(token)

		# Indicateur rebond (icône)
		var rebond_icon := TextureRect.new()
		rebond_icon.texture = _icon_rebound
		rebond_icon.size = Vector2(16, 16)
		rebond_icon.position = Vector2(-8, -28)
		rebond_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		token.add_child(rebond_icon)

		# Arc
		var size := 28.0
		if abbr == "M" or abbr == "RG" or abbr == "CR":
			size = 34.0
		elif abbr == "CL" or abbr == "BM" or abbr == "DS":
			size = 30.0
		var arc_height: float = size * 3.0

		var arrow: Line2D = _create_move_arrow(from_pos, to_pos, arc_height, Color(1.0, 0.4, 0.4, 0.5))
		arrows.append(arrow)

		var tween := create_tween()
		_active_tweens.append(tween)
		tween.tween_method(func(t: float) -> void:
			token.position = from_pos.lerp(to_pos, t) + Vector2(0, -arc_height * sin(t * PI))
		, 0.0, 1.0, duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_callback(func():
			token.queue_free()
			arrow.queue_free()
			_active_tweens.erase(tween)
			state["finished"] += 1
			if state["finished"] >= total:
				_play_next()
		)

func _animate_combat(anim: Dictionary) -> void:
	if board_renderer == null:
		_play_next()
		return

	var pos: Vector2 = board_renderer.get_sector_position(anim["sector"])
	var winner_color: Color = GameEnums.get_player_color(anim["winner"])

	# Flash lumineux sur le secteur
	var flash: Node2D = _create_flash(pos, winner_color)

	var duration: float = COMBAT_FLASH_DURATION / speed_multiplier
	var tween := create_tween()
	_active_tweens.append(tween)

	tween.tween_property(flash, "modulate:a", 0.9, duration * 0.2)
	tween.tween_property(flash, "scale", Vector2(1.5, 1.5), duration * 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tween.tween_property(flash, "modulate:a", 0.0, duration * 0.5)
	tween.tween_callback(func():
		flash.queue_free()
		_active_tweens.erase(tween)
		_play_next()
	)

func _animate_capture(anim: Dictionary) -> void:
	if board_renderer == null:
		_play_next()
		return

	var pos: Vector2 = board_renderer.get_sector_position(anim["sector"])
	var color: Color = GameEnums.get_player_color(anim["capturer"])

	# Cercle qui se rétrécit (aspiration des pièces capturées)
	var ring: Node2D = _create_capture_ring(pos, color)

	var duration: float = CAPTURE_DURATION / speed_multiplier
	var tween := create_tween()
	_active_tweens.append(tween)

	tween.tween_property(ring, "scale", Vector2(0.1, 0.1), duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(ring, "modulate:a", 0.0, duration)
	tween.tween_callback(func():
		ring.queue_free()
		_active_tweens.erase(tween)
		_play_next()
	)

func _animate_explosion(anim: Dictionary) -> void:
	if board_renderer == null:
		_play_next()
		return

	var pos: Vector2 = board_renderer.get_sector_position(anim["sector"])

	# Cercle rouge-orange qui s'étend puis disparaît
	var explosion: Node2D = _create_explosion_effect(pos)

	var duration: float = 0.8 / speed_multiplier
	var tween := create_tween()
	_active_tweens.append(tween)

	tween.tween_property(explosion, "scale", Vector2(3.0, 3.0), duration * 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.parallel().tween_property(explosion, "modulate", Color(1, 0.3, 0, 0), duration) \
		.from(Color(1, 0.8, 0.2, 1))
	tween.tween_callback(func():
		explosion.queue_free()
		_active_tweens.erase(tween)
		_play_next()
	)

func _animate_missile_strike(anim: Dictionary) -> void:
	if board_renderer == null:
		_play_next()
		return

	var from_pos: Vector2 = board_renderer.get_sector_position(anim["from"])
	var to_pos: Vector2 = board_renderer.get_sector_position(anim["to"])
	var color: Color = GameEnums.get_player_color(anim["owner"])

	# Phase 1: missile vole vers la cible
	var token: Node2D = _create_unit_token("M", color, from_pos)

	var fly_duration: float = 0.5 / speed_multiplier
	var tween := create_tween()
	_active_tweens.append(tween)

	tween.tween_property(token, "position", to_pos, fly_duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func():
		token.queue_free()
		_active_tweens.erase(tween)
		# Phase 2: explosion sur la cible
		_animate_explosion({"sector": anim["to"]})
	)

func _animate_flag_capture(anim: Dictionary) -> void:
	# Grand texte qui apparaît au centre de l'écran
	var capturer_name: String = _color_name(anim["capturer"])
	var captured_name: String = _color_name(anim["captured"])
	var text: String = "%s capture le drapeau de %s!" % [capturer_name, captured_name]
	var color: Color = GameEnums.get_player_color(anim["capturer"])

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var vp_size := get_viewport().get_visible_rect().size
	label.position = Vector2(vp_size.x / 2 - 200, vp_size.y / 2 - 30)
	label.pivot_offset = Vector2(label.size.x / 2, label.size.y / 2)
	label.modulate.a = 0
	_screen_overlay.add_child(label)

	var duration := 2.0 / speed_multiplier
	var tween := create_tween()
	_active_tweens.append(tween)

	tween.tween_property(label, "modulate:a", 1.0, 0.3)
	tween.tween_property(label, "scale", Vector2(1.2, 1.2), 0.2) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.1)
	tween.tween_interval(duration * 0.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func():
		label.queue_free()
		_active_tweens.erase(tween)
		_play_next()
	)

func _animate_phase_title(anim: Dictionary) -> void:
	var text: String = anim["text"]
	var vp_size := get_viewport().get_visible_rect().size

	# Couleur selon la phase
	var text_color: Color = _get_phase_color(text)

	# Conteneur pour grouper fond + texte (facilite le fondu global)
	var container := Control.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.modulate.a = 0
	_screen_overlay.add_child(container)

	# Barre de fond semi-transparente
	var bg_bar := ColorRect.new()
	bg_bar.color = Color(0, 0, 0, 0.5)
	var bar_height := 70.0
	bg_bar.size = Vector2(vp_size.x, bar_height)
	bg_bar.position = Vector2(0, vp_size.y / 2.0 - bar_height / 2.0)
	bg_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bg_bar)

	# Texte centré précisément
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", text_color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Calculer la taille du texte pour centrer correctement
	var font: Font = label.get_theme_font("font")
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 36)
	label.position = Vector2(vp_size.x / 2.0 - text_size.x / 2.0, vp_size.y / 2.0 - text_size.y / 2.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(label)

	var duration := 1.5 / speed_multiplier
	var tween := create_tween()
	_active_tweens.append(tween)

	# Fondu entrant (20% de la durée)
	tween.tween_property(container, "modulate:a", 1.0, duration * 0.2)
	# Maintien (50% de la durée)
	tween.tween_interval(duration * 0.5)
	# Fondu sortant (30% de la durée)
	tween.tween_property(container, "modulate:a", 0.0, duration * 0.3)
	tween.tween_callback(func():
		container.queue_free()
		_active_tweens.erase(tween)
		_play_next()
	)

# ===== CRÉATION D'ÉLÉMENTS VISUELS =====

func _create_unit_token(abbr: String, color: Color, pos: Vector2) -> Node2D:
	var token := Node2D.new()
	token.position = pos
	token.z_index = 15
	_world_overlay.add_child(token)

	# Taille selon l'importance de l'unité (basée sur l'abréviation)
	var size := 28.0
	if abbr == "M" or abbr == "RG" or abbr == "CR":
		size = 34.0  # Unités puissantes
	elif abbr == "CL" or abbr == "BM" or abbr == "DS":
		size = 30.0  # Unités moyennes

	# Ombre portée (cercle décalé)
	var shadow_panel := Panel.new()
	shadow_panel.custom_minimum_size = Vector2(size, size)
	shadow_panel.size = Vector2(size, size)
	shadow_panel.position = Vector2(-size / 2.0 + 2, -size / 2.0 + 2)
	shadow_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = Color(0, 0, 0, 0.35)
	shadow_style.set_corner_radius_all(int(size / 2.0))
	shadow_style.set_content_margin_all(0)
	shadow_panel.add_theme_stylebox_override("panel", shadow_style)
	shadow_panel.z_index = -1
	token.add_child(shadow_panel)

	# Fond circulaire (coin arrondi au max = cercle)
	var bg := Panel.new()
	bg.custom_minimum_size = Vector2(size, size)
	bg.size = Vector2(size, size)
	bg.position = Vector2(-size / 2.0, -size / 2.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.2)
	style.border_color = color.lightened(0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(size / 2.0))
	style.set_content_margin_all(0)
	bg.add_theme_stylebox_override("panel", style)
	token.add_child(bg)

	# Abréviation centrée
	var label := Label.new()
	label.text = abbr
	var font_size: int = 11 if abbr.length() <= 2 else 9
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(size, size)
	label.position = Vector2(-size / 2.0, -size / 2.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	token.add_child(label)

	return token

func _create_flash(pos: Vector2, color: Color) -> Node2D:
	var flash := Node2D.new()
	flash.position = pos
	flash.modulate.a = 0
	flash.z_index = 20
	_world_overlay.add_child(flash)

	# Dessiner un cercle coloré via un ColorRect (simplifié)
	var rect := ColorRect.new()
	rect.color = color.lightened(0.5)
	rect.size = Vector2(50, 50)
	rect.position = Vector2(-25, -25)
	flash.add_child(rect)

	# Icône combat
	var cross := TextureRect.new()
	cross.texture = _icon_combat
	cross.size = Vector2(24, 24)
	cross.position = Vector2(-12, -12)
	flash.add_child(cross)

	return flash

func _create_capture_ring(pos: Vector2, color: Color) -> Node2D:
	var ring := Node2D.new()
	ring.position = pos
	ring.z_index = 20
	_world_overlay.add_child(ring)

	var rect := ColorRect.new()
	rect.color = color
	rect.color.a = 0.6
	rect.size = Vector2(40, 40)
	rect.position = Vector2(-20, -20)
	ring.add_child(rect)

	return ring

func _create_explosion_effect(pos: Vector2) -> Node2D:
	var explosion := Node2D.new()
	explosion.position = pos
	explosion.z_index = 25
	_world_overlay.add_child(explosion)

	# Centre lumineux
	var core := ColorRect.new()
	core.color = Color(1, 0.9, 0.3, 0.9)
	core.size = Vector2(30, 30)
	core.position = Vector2(-15, -15)
	explosion.add_child(core)

	# Icône explosion
	var symbol := TextureRect.new()
	symbol.texture = _icon_explosion
	symbol.size = Vector2(24, 24)
	symbol.position = Vector2(-12, -12)
	explosion.add_child(symbol)

	return explosion

func _create_move_arrow(from_pos: Vector2, to_pos: Vector2, arc_height: float, color: Color) -> Line2D:
	## Crée une flèche en arc montrant la trajectoire du mouvement.
	var line := Line2D.new()
	line.z_index = 14  # Sous le token (z_index 15)
	line.width = 3.0
	line.default_color = Color(color.r, color.g, color.b, 0.5)
	line.antialiased = true

	# Échantillonner 20 points le long de l'arc
	var num_points := 20
	for i in range(num_points + 1):
		var t: float = float(i) / float(num_points)
		var point: Vector2 = from_pos.lerp(to_pos, t) + Vector2(0, -arc_height * sin(t * PI))
		line.add_point(point)

	_world_overlay.add_child(line)

	# Pointe de flèche au bout
	_add_arrowhead(line, color)

	return line

func _add_arrowhead(line: Line2D, color: Color) -> void:
	## Ajoute un triangle (pointe de flèche) à l'extrémité d'un Line2D.
	var count: int = line.get_point_count()
	if count < 2:
		return

	var tip: Vector2 = line.get_point_position(count - 1)
	var prev: Vector2 = line.get_point_position(count - 2)
	var direction: Vector2 = (tip - prev).normalized()
	var perp: Vector2 = Vector2(-direction.y, direction.x)

	var arrow_size := 8.0
	var p1: Vector2 = tip
	var p2: Vector2 = tip - direction * arrow_size + perp * arrow_size * 0.5
	var p3: Vector2 = tip - direction * arrow_size - perp * arrow_size * 0.5

	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([p1, p2, p3])
	head.color = Color(color.r, color.g, color.b, 0.7)
	head.z_index = 14
	line.add_child(head)

func _cleanup_overlay() -> void:
	for child in _world_overlay.get_children():
		child.queue_free()
	for child in _screen_overlay.get_children():
		child.queue_free()

func _get_phase_color(phase_text: String) -> Color:
	## Retourne la couleur associée à une phase selon son nom.
	var lower: String = phase_text.to_lower()
	if lower.find("préparation") >= 0 or lower.find("preparation") >= 0:
		return Color(0.4, 0.7, 1.0)      # Bleu
	elif lower.find("exécution") >= 0 or lower.find("execution") >= 0:
		return Color(1.0, 0.75, 0.2)     # Or
	elif lower.find("résolution") >= 0 or lower.find("conflit") >= 0:
		return Color(1.0, 0.4, 0.2)      # Rouge-orangé
	elif lower.find("collecte") >= 0:
		return Color(1.0, 0.9, 0.3)      # Jaune
	elif lower.find("capture") >= 0:
		return Color(0.3, 0.9, 0.4)      # Vert
	else:
		return Color(1.0, 0.75, 0.2)     # Or par défaut

func _color_name(c: GameEnums.PlayerColor) -> String:
	match c:
		GameEnums.PlayerColor.GREEN: return "Vert"
		GameEnums.PlayerColor.BLUE: return "Bleu"
		GameEnums.PlayerColor.YELLOW: return "Jaune"
		GameEnums.PlayerColor.RED: return "Rouge"
		_: return "?"
