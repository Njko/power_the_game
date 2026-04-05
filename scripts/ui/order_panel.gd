extends PanelContainer
class_name OrderPanel

## Panneau de programmation des ordres pour un joueur.
## En mode hotseat, chaque joueur programme ses ordres à tour de rôle.
## Workflow: clic sur unité (sélection) → clic sur destination → ordre ajouté.

signal orders_confirmed(player_color: GameEnums.PlayerColor)

const MAX_ORDERS := 5

var game_state: GameState
var board_renderer: BoardRenderer
var current_player: GameEnums.PlayerColor = GameEnums.PlayerColor.GREEN
var pending_orders: Array[Order] = []
var _selected_unit: UnitData = null
var _selected_from_sector: String = ""
var _is_exchange_mode: bool = false
var _is_missile_create_mode: bool = false
var _missile_create_sector: String = ""
var _missile_selected_units: Dictionary = {}  # UnitType -> count
var _missile_available_units: Dictionary = {}  # UnitType -> max available count
var _missile_total_power: int = 0
var _pending_missile_sectors: Array[String] = []  # Secteurs où des missiles seront créés ce tour

# Noeuds UI créés dynamiquement
var _title_label: Label
var _timer_label: Label
var _order_list: VBoxContainer
var _instruction_label: Label
var _confirm_button: Button
var _exchange_button: Button
var _cancel_button: Button
var _reserve_button: Button
var _reserve_display: Label

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	# Titre joueur
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_title_label)

	# Timer
	_timer_label = Label.new()
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 24)
	_timer_label.text = "3:00"
	vbox.add_child(_timer_label)

	# Séparateur
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Instructions
	_instruction_label = Label.new()
	_instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_instruction_label.text = "Cliquez sur une unité pour la sélectionner"
	_instruction_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_instruction_label)

	# Liste des ordres
	var orders_title := Label.new()
	orders_title.text = "Ordres (0/5):"
	orders_title.name = "OrdersTitle"
	vbox.add_child(orders_title)

	_order_list = VBoxContainer.new()
	_order_list.add_theme_constant_override("separation", 2)
	vbox.add_child(_order_list)

	# Boutons
	var btn_box := VBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 4)
	vbox.add_child(btn_box)

	_exchange_button = Button.new()
	_exchange_button.text = "Mode Échange"
	_exchange_button.pressed.connect(_on_exchange_pressed)
	btn_box.add_child(_exchange_button)

	var _missile_button := Button.new()
	_missile_button.text = "Créer Méga-Missile"
	_missile_button.name = "MissileButton"
	_missile_button.pressed.connect(_on_missile_create_pressed)
	btn_box.add_child(_missile_button)

	_reserve_button = Button.new()
	_reserve_button.text = "Depuis la Réserve"
	_reserve_button.pressed.connect(_on_reserve_pressed)
	btn_box.add_child(_reserve_button)

	_cancel_button = Button.new()
	_cancel_button.text = "Annuler dernier ordre"
	_cancel_button.pressed.connect(_on_cancel_pressed)
	btn_box.add_child(_cancel_button)

	var sep2 := HSeparator.new()
	btn_box.add_child(sep2)

	_confirm_button = Button.new()
	_confirm_button.text = "Valider mes ordres"
	_confirm_button.add_theme_font_size_override("font_size", 16)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	btn_box.add_child(_confirm_button)

	# Séparateur avant réserve
	var sep3 := HSeparator.new()
	vbox.add_child(sep3)

	# Affichage de la réserve
	var reserve_title := Label.new()
	reserve_title.text = "Réserve:"
	reserve_title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(reserve_title)

	_reserve_display = Label.new()
	_reserve_display.autowrap_mode = TextServer.AUTOWRAP_WORD
	_reserve_display.add_theme_font_size_override("font_size", 11)
	_reserve_display.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
	vbox.add_child(_reserve_display)

func activate(player_color: GameEnums.PlayerColor) -> void:
	current_player = player_color
	pending_orders.clear()
	_selected_unit = null
	_selected_from_sector = ""
	_is_exchange_mode = false
	_is_missile_create_mode = false
	_missile_create_sector = ""
	_missile_selected_units.clear()
	_missile_available_units.clear()
	_missile_total_power = 0
	_pending_missile_sectors.clear()
	visible = true

	var color_name := _get_color_name(player_color)
	_title_label.text = "Joueur %s" % color_name
	_title_label.add_theme_color_override("font_color", GameEnums.get_player_color(player_color))
	_instruction_label.text = "Cliquez sur une de vos unités pour la sélectionner"
	_refresh_order_list()
	_refresh_reserve_display()

