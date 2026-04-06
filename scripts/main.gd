extends Node

## Scène racine du jeu Power.
## Orchestre les composants: plateau, unités, game manager, UI, ordres.

# ===== CLASSE INTERNE: PhaseTimeline =====

class PhaseTimeline extends Control:
	## Widget visuel affichant la progression des phases du tour.

	const TIMELINE_GOLD := Color(1.0, 0.75, 0.2)
	const TIMELINE_GRAY := Color(0.4, 0.4, 0.5)
	const TIMELINE_BG_LINE := Color(0.25, 0.25, 0.35)
	const PHASE_NAMES: Array[String] = ["Plan", "Ordres", "Combat", "Power", "Flags"]
	const POINT_RADIUS := 5.0
	const CURRENT_RADIUS := 7.0

	var _phase_index: int = -1

	func _init() -> void:
		custom_minimum_size = Vector2(350, 38)

	func set_phase(index: int) -> void:
		_phase_index = index
		queue_redraw()

	func _draw() -> void:
		var nb_phases: int = PHASE_NAMES.size()
		var marge_x := 30.0
		var largeur_utile: float = size.x - marge_x * 2.0
		var espacement: float = largeur_utile / float(nb_phases - 1)
		var centre_y := size.y * 0.35

		# Dessiner les segments de ligne entre les points
		for i in range(nb_phases - 1):
			var x_debut: float = marge_x + espacement * float(i)
			var x_fin: float = marge_x + espacement * float(i + 1)
			var couleur_ligne: Color
			if _phase_index >= 0 and i < _phase_index:
				couleur_ligne = TIMELINE_GOLD
			else:
				couleur_ligne = TIMELINE_BG_LINE
			draw_line(Vector2(x_debut, centre_y), Vector2(x_fin, centre_y), couleur_ligne, 2.0)

		# Dessiner les points et les labels
		var font: Font = ThemeDB.fallback_font
		var taille_police := 10
		for i in range(nb_phases):
			var x: float = marge_x + espacement * float(i)
			var pos := Vector2(x, centre_y)

			if _phase_index >= 0 and i < _phase_index:
				# Phase passée: cercle plein doré
				draw_circle(pos, POINT_RADIUS, TIMELINE_GOLD)
			elif _phase_index >= 0 and i == _phase_index:
				# Phase courante: cercle plus grand avec halo
				draw_circle(pos, CURRENT_RADIUS + 3.0, Color(TIMELINE_GOLD, 0.15))
				draw_circle(pos, CURRENT_RADIUS, TIMELINE_GOLD)
			else:
				# Phase future: cercle creux gris
				draw_arc(pos, POINT_RADIUS, 0, TAU, 32, TIMELINE_GRAY, 1.5)

			# Label sous le point
			var couleur_texte: Color
			if _phase_index >= 0 and i <= _phase_index:
				couleur_texte = TIMELINE_GOLD
			else:
				couleur_texte = TIMELINE_GRAY
			var nom: String = PHASE_NAMES[i]
			var taille_texte: Vector2 = font.get_string_size(nom, HORIZONTAL_ALIGNMENT_CENTER, -1, taille_police)
			var pos_texte := Vector2(x - taille_texte.x * 0.5, centre_y + CURRENT_RADIUS + 4.0 + taille_texte.y * 0.7)
			draw_string(font, pos_texte, nom, HORIZONTAL_ALIGNMENT_LEFT, -1, taille_police, couleur_texte)

# ===== FIN CLASSE INTERNE =====

@onready var board_3d = $Board3D  # Board3D
@onready var unit_renderer: UnitRenderer = $UnitOverlay/UnitRenderer
@onready var game_manager: Node = $GameManager
@onready var order_panel: OrderPanel = $GameUI/OrderPanel
@onready var anim_manager: AnimationManager = $AnimOverlay/AnimationManager
@onready var camera_controller = $Board3D/CameraController  # CameraController

var board_renderer: BoardRenderer

# UI
@onready var phase_label: Label = $GameUI/TopBar/HBox/PhaseLabel
@onready var game_timer_label: Label = $GameUI/TopBar/HBox/GameTimerLabel
@onready var round_label: Label = $GameUI/TopBar/HBox/RoundLabel
@onready var info_label: Label = $GameUI/BottomBar/VBox/InfoLabel
@onready var sector_info: Label = $GameUI/BottomBar/VBox/SectorInfo
@onready var resolution_panel: PanelContainer = $GameUI/ResolutionPanel
@onready var resolution_log: RichTextLabel = $GameUI/ResolutionPanel/VBox/ResolutionLog

