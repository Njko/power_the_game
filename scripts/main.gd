extends Node

## Scène racine du jeu Power.
## Orchestre les composants: plateau, unités, game manager, UI, ordres.

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

var _switch_screen: PlayerSwitchScreen
var _game_started := false

func _ready() -> void:
	# Cacher les éléments de jeu pendant l'écran titre
	$Board3D.visible = false
	$UnitOverlay.visible = false
	$AnimOverlay.visible = false
	$GameUI.visible = false

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

	# En phase de planification, déléguer au panneau d'ordres
	if game_manager.game_state.current_phase == GameEnums.GamePhase.PLANNING:
		if order_panel.visible and not _switch_screen.visible:
			order_panel.handle_sector_click(sector_id)
		return

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
	match phase:
		GameEnums.GamePhase.PLANNING:
			phase_label.text = "Préparation des ordres"
			resolution_panel.visible = false
		GameEnums.GamePhase.EXECUTION:
			phase_label.text = "Exécution des ordres"
			order_panel.deactivate()
			# Ouvrir le log de résolution et le vider
			resolution_log.clear()
			resolution_panel.visible = true
			_log_header("Exécution des ordres - Manche %d" % game_manager.game_state.current_round)
		GameEnums.GamePhase.CONFLICT:
			phase_label.text = "Résolution des conflits"
			_log_header("Résolution des conflits")
		GameEnums.GamePhase.COLLECT_POWER:
			phase_label.text = "Collecte des Power"
			_log_header("Collecte des Power")
		GameEnums.GamePhase.CAPTURE_FLAGS:
			phase_label.text = "Capture des drapeaux"
		GameEnums.GamePhase.GAME_OVER:
			phase_label.text = "FIN DE PARTIE"
			_log_header("FIN DE PARTIE")

func _on_round_started(round_number: int) -> void:
	round_label.text = "Manche %d" % round_number

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
	phase_label.text = "FIN DE PARTIE"

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