func deactivate() -> void:
	visible = false
	_selected_unit = null
	_selected_from_sector = ""
	if board_renderer:
		board_renderer.clear_highlights()

func update_timer(seconds: float) -> void:
	var minutes := int(seconds) / 60
	var secs := int(seconds) % 60
	_timer_label.text = "%d:%02d" % [minutes, secs]

	# Rouge si < 30 secondes
	if seconds < 30:
		_timer_label.add_theme_color_override("font_color", Color.RED)
	else:
		_timer_label.remove_theme_color_override("font_color")

# ===== GESTION DES CLICS SUR LE PLATEAU =====

func handle_sector_click(sector_id: String) -> void:
	if game_state == null:
		return

	if _is_missile_create_mode:
		_handle_missile_create_click(sector_id)
		return

	if _is_exchange_mode:
		_handle_exchange_click(sector_id)
		return

	if _selected_unit == null:
		# Étape 1: sélectionner une unité
		_try_select_unit(sector_id)
	else:
		# Étape 2: choisir la destination
		_try_set_destination(sector_id)

func _try_select_unit(sector_id: String) -> void:
	var sector := game_state.board.get_sector(sector_id)
	if sector == null:
		return

	# Chercher une unité du joueur actuel qui n'a pas encore d'ordre ce tour
	var available_units := []
	for unit in sector.units:
		if unit.owner == current_player and unit.unit_type != GameEnums.UnitType.FLAG:
			if unit.get_max_move() > 0 or unit.unit_type == GameEnums.UnitType.MEGA_MISSILE:
				available_units.append(unit)

	# Ajouter les missiles en attente de création (pas encore sur le plateau)
	if sector_id in _pending_missile_sectors:
		var virtual_missile := UnitData.new(GameEnums.UnitType.MEGA_MISSILE, current_player, sector_id)
		available_units.append(virtual_missile)

	if available_units.is_empty():
		_instruction_label.text = "Pas d'unité déplaçable ici. Sélectionnez une de vos unités."
		return

	# Si plusieurs unités, prendre la première non-encore-ordonnée
	var unit_to_select: UnitData = null
	for unit in available_units:
		if not _has_pending_order_for(unit, sector_id):
			unit_to_select = unit
			break

	if unit_to_select == null:
		unit_to_select = available_units[0]

	_selected_unit = unit_to_select
	_selected_from_sector = sector_id

	# Afficher les destinations possibles
	if _selected_unit.unit_type == GameEnums.UnitType.MEGA_MISSILE:
		# Méga-Missile: portée illimitée, tous les secteurs du plateau
		var all_sectors: Array[String] = []
		for sid in game_state.board.sectors:
			if sid != sector_id:
				all_sectors.append(sid)
		if board_renderer:
			board_renderer.highlight_sectors(all_sectors)
			board_renderer.selected_sector = sector_id
			board_renderer.queue_redraw()
		_instruction_label.text = "Méga-Missile sélectionné en %s\nCliquez sur le secteur cible (portée illimitée)" % sector_id
	else:
		var max_move: int = _selected_unit.get_max_move()
		var reachable := game_state.board.get_reachable_sectors(sector_id, _selected_unit.unit_type, max_move)
		var typed: Array[String] = []
		for s in reachable:
			typed.append(s)
		if board_renderer:
			board_renderer.highlight_sectors(typed)
			board_renderer.selected_sector = sector_id
			board_renderer.queue_redraw()

		_instruction_label.text = "%s sélectionné(e) en %s\nCliquez sur la destination (max %d cases)" % [
			_selected_unit.get_display_name(), sector_id, max_move
		]

func _try_set_destination(sector_id: String) -> void:
	if pending_orders.size() >= MAX_ORDERS:
		_instruction_label.text = "Maximum 5 ordres atteint!"
		_deselect()
		return

	# Clic sur le même secteur = désélection
	if sector_id == _selected_from_sector:
		_deselect()
		return

	var to_sector := game_state.board.get_sector(sector_id)
	if to_sector == null:
		return

	# Méga-Missile: créer un ordre LAUNCH (pas de restriction terrain/distance)
	if _selected_unit.unit_type == GameEnums.UnitType.MEGA_MISSILE:
		var order := Order.create_launch(current_player, _selected_from_sector, sector_id)
		pending_orders.append(order)
		_instruction_label.text = "Lancement Méga-Missile: %s → %s" % [_selected_from_sector, sector_id]
		_deselect()
		_refresh_order_list()
		return

	# Vérifier l'accessibilité
	if not to_sector.is_accessible_by(_selected_unit.unit_type):
		_instruction_label.text = "Cette unité ne peut pas aller sur ce type de terrain!"
		return

	# Vérifier la distance
	var max_move: int = _selected_unit.get_max_move()
	var distance := game_state.board.get_distance(_selected_from_sector, sector_id, _selected_unit.unit_type)
	if distance < 0 or distance > max_move:
		_instruction_label.text = "Trop loin! (distance: %d, max: %d)" % [distance, max_move]
		return

	# Créer l'ordre de déplacement
	var order := Order.create_move(current_player, _selected_unit.unit_type, _selected_from_sector, sector_id)
	pending_orders.append(order)

	_instruction_label.text = "Ordre ajouté: %s" % order.get_description()
	_deselect()
	_refresh_order_list()