const UnitInfoPanelClass = preload("res://scripts/ui/unit_info_panel.gd")

var _switch_screen: PlayerSwitchScreen
var _game_started := false
var _phase_timeline: PhaseTimeline
var _unit_info_panel

func _ready() -> void:
	# Cacher les éléments de jeu pendant l'écran titre
	$Board3D.visible = false
	$UnitOverlay.visible = false
	$AnimOverlay.visible = false
	$GameUI.visible = false

	# Remplacer PhaseLabel par le widget PhaseTimeline
	phase_label.visible = false
	_phase_timeline = PhaseTimeline.new()
	_phase_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hbox: HBoxContainer = phase_label.get_parent()
	var idx_label: int = phase_label.get_index()
	hbox.add_child(_phase_timeline)
	hbox.move_child(_phase_timeline, idx_label + 1)

	# Récupérer le board_renderer créé dynamiquement par Board3D
	board_renderer = board_3d.board_renderer

	# Connecter la caméra
	camera_controller.camera = board_3d.camera
	camera_controller._update_camera_position()

	# Afficher l'écran titre dans un CanvasLayer pour centrage correct
	var title_layer := CanvasLayer.new()
	title_layer.layer = 30
	title_layer.name = "TitleLayer"
	add_child(title_layer)
	var title := preload("res://scripts/ui/title_screen.gd").new()
	title.game_start_requested.connect(_on_game_start_requested)
	title_layer.add_child(title)

func _on_game_start_requested(num_players: int, human_color: GameEnums.PlayerColor, is_solo: bool) -> void:
	# Montrer les éléments de jeu
	$Board3D.visible = true
	$UnitOverlay.visible = true
	$AnimOverlay.visible = true
	$GameUI.visible = true

	# Connecter les signaux du plateau
	board_3d.sector_clicked.connect(_on_sector_clicked)
	board_3d.sector_clicked_with_pos.connect(_on_sector_clicked_with_pos)
	board_3d.sector_hovered.connect(_on_sector_hovered)

	# Connecter les signaux du game manager
	game_manager.phase_changed.connect(_on_phase_changed)
	game_manager.round_started.connect(_on_round_started)
	game_manager.planning_player_changed.connect(_on_planning_player_changed)
	game_manager.planning_timer_updated.connect(_on_planning_timer_updated)
	game_manager.combat_resolved.connect(_on_combat_resolved)
	game_manager.flag_captured.connect(_on_flag_captured)
	game_manager.game_over.connect(_on_game_over)
	game_manager.resolution_log.connect(_on_resolution_log)

	# Connecter le panneau d'ordres
	order_panel.orders_confirmed.connect(_on_orders_confirmed)

	# Créer l'écran de transition
	_switch_screen = PlayerSwitchScreen.new()
	_switch_screen.visible = false
	_switch_screen.player_ready.connect(_on_player_ready)
	$GameUI.add_child(_switch_screen)

	# Créer le panneau d'info unité
	_unit_info_panel = UnitInfoPanelClass.new()
	_unit_info_panel.visible = false
	_unit_info_panel.anchor_left = 0.0
	_unit_info_panel.anchor_right = 0.0
	_unit_info_panel.anchor_top = 0.0
	_unit_info_panel.anchor_bottom = 0.0
	_unit_info_panel.offset_left = 5
	_unit_info_panel.offset_top = 42
	_unit_info_panel.offset_right = 185
	_unit_info_panel.offset_bottom = 330
	$GameUI.add_child(_unit_info_panel)

	# Connecter l'animation manager au board_renderer
	if anim_manager:
		anim_manager.board_renderer = board_renderer

	board_3d.board_data = game_manager.game_state.board

	# Démarrer la partie
	if is_solo:
		game_manager.start_game(num_players, human_color)
	else:
		# Hotseat: pas d'IA, on passe NONE pour que personne ne soit IA
		# En fait, il faut modifier start_game pour supporter "tous humains"
		game_manager.start_game_hotseat(num_players)
	_game_started = true

	# Connecter l'état du jeu au panneau d'ordres
	order_panel.game_state = game_manager.game_state
	order_panel.board_renderer = board_renderer
	unit_renderer.board_3d = board_3d

func _on_sector_clicked(sector_id: String) -> void:
	var sector: Sector = game_manager.game_state.board.get_sector(sector_id)
	if sector:
		_show_sector_info(sector_id, sector)

