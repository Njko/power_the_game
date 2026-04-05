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

	var anim: Dictionary = _animation_queue.pop_front()
	match anim["type"]:
		"move":
			_animate_move(anim)
		"rebond":
			_animate_rebond(anim)
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

	var duration: float = MOVE_DURATION / speed_multiplier
	var tween := create_tween()
	_active_tweens.append(tween)
	tween.tween_property(token, "position", to_pos, duration) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(func():
		token.queue_free()
		_active_tweens.erase(tween)
		_play_next()
	)

func _animate_rebond(anim: Dictionary) -> void:
	if board_renderer == null:
		_play_next()
		return

	var from_pos: Vector2 = board_renderer.get_sector_position(anim["from"])
	var to_pos: Vector2 = board_renderer.get_sector_position(anim["to"])
	var color: Color = GameEnums.get_player_color(anim["owner"])
	var abbr: String = GameEnums.get_unit_abbreviation(anim["unit_type"])

	var token: Node2D = _create_unit_token(abbr, color, from_pos)

	# Aller vers la destination puis rebondir en arrière
	var duration: float = MOVE_DURATION * 0.5 / speed_multiplier
	var tween := create_tween()
	_active_tweens.append(tween)

	var mid_pos: Vector2 = from_pos.lerp(to_pos, 0.3)
	tween.tween_property(token, "position", mid_pos, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(token, "position", to_pos, duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func():
		token.queue_free()
		_active_tweens.erase(tween)
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
	label.position = Vector2(640, 300)
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
	var label := Label.new()
	label.text = anim["text"]
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(640, 320)
	label.modulate.a = 0
	_screen_overlay.add_child(label)

	var duration := PHASE_TRANSITION_DURATION / speed_multiplier
	var tween := create_tween()
	_active_tweens.append(tween)

	tween.tween_property(label, "modulate:a", 1.0, duration * 0.3)
	tween.tween_property(label, "position:y", 300, duration * 0.3) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_interval(duration * 0.4)
	tween.tween_property(label, "modulate:a", 0.0, duration * 0.3)
	tween.tween_callback(func():
		label.queue_free()
		_active_tweens.erase(tween)
		_play_next()
	)

# ===== CRÉATION D'ÉLÉMENTS VISUELS =====

func _create_unit_token(abbr: String, color: Color, pos: Vector2) -> Node2D:
	var token := Node2D.new()
	token.position = pos
	token.z_index = 15
	_world_overlay.add_child(token)

	# Fond arrondi
	var bg := ColorRect.new()
	bg.color = color.darkened(0.2)
	bg.size = Vector2(30, 20)
	bg.position = Vector2(-15, -10)
	token.add_child(bg)

	# Texte
	var label := Label.new()
	label.text = abbr
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.position = Vector2(-12, -9)
	token.add_child(label)

	# Ombre portée subtile
	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.3)
	shadow.size = Vector2(30, 20)
	shadow.position = Vector2(-13, -8)
	shadow.z_index = -1
	token.add_child(shadow)

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

	# Croix de combat
	var cross := Label.new()
	cross.text = "⚔"
	cross.add_theme_font_size_override("font_size", 24)
	cross.position = Vector2(-12, -16)
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
	core.size = Vector2(20, 20)
	core.position = Vector2(-10, -10)
	explosion.add_child(core)

	# Symbole
	var symbol := Label.new()
	symbol.text = "💥"
	symbol.add_theme_font_size_override("font_size", 20)
	symbol.position = Vector2(-12, -14)
	explosion.add_child(symbol)

	return explosion

func _cleanup_overlay() -> void:
	for child in _world_overlay.get_children():
		child.queue_free()
	for child in _screen_overlay.get_children():
		child.queue_free()

func _color_name(c: GameEnums.PlayerColor) -> String:
	match c:
		GameEnums.PlayerColor.GREEN: return "Vert"
		GameEnums.PlayerColor.BLUE: return "Bleu"
		GameEnums.PlayerColor.YELLOW: return "Jaune"
		GameEnums.PlayerColor.RED: return "Rouge"
		_: return "?"