func _handle_exchange_click(sector_id: String) -> void:
	var sector := game_state.board.get_sector(sector_id)
	if sector == null:
		return

	if pending_orders.size() >= MAX_ORDERS:
		_instruction_label.text = "Maximum 5 ordres atteint!"
		_is_exchange_mode = false
		return

	# Chercher 3 unités du même type (groupe 1) sur ce secteur
	var units_by_type: Dictionary = {}
	for unit in sector.units:
		if unit.owner == current_player:
			var group := GameEnums.get_unit_group(unit.unit_type)
			if group == 1:
				if unit.unit_type not in units_by_type:
					units_by_type[unit.unit_type] = 0
				units_by_type[unit.unit_type] += 1

	# Trouver un type avec au moins 3 unités
	var exchange_type: GameEnums.UnitType = GameEnums.UnitType.POWER
	var found := false
	for unit_type in units_by_type:
		if units_by_type[unit_type] >= 3:
			exchange_type = unit_type
			found = true
			break

	if not found:
		# Vérifier aussi les échanges Power -> unité
		var power_count := 0
		for unit in sector.units:
			if unit.owner == current_player and unit.unit_type == GameEnums.UnitType.POWER:
				power_count += 1

		# Vérifier en réserve aussi
		if game_state.get_player(current_player):
			power_count += game_state.get_player(current_player).get_reserve_power_count()

		if power_count >= 2:
			_instruction_label.text = "Échange Power disponible. (fonctionnalité à venir)"
		else:
			_instruction_label.text = "Pas assez d'unités identiques (3 requises) pour un échange ici."
		_is_exchange_mode = false
		return

	# Créer l'ordre d'échange
	var result_type := GameEnums.get_upgrade_type(exchange_type)
	var order := Order.create_exchange(current_player, [], result_type, sector_id)
	order.unit_type = exchange_type  # Stocker le type source
	pending_orders.append(order)

	_instruction_label.text = "Échange: 3x %s → 1x %s en %s" % [
		GameEnums.get_unit_name(exchange_type),
		GameEnums.get_unit_name(result_type),
		sector_id
	]
	_is_exchange_mode = false
	_refresh_order_list()

func _has_pending_order_for(unit: UnitData, sector_id: String) -> bool:
	for order in pending_orders:
		if order.order_type == GameEnums.OrderType.MOVE:
			if order.unit_type == unit.unit_type and order.from_sector == sector_id:
				return true
	return false

func _deselect() -> void:
	_selected_unit = null
	_selected_from_sector = ""
	if board_renderer:
		board_renderer.clear_highlights()

func _refresh_order_list() -> void:
	# Nettoyer la liste
	for child in _order_list.get_children():
		child.queue_free()

	# Afficher les ordres
	for i in range(pending_orders.size()):
		var order: Order = pending_orders[i]
		var hbox := HBoxContainer.new()

		var label := Label.new()
		label.text = "%d. %s" % [i + 1, order.get_description()]
		label.add_theme_font_size_override("font_size", 12)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(label)

		var del_btn := Button.new()
		del_btn.text = "X"
		del_btn.custom_minimum_size = Vector2(24, 24)
		del_btn.pressed.connect(_on_delete_order.bind(i))
		hbox.add_child(del_btn)

		_order_list.add_child(hbox)

	# Slots vides
	for i in range(pending_orders.size(), MAX_ORDERS):
		var label := Label.new()
		label.text = "%d. ---" % [i + 1]
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_order_list.add_child(label)

	# Mettre à jour le titre des ordres
	var orders_title := get_node_or_null("VBoxContainer/OrdersTitle")
	if orders_title == null:
		# Chercher dans les enfants du vbox
		for child in get_child(0).get_children():
			if child.name == "OrdersTitle":
				orders_title = child
				break
	if orders_title:
		orders_title.text = "Ordres (%d/%d):" % [pending_orders.size(), MAX_ORDERS]

# ===== CALLBACKS BOUTONS =====