func _on_sector_clicked_with_pos(sector_id: String, screen_pos: Vector2) -> void:
	# Chercher l'unité cliquée via le hit-test du unit_renderer
	var unite_cliquee: UnitData = unit_renderer.get_unit_at_screen_pos(screen_pos)

	# Mettre à jour le panneau d'info unité
	if unite_cliquee != null:
		_unit_info_panel.afficher_unite(unite_cliquee)
	else:
		_unit_info_panel.cacher()

	# Mettre à jour la sélection visuelle sur le renderer
	unit_renderer.selected_unit = unite_cliquee
	unit_renderer.queue_redraw()

	# En phase de planification, déléguer au panneau d'ordres avec l'unité ciblée
	if game_manager.game_state.current_phase == GameEnums.GamePhase.PLANNING:
		if order_panel.visible and not _switch_screen.visible:
			order_panel.handle_sector_click_with_unit(sector_id, unite_cliquee)

func _on_sector_hovered(sector_id: String) -> void:
	var sector: Sector = game_manager.game_state.board.get_sector(sector_id)
	if sector:
		_show_sector_info(sector_id, sector)

func _show_sector_info(sector_id: String, sector: Sector) -> void:
	var info := "%s" % sector.display_name
	match sector.sector_type:
		GameEnums.SectorType.LAND: info += " (Terrestre)"
		GameEnums.SectorType.COASTAL: info += " (Côtier)"
		GameEnums.SectorType.SEA: info += " (Maritime)"
		GameEnums.SectorType.ISLAND: info += " (Île)"
		GameEnums.SectorType.HQ: info += " (QG)"

	if sector.owner_territory != GameEnums.PlayerColor.NONE:
		info += " - %s" % _color_name(sector.owner_territory)

	if not sector.units.is_empty():
		info += "  |  "
		var parts := []
		for unit in sector.units:
			parts.append("%s [%s]" % [unit.get_display_name(), _color_name(unit.owner)])
		info += ", ".join(parts)

	sector_info.text = info

# ===== GAME MANAGER CALLBACKS =====

func _on_phase_changed(phase: GameEnums.GamePhase) -> void:
	# Cacher le panneau d'info unité et reset la sélection
	_unit_info_panel.cacher()
	unit_renderer.selected_unit = null

	# Mettre à jour la timeline visuelle
	var timeline_index: int = -1
	match phase:
		GameEnums.GamePhase.PLANNING:
			timeline_index = 0
			resolution_panel.visible = false
		GameEnums.GamePhase.EXECUTION:
			timeline_index = 1
			order_panel.deactivate()
			# Ouvrir le log de résolution et le vider
			resolution_log.clear()
			resolution_panel.visible = true
			_log_header("Exécution des ordres - Tour %d" % game_manager.game_state.current_round)
		GameEnums.GamePhase.CONFLICT:
			timeline_index = 2
			_log_header("Résolution des conflits")
		GameEnums.GamePhase.COLLECT_POWER:
			timeline_index = 3
			_log_header("Collecte des Power")
		GameEnums.GamePhase.CAPTURE_FLAGS:
			timeline_index = 4
		GameEnums.GamePhase.GAME_OVER:
			timeline_index = 4
			_log_header("FIN DE PARTIE")
	_phase_timeline.set_phase(timeline_index)

func _on_round_started(round_number: int) -> void:
	round_label.text = "Tour %d" % round_number

func _on_planning_player_changed(color: GameEnums.PlayerColor) -> void:
	# Ne pas afficher les UI pour les joueurs IA
	if game_manager.is_ai(color):
		return

	# En solo, pas besoin d'écran de transition (un seul joueur humain)
	if game_manager.human_player != GameEnums.PlayerColor.NONE:
		# Mode solo: passer directement à la saisie des ordres
		order_panel.game_state = game_manager.game_state
		order_panel.activate(color)
		game_manager.on_player_ready()
	else:
		# Mode hotseat: écran de transition entre joueurs
		_unit_info_panel.cacher()
		unit_renderer.selected_unit = null
		_switch_screen.show_for_player(color)
		order_panel.game_state = game_manager.game_state
		order_panel.activate(color)

func _on_player_ready() -> void:
	game_manager.on_player_ready()

func _on_planning_timer_updated(seconds: float) -> void:
	order_panel.update_timer(seconds)

func _on_orders_confirmed(_color: GameEnums.PlayerColor) -> void:
	order_panel.deactivate()
	game_manager.submit_current_player_orders()

func _on_combat_resolved(sector_id: String, winner: GameEnums.PlayerColor) -> void:
	info_label.text = "Combat en %s: victoire %s!" % [sector_id, _color_name(winner)]