func _refresh_reserve_display() -> void:
	if game_state == null or _reserve_display == null:
		return
	var player := game_state.get_player(current_player)
	if player == null:
		_reserve_display.text = "(vide)"
		return

	if player.reserve.is_empty():
		_reserve_display.text = "(vide)"
		return

	# Compter par type
	var counts: Dictionary = {}
	for unit in player.reserve:
		var name := GameEnums.get_unit_name(unit.unit_type)
		if name not in counts:
			counts[name] = 0
		counts[name] += 1

	var parts := []
	for unit_name in counts:
		parts.append("%dx %s" % [counts[unit_name], unit_name])
	_reserve_display.text = ", ".join(parts)

func _on_confirm_pressed() -> void:
	# Transférer les ordres au joueur
	if game_state:
		var player := game_state.get_player(current_player)
		if player:
			player.clear_orders()
			for order in pending_orders:
				player.add_order(order)
	orders_confirmed.emit(current_player)

func _on_cancel_pressed() -> void:
	if pending_orders.size() > 0:
		pending_orders.pop_back()
		_refresh_order_list()
		_instruction_label.text = "Dernier ordre annulé."

func _on_delete_order(index: int) -> void:
	if index >= 0 and index < pending_orders.size():
		pending_orders.remove_at(index)
		_refresh_order_list()

func _on_exchange_pressed() -> void:
	_is_exchange_mode = true
	_deselect()
	_instruction_label.text = "Mode échange: cliquez sur un secteur avec 3+ unités identiques"

func _on_reserve_pressed() -> void:
	if game_state == null:
		return
	var player := game_state.get_player(current_player)
	if player == null or player.reserve.is_empty():
		_instruction_label.text = "Réserve vide!"
		return

	if pending_orders.size() >= MAX_ORDERS:
		_instruction_label.text = "Maximum 5 ordres atteint!"
		return

	# Trouver la première unité déplaçable en réserve
	var unit_to_deploy: UnitData = null
	for unit in player.reserve:
		if unit.unit_type != GameEnums.UnitType.POWER and unit.unit_type != GameEnums.UnitType.FLAG:
			unit_to_deploy = unit
			break

	if unit_to_deploy == null:
		# Essayer un échange Power -> unité
		var power_count := player.get_reserve_power_count()
		if power_count >= 2:
			_instruction_label.text = "Réserve: %d Power disponibles. Échange Power en cours..." % power_count
			# Créer un ordre d'échange Power -> Soldat (le moins cher)
			var order := Order.create_exchange(current_player, [], GameEnums.UnitType.SOLDIER, "RV")
			pending_orders.append(order)
			_refresh_order_list()
		else:
			_instruction_label.text = "Aucune unité déployable en réserve."
		return

	# Créer un ordre de déploiement (réserve -> QG)
	var hq_id := "HQ_" + game_state.board.get_territory_prefix(current_player)
	var order := Order.create_move(current_player, unit_to_deploy.unit_type, "RV", hq_id)
	pending_orders.append(order)
	_instruction_label.text = "Déploiement: %s → QG" % unit_to_deploy.get_display_name()
	_refresh_order_list()

func _on_missile_create_pressed() -> void:
	_is_missile_create_mode = true
	_is_exchange_mode = false
	_deselect()
	_missile_create_sector = ""
	_missile_selected_units.clear()
	_missile_available_units.clear()
	_missile_total_power = 0
	_instruction_label.text = "Création Méga-Missile: cliquez sur un secteur avec vos unités (100+ puissance requise)"

func _handle_missile_create_click(sector_id: String) -> void:
	if _missile_create_sector == "":
		# Étape 1: sélectionner le secteur de création
		var sector := game_state.board.get_sector(sector_id)
		if sector == null:
			return

		# Calculer les unités disponibles du joueur sur ce secteur
		_missile_available_units.clear()
		var max_possible_power := 0
		for unit in sector.units:
			if unit.owner == current_player and unit.unit_type != GameEnums.UnitType.FLAG and unit.unit_type != GameEnums.UnitType.MEGA_MISSILE:
				var ut: GameEnums.UnitType = unit.unit_type
				if ut not in _missile_available_units:
					_missile_available_units[ut] = 0
				_missile_available_units[ut] += 1
				max_possible_power += GameEnums.get_unit_power(ut)

		if max_possible_power < 100:
			_instruction_label.text = "Puissance insuffisante sur ce secteur (%d/100). Choisissez un autre secteur." % max_possible_power
			return

		_missile_create_sector = sector_id
		# Par défaut, sélectionner toutes les unités
		_missile_selected_units = _missile_available_units.duplicate()
		_missile_total_power = max_possible_power
		_update_missile_ui()
	else:
		# Clic ailleurs = annuler
		_cancel_missile_create()

func _update_missile_ui() -> void:
	## Met à jour l'instruction avec l'état de la sélection missile.
	var lines := "Création Méga-Missile en %s\n" % _missile_create_sector
	_missile_total_power = 0

	for ut in _missile_selected_units:
		var count: int = _missile_selected_units[ut]
		var power: int = GameEnums.get_unit_power(ut) * count
		_missile_total_power += power
		var max_count: int = _missile_available_units[ut]
		lines += "%s: %d/%d (puissance: %d)\n" % [
			GameEnums.get_unit_name(ut), count, max_count, power]

	lines += "Total: %d/100" % _missile_total_power

	if _missile_total_power >= 100:
		lines += " ✓ Cliquez Confirmer pour créer!"
	else:
		lines += " (ajoutez des unités avec +/-)"

	_instruction_label.text = lines
	_refresh_missile_selection_buttons()

func _refresh_missile_selection_buttons() -> void:
	## Affiche les boutons +/- pour chaque type d'unité dans la liste d'ordres.
	for child in _order_list.get_children():
		child.queue_free()

	for ut in _missile_available_units:
		var max_count: int = _missile_available_units[ut]
		var current_count: int = _missile_selected_units.get(ut, 0)

		var hbox := HBoxContainer.new()

		var label := Label.new()
		label.text = "%s: %d/%d" % [GameEnums.get_unit_name(ut), current_count, max_count]
		label.add_theme_font_size_override("font_size", 12)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(label)

		var minus_btn := Button.new()
		minus_btn.text = "-"
		minus_btn.custom_minimum_size = Vector2(24, 24)
		minus_btn.disabled = current_count <= 0
		minus_btn.pressed.connect(_on_missile_unit_change.bind(ut, -1))
		hbox.add_child(minus_btn)

		var plus_btn := Button.new()
		plus_btn.text = "+"
		plus_btn.custom_minimum_size = Vector2(24, 24)
		plus_btn.disabled = current_count >= max_count
		plus_btn.pressed.connect(_on_missile_unit_change.bind(ut, 1))
		hbox.add_child(plus_btn)

		_order_list.add_child(hbox)

	# Boutons confirmer / annuler
	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 4)

	var confirm := Button.new()
	confirm.text = "Confirmer (%d)" % _missile_total_power
	confirm.disabled = _missile_total_power < 100
	confirm.pressed.connect(_on_missile_create_confirm)
	btn_hbox.add_child(confirm)

	var cancel := Button.new()
	cancel.text = "Annuler"
	cancel.pressed.connect(_cancel_missile_create)
	btn_hbox.add_child(cancel)

	_order_list.add_child(btn_hbox)

func _on_missile_unit_change(ut: GameEnums.UnitType, delta: int) -> void:
	var current: int = _missile_selected_units.get(ut, 0)
	var max_count: int = _missile_available_units.get(ut, 0)
	var new_count: int = clampi(current + delta, 0, max_count)
	_missile_selected_units[ut] = new_count
	_update_missile_ui()

func _on_missile_create_confirm() -> void:
	if pending_orders.size() >= MAX_ORDERS:
		_instruction_label.text = "Maximum 5 ordres atteint!"
		_cancel_missile_create()
		return

	if _missile_total_power < 100:
		return

	# Construire la liste des unités sacrifiées
	var sacrificed: Array = []
	for ut in _missile_selected_units:
		var count: int = _missile_selected_units[ut]
		if count > 0:
			sacrificed.append({"type": ut, "count": count})

	var order := Order.create_missile_exchange(
		current_player, sacrificed, _missile_create_sector)
	pending_orders.append(order)
	_pending_missile_sectors.append(_missile_create_sector)

	_instruction_label.text = "Méga-Missile créé en %s! (puissance sacrifiée: %d)" % [
		_missile_create_sector, _missile_total_power]
	_cancel_missile_create()
	_refresh_order_list()

func _cancel_missile_create() -> void:
	_is_missile_create_mode = false
	_missile_create_sector = ""
	_missile_selected_units.clear()
	_missile_available_units.clear()
	_missile_total_power = 0
	_refresh_order_list()

func _get_color_name(color: GameEnums.PlayerColor) -> String:
	match color:
		GameEnums.PlayerColor.GREEN: return "Vert"
		GameEnums.PlayerColor.BLUE: return "Bleu"
		GameEnums.PlayerColor.YELLOW: return "Jaune"
		GameEnums.PlayerColor.RED: return "Rouge"
		_: return "?"