func _on_flag_captured(capturer: GameEnums.PlayerColor, captured: GameEnums.PlayerColor) -> void:
	var msg := "%s capture le drapeau de %s!" % [_color_name(capturer), _color_name(captured)]
	info_label.text = msg

func _on_game_over(winner: GameEnums.PlayerColor) -> void:
	var msg := "VICTOIRE DE %s!" % _color_name(winner)
	info_label.text = msg
	_phase_timeline.set_phase(4)

	# Afficher le score final dans le log
	_log_header("VICTOIRE DE %s" % _color_name(winner))
	if resolution_log and game_manager.game_state:
		for color in game_manager.game_state.get_active_players():
			var total: int = game_manager.game_state.calculate_player_total_power(color)
			var flags: int = game_manager.game_state.get_player(color).flags_captured.size()
			resolution_log.append_text("  %s: puissance %d, %d drapeau(x)\n" % [
				_color_name(color), total, flags])

func _on_resolution_log(message: String) -> void:
	print("[Power] %s" % message)
	if resolution_log == null:
		return

	# Coloriser le message selon son contenu
	var colored := _colorize_log(message)
	resolution_log.append_text(colored + "\n")

func _log_header(text: String) -> void:
	if resolution_log == null:
		return
	resolution_log.append_text("\n[b][color=#FFD700]═══ %s ═══[/color][/b]\n" % text)

func _colorize_log(message: String) -> String:
	# Ordres exécutés avec succès
	if message.begins_with("  OK:"):
		return "[color=#88CC88]%s[/color]" % message

	# Ordres illégaux
	if message.begins_with("  ILLÉGAL:"):
		return "[color=#CC6666]%s[/color]" % message

	# Pénalité
	if "Pénalité" in message or "pénalité" in message:
		return "[color=#CC6666]%s[/color]" % message

	# Combat gagné
	if "gagne" in message and "Combat" in message:
		return "[color=#66CCFF]⚔ %s[/color]" % message

	# Égalité / rebond
	if "Égalité" in message or "Rebond" in message or "rebond" in message:
		return "[color=#CCCC66]↩ %s[/color]" % message

	# Power gagné
	if "Power" in message and "gagne" in message:
		return "[color=#FFCC00]★ %s[/color]" % message

	# Drapeau capturé
	if "DRAPEAU" in message or "drapeau" in message:
		return "[color=#FF6600][b]⚑ %s[/b][/color]" % message

	# IA
	if message.begins_with("IA "):
		return "[color=#AAAAAA]%s[/color]" % message

	# Temps écoulé
	if "Temps écoulé" in message:
		return "[color=#FF8888]%s[/color]" % message

	# En-têtes de joueur (--- Ordres de X ---)
	if message.begins_with("---"):
		# Extraire la couleur du joueur
		var player_color := _extract_player_color_from_log(message)
		if player_color != "":
			return "[b][color=%s]%s[/color][/b]" % [player_color, message]

	return message

func _extract_player_color_from_log(message: String) -> String:
	if "Vert" in message:
		return "#66CC66"
	if "Bleu" in message:
		return "#6688DD"
	if "Jaune" in message:
		return "#DDDD66"
	if "Rouge" in message:
		return "#DD6666"
	return ""

func _process(_delta: float) -> void:
	if not _game_started:
		return
	# Mettre à jour le timer global
	if game_manager.game_state.current_phase != GameEnums.GamePhase.SETUP \
			and game_manager.game_state.current_phase != GameEnums.GamePhase.GAME_OVER:
		var elapsed: float = game_manager.game_timer
		var remaining: float = game_manager.game_state.game_duration_limit - elapsed
		if remaining < 0:
			remaining = 0
		var hours := int(remaining) / 3600
		var minutes := (int(remaining) % 3600) / 60
		var seconds := int(remaining) % 60
		game_timer_label.text = "%d:%02d:%02d" % [hours, minutes, seconds]

func _unhandled_input(event: InputEvent) -> void:
	# Espace pour skip les animations
	if event.is_action_pressed("ui_accept") and anim_manager and anim_manager.is_playing():
		anim_manager.skip_all()

func _color_name(color: GameEnums.PlayerColor) -> String:
	match color:
		GameEnums.PlayerColor.GREEN: return "Vert"
		GameEnums.PlayerColor.BLUE: return "Bleu"
		GameEnums.PlayerColor.YELLOW: return "Jaune"
		GameEnums.PlayerColor.RED: return "Rouge"
		GameEnums.PlayerColor.MERCENARY: return "Mercenaire"
		_: return "?"
