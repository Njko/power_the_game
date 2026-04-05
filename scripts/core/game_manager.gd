extends Node

## Gestionnaire principal du jeu Power.
## Flux asynchrone: les animations sont jouées entre chaque phase.

signal phase_changed(phase: GameEnums.GamePhase)
signal round_started(round_number: int)
signal combat_resolved(sector_id: String, winner: GameEnums.PlayerColor)
signal flag_captured(capturer: GameEnums.PlayerColor, captured: GameEnums.PlayerColor)
signal player_eliminated(color: GameEnums.PlayerColor)
signal game_over(winner: GameEnums.PlayerColor)
signal planning_player_changed(color: GameEnums.PlayerColor)
signal planning_timer_updated(seconds_remaining: float)
signal resolution_log(message: String)

var game_state: GameState
var planning_timer: float = 0.0
var planning_duration: float = 180.0
var game_timer: float = 0.0
var is_planning_active: bool = false
var _planning_queue: Array[GameEnums.PlayerColor] = []
var _current_planning_color: GameEnums.PlayerColor = GameEnums.PlayerColor.NONE
var _waiting_for_player_switch: bool = false

var board_renderer: BoardRenderer
var unit_renderer: UnitRenderer
var anim_manager: AnimationManager

# IA
var ai_players: Dictionary = {}  # PlayerColor -> AIPlayer
var human_player: GameEnums.PlayerColor = GameEnums.PlayerColor.NONE

signal ai_orders_generated(color: GameEnums.PlayerColor)

func _ready() -> void:
	game_state = GameState.new()

func is_ai(color: GameEnums.PlayerColor) -> bool:
	return color in ai_players

func start_game(num_players: int = 4, p_human_color: GameEnums.PlayerColor = GameEnums.PlayerColor.GREEN) -> void:
	var board_3d_node = get_node_or_null("../Board3D")
	if board_3d_node:
		board_renderer = board_3d_node.board_renderer
	unit_renderer = get_node_or_null("../UnitOverlay/UnitRenderer") as UnitRenderer
	anim_manager = get_node_or_null("../AnimOverlay/AnimationManager") as AnimationManager

	if anim_manager and board_renderer:
		anim_manager.board_renderer = board_renderer

	game_state.setup_game(num_players)
	game_state.game_start_time = Time.get_unix_time_from_system()

	# Configurer l'IA: tous les joueurs sauf le joueur humain
	human_player = p_human_color
	ai_players.clear()
	for color in game_state.get_active_players():
		if color != human_player:
			ai_players[color] = AIPlayer.new(color, game_state)

	if board_renderer:
		board_renderer.board_data = game_state.board
	if unit_renderer:
		unit_renderer.board_renderer = board_renderer
		unit_renderer.game_state = game_state
		unit_renderer.update_display()
	_start_round()

func start_game_hotseat(num_players: int = 4) -> void:
	## Lance une partie sans IA (tous les joueurs sont humains).
	var board_3d_node = get_node_or_null("../Board3D")
	if board_3d_node:
		board_renderer = board_3d_node.board_renderer
	unit_renderer = get_node_or_null("../UnitOverlay/UnitRenderer") as UnitRenderer
	anim_manager = get_node_or_null("../AnimOverlay/AnimationManager") as AnimationManager

	if anim_manager and board_renderer:
		anim_manager.board_renderer = board_renderer

	game_state.setup_game(num_players)
	game_state.game_start_time = Time.get_unix_time_from_system()

	human_player = GameEnums.PlayerColor.NONE  # Pas de joueur IA
	ai_players.clear()

	if board_renderer:
		board_renderer.board_data = game_state.board
	if unit_renderer:
		unit_renderer.board_renderer = board_renderer
		unit_renderer.game_state = game_state
		unit_renderer.update_display()
	_start_round()

func _start_round() -> void:
	round_started.emit(game_state.current_round)
	_start_planning_phase()

func _process(delta: float) -> void:
	if is_planning_active and not _waiting_for_player_switch:
		planning_timer -= delta
		planning_timer_updated.emit(planning_timer)
		if planning_timer <= 0:
			_force_submit_current_player()

	if game_state and game_state.current_phase != GameEnums.GamePhase.SETUP \
			and game_state.current_phase != GameEnums.GamePhase.GAME_OVER:
		game_timer += delta

# =============================================
# PHASE 1: PRÉPARATION DES ORDRES (HOTSEAT)
# =============================================

func _start_planning_phase() -> void:
	game_state.current_phase = GameEnums.GamePhase.PLANNING
	phase_changed.emit(GameEnums.GamePhase.PLANNING)

	for color in game_state.get_active_players():
		game_state.get_player(color).clear_orders()

	for unit in game_state.all_units:
		unit.moved_this_turn = false
		unit.rebounded_this_turn = false

	var active := game_state.get_active_players()
	_planning_queue.clear()
	var start: int = game_state.arbiter_index % active.size()
	for i in range(active.size()):
		_planning_queue.append(active[(start + i) % active.size()])

	is_planning_active = true
	_advance_to_next_player()

func _advance_to_next_player() -> void:
	if _planning_queue.is_empty():
		_end_planning_phase()
		return

	_current_planning_color = _planning_queue.pop_front()

	if is_ai(_current_planning_color):
		# Joueur IA: générer les ordres automatiquement
		_generate_ai_orders(_current_planning_color)
		# Passer au joueur suivant immédiatement
		call_deferred("_advance_to_next_player")
		return

	# Joueur humain: afficher l'écran de transition et le panneau d'ordres
	planning_timer = planning_duration
	_waiting_for_player_switch = true
	planning_player_changed.emit(_current_planning_color)

func _generate_ai_orders(color: GameEnums.PlayerColor) -> void:
	var ai: AIPlayer = ai_players[color]
	var orders := ai.generate_orders()
	var player := game_state.get_player(color)
	player.clear_orders()
	for order in orders:
		player.add_order(order)
	resolution_log.emit("IA %s: %d ordres programmés" % [_color_name(color), orders.size()])
	ai_orders_generated.emit(color)

func on_player_ready() -> void:
	_waiting_for_player_switch = false

func submit_current_player_orders() -> void:
	_advance_to_next_player()

func _force_submit_current_player() -> void:
	resolution_log.emit("Temps écoulé pour %s!" % _color_name(_current_planning_color))
	submit_current_player_orders()

func _end_planning_phase() -> void:
	is_planning_active = false
	_current_planning_color = GameEnums.PlayerColor.NONE
	_run_resolution_phases()

func get_current_planning_player() -> GameEnums.PlayerColor:
	return _current_planning_color

# =============================================
# PHASES DE RÉSOLUTION (asynchrone avec animations)
# =============================================

func _run_resolution_phases() -> void:
	## Exécute les phases 2 à 6 séquentiellement avec animations entre chaque.
	await _phase_execution()
	await _phase_conflict()
	await _phase_collect_power()
	await _phase_capture_flags()

	# Tour suivant ou fin de partie
	if game_state.current_phase == GameEnums.GamePhase.GAME_OVER:
		return

	game_state.advance_arbiter()
	if game_timer >= game_state.game_duration_limit:
		_end_game_by_timeout()
		return

	game_state.current_round += 1
	_start_round()

# --- Phase 2: Exécution ---

func _phase_execution() -> void:
	game_state.current_phase = GameEnums.GamePhase.EXECUTION
	phase_changed.emit(GameEnums.GamePhase.EXECUTION)

	if anim_manager:
		anim_manager.play_phase_title("Exécution des ordres")
		anim_manager.play_all()
		await anim_manager.animation_finished

	for unit in game_state.all_units:
		if not unit.in_reserve and unit.sector_id != "":
			unit.set_meta("origin_sector", unit.sector_id)

	var active := game_state.get_active_players()
	var start_idx: int = game_state.arbiter_index % active.size()

	for i in range(active.size()):
		var player_idx: int = (start_idx + i) % active.size()
		var player_color: GameEnums.PlayerColor = active[player_idx]
		var player := game_state.get_player(player_color)
		resolution_log.emit("--- Ordres de %s ---" % _color_name(player_color))
		_execute_player_orders(player)

	# Jouer les animations de déplacement
	if anim_manager:
		anim_manager.play_all()
		await anim_manager.animation_finished

	if unit_renderer:
		unit_renderer.update_display()

func _execute_player_orders(player: PlayerData) -> void:
	var valid_count := 0
	for order in player.orders:
		if _validate_and_execute_order(order, player):
			valid_count += 1
			resolution_log.emit("  OK: %s" % order.get_description())
		else:
			resolution_log.emit("  ILLÉGAL: %s" % order.get_description())

	if valid_count == 0:
		_apply_inaction_penalty(player)
		resolution_log.emit("  Pénalité: aucun ordre valide!")

func _validate_and_execute_order(order: Order, player: PlayerData) -> bool:
	if order.order_type == GameEnums.OrderType.MOVE:
		return _execute_move_order(order, player)
	elif order.order_type == GameEnums.OrderType.LAUNCH:
		return _execute_launch_order(order, player)
	else:
		return _execute_exchange_order(order, player)

func _execute_move_order(order: Order, player: PlayerData) -> bool:
	if order.from_sector == "RV":
		return _execute_reserve_deploy(order, player)

	var from_sector := game_state.board.get_sector(order.from_sector)
	var to_sector := game_state.board.get_sector(order.to_sector)
	if from_sector == null or to_sector == null:
		return false

	var unit_to_move: UnitData = null
	for unit in from_sector.units:
		if unit.owner == player.color and unit.unit_type == order.unit_type and not unit.moved_this_turn:
			unit_to_move = unit
			break

	if unit_to_move == null:
		return false
	if not to_sector.is_accessible_by(order.unit_type):
		return false

	var max_move := GameEnums.get_unit_max_move(order.unit_type)
	var distance := game_state.board.get_distance(order.from_sector, order.to_sector, order.unit_type)
	if distance < 0 or distance > max_move:
		return false

	unit_to_move.set_meta("origin_sector", order.from_sector)
	game_state.move_unit(unit_to_move, order.to_sector)
	unit_to_move.moved_this_turn = true

	# Enregistrer l'animation
	if anim_manager:
		anim_manager.play_move(order.unit_type, player.color, order.from_sector, order.to_sector)

	return true

func _execute_reserve_deploy(order: Order, player: PlayerData) -> bool:
	var unit_to_deploy: UnitData = null
	for unit in player.reserve:
		if unit.unit_type == order.unit_type and not unit.moved_this_turn:
			unit_to_deploy = unit
			break

	if unit_to_deploy == null:
		return false

	var hq_id := "HQ_" + game_state.board.get_territory_prefix(player.color)
	if order.to_sector != hq_id:
		return false

	player.remove_from_reserve(unit_to_deploy)
	game_state.move_unit(unit_to_deploy, hq_id)
	unit_to_deploy.moved_this_turn = true
	return true

func _execute_launch_order(order: Order, player: PlayerData) -> bool:
	## Lance un Méga-Missile depuis from_sector vers to_sector.
	## Détruit TOUTES les unités sur le secteur cible sauf les drapeaux.
	var from_sector := game_state.board.get_sector(order.from_sector)
	if from_sector == null:
		return false

	# Trouver le missile du joueur sur le secteur source
	var missile: UnitData = null
	for unit in from_sector.units:
		if unit.owner == player.color and unit.unit_type == GameEnums.UnitType.MEGA_MISSILE:
			missile = unit
			break

	if missile == null:
		return false

	var to_sector := game_state.board.get_sector(order.to_sector)
	if to_sector == null:
		return false

	# Retirer le missile du jeu (consommé)
	game_state.remove_unit(missile)

	# Détruire toutes les unités sur le secteur cible sauf les drapeaux
	var units_to_destroy := to_sector.units.duplicate()
	var destroyed_count := 0
	for unit in units_to_destroy:
		if unit.unit_type == GameEnums.UnitType.FLAG:
			continue
		game_state.remove_unit(unit)
		destroyed_count += 1

	resolution_log.emit("  MÉGA-MISSILE: %s → %s (%d unités détruites!)" % [
		order.from_sector, order.to_sector, destroyed_count])

	# Animation de frappe missile
	if anim_manager:
		anim_manager.play_missile_strike(player.color, order.from_sector, order.to_sector)

	return true

func _execute_exchange_order(order: Order, player: PlayerData) -> bool:
	var location := order.exchange_location

	if location == "RV":
		var cost := GameEnums.get_unit_cost(order.exchange_result)
		var power_units := player.get_reserve_units_of_type(GameEnums.UnitType.POWER)
		if power_units.size() < cost:
			return false
		for i in range(cost):
			game_state.remove_unit(power_units[i])
		var new_unit := UnitData.new(order.exchange_result, player.color, "")
		game_state.all_units.append(new_unit)
		player.add_to_reserve(new_unit)
		return true

	var sector := game_state.board.get_sector(location)
	if sector == null:
		return false

	# Création de Méga-Missile
	if order.exchange_result == GameEnums.UnitType.MEGA_MISSILE:
		return _execute_missile_creation(order, player, sector)

	var source_type := order.unit_type
	var target_type := order.exchange_result
	var matching_units := []
	for unit in sector.units:
		if unit.owner == player.color and unit.unit_type == source_type:
			matching_units.append(unit)

	if matching_units.size() < 3:
		return false

	for i in range(3):
		game_state.remove_unit(matching_units[i])

	var upgraded := UnitData.new(target_type, player.color, location)
	game_state.all_units.append(upgraded)
	sector.units.append(upgraded)
	return true

func _execute_missile_creation(order: Order, player: PlayerData, sector: Sector) -> bool:
	## Sacrifie les unités listées dans exchange_units pour créer un Méga-Missile.
	## exchange_units contient des dictionnaires {type: UnitType, count: int}.
	var total_power := 0
	var units_to_sacrifice: Array = []

	for entry in order.exchange_units:
		var unit_type: GameEnums.UnitType = entry["type"]
		var count: int = entry["count"]
		var found := 0
		for unit in sector.units:
			if unit.owner == player.color and unit.unit_type == unit_type and unit not in units_to_sacrifice:
				units_to_sacrifice.append(unit)
				total_power += GameEnums.get_unit_power(unit_type)
				found += 1
				if found >= count:
					break
		if found < count:
			return false

	if total_power < 100:
		return false

	# Sacrifier les unités
	for unit in units_to_sacrifice:
		game_state.remove_unit(unit)

	# Créer le Méga-Missile sur le secteur
	var missile := UnitData.new(GameEnums.UnitType.MEGA_MISSILE, player.color, sector.id)
	game_state.all_units.append(missile)
	sector.units.append(missile)

	resolution_log.emit("  Création Méga-Missile en %s (puissance sacrifiée: %d)" % [
		sector.id, total_power])
	return true

func _apply_inaction_penalty(player: PlayerData) -> void:
	var power_units := player.get_reserve_units_of_type(GameEnums.UnitType.POWER)
	if power_units.size() > 0:
		game_state.remove_unit(power_units[0])
	else:
		_convert_smallest_to_power(player)

func _convert_smallest_to_power(player: PlayerData) -> void:
	var smallest: UnitData = null
	var smallest_value := 999

	for unit in game_state.all_units:
		if unit.owner == player.color and unit.unit_type != GameEnums.UnitType.FLAG:
			var val: int = unit.get_power()
			if val > 0 and val < smallest_value:
				smallest = unit
				smallest_value = val

	if smallest == null:
		return

	var group := GameEnums.get_unit_group(smallest.unit_type)
	if group == 2:
		var base_type := GameEnums.get_downgrade_type(smallest.unit_type)
		var sector_id := smallest.sector_id
		var was_reserve := smallest.in_reserve
		game_state.remove_unit(smallest)
		for i in range(3):
			var new_unit := UnitData.new(base_type, player.color, "")
			game_state.all_units.append(new_unit)
			if was_reserve:
				player.add_to_reserve(new_unit)
			elif sector_id != "":
				game_state.move_unit(new_unit, sector_id)
	else:
		game_state.remove_unit(smallest)
		var power := UnitData.new(GameEnums.UnitType.POWER, player.color, "")
		game_state.all_units.append(power)
		player.add_to_reserve(power)

# --- Phase 3: Résolution des conflits ---

func _phase_conflict() -> void:
	game_state.current_phase = GameEnums.GamePhase.CONFLICT
	phase_changed.emit(GameEnums.GamePhase.CONFLICT)

	if anim_manager:
		anim_manager.play_phase_title("Résolution des conflits")
		anim_manager.play_all()
		await anim_manager.animation_finished

	var max_iterations := 20
	var had_conflicts := true

	while had_conflicts and max_iterations > 0:
		had_conflicts = false
		max_iterations -= 1

		for sector_id in game_state.board.sectors:
			var sector: Sector = game_state.board.get_sector(sector_id)
			var players_present := sector.get_players_present()

			if players_present.size() < 2:
				continue

			if _resolve_combat(sector_id, players_present):
				had_conflicts = true

	# Jouer les animations de combat
	if anim_manager:
		anim_manager.play_all()
		await anim_manager.animation_finished

	if unit_renderer:
		unit_renderer.update_display()

func _resolve_combat(sector_id: String, players_present: Array[GameEnums.PlayerColor]) -> bool:
	var sector: Sector = game_state.board.get_sector(sector_id)

	var powers: Dictionary = {}
	for color in players_present:
		powers[color] = sector.get_player_power(color)

	var max_power := 0
	var max_players: Array[GameEnums.PlayerColor] = []
	for color in powers:
		if powers[color] > max_power:
			max_power = powers[color]
			max_players = [color]
		elif powers[color] == max_power:
			max_players.append(color)

	if max_players.size() == 1:
		var winner: GameEnums.PlayerColor = max_players[0]
		resolution_log.emit("Combat en %s: %s gagne (puissance %d)" % [
			sector_id, _color_name(winner), max_power])
		_capture_pieces_from_combat(sector_id, winner, players_present)
		combat_resolved.emit(sector_id, winner)

		if anim_manager:
			anim_manager.play_combat(sector_id, winner)
		return true
	else:
		resolution_log.emit("Égalité en %s: rebond!" % sector_id)
		_resolve_tie(sector_id, max_players)
		return true

func _capture_pieces_from_combat(sector_id: String, winner: GameEnums.PlayerColor, all_players: Array[GameEnums.PlayerColor]) -> void:
	var sector: Sector = game_state.board.get_sector(sector_id)
	var winner_player := game_state.get_player(winner)

	for color in all_players:
		if color == winner:
			continue
		var units_to_capture := sector.get_units_of_player(color).duplicate()
		for unit in units_to_capture:
			if unit.unit_type == GameEnums.UnitType.FLAG:
				continue
			game_state.remove_unit(unit)
			var captured := UnitData.new(unit.unit_type, winner, "")
			game_state.all_units.append(captured)
			winner_player.add_to_reserve(captured)

	if anim_manager:
		anim_manager.play_capture(sector_id, winner)

func _resolve_tie(sector_id: String, tied_players: Array[GameEnums.PlayerColor]) -> void:
	for color in tied_players:
		var sector: Sector = game_state.board.get_sector(sector_id)
		var units := sector.get_units_of_player(color).duplicate()
		for unit in units:
			if unit.moved_this_turn and not unit.rebounded_this_turn:
				unit.rebounded_this_turn = true
				var origin: String = unit.get_meta("origin_sector", "")
				if origin != "" and origin != sector_id:
					game_state.move_unit(unit, origin)
					resolution_log.emit("  Rebond: %s retourne en %s" % [
						unit.get_display_name(), origin])
					if anim_manager:
						anim_manager.play_rebond(unit.unit_type, color, sector_id, origin)

# --- Phase 5: Collecte des Power ---

func _phase_collect_power() -> void:
	game_state.current_phase = GameEnums.GamePhase.COLLECT_POWER
	phase_changed.emit(GameEnums.GamePhase.COLLECT_POWER)

	for color in game_state.get_active_players():
		_collect_power_for_player(color)

	if unit_renderer:
		unit_renderer.update_display()

func _collect_power_for_player(color: GameEnums.PlayerColor) -> void:
	var player := game_state.get_player(color)

	for enemy_color in game_state.player_order:
		if enemy_color == color:
			continue
		var enemy_player := game_state.get_player(enemy_color)
		if enemy_player.is_eliminated:
			continue

		var prefix := game_state.board.get_territory_prefix(enemy_color)
		var occupies := false
		for i in range(9):
			var sector_id := "%s%d" % [prefix, i]
			var sector := game_state.board.get_sector(sector_id)
			if sector and sector.has_units_of_player(color):
				occupies = true
				break

		if occupies:
			var power := UnitData.new(GameEnums.UnitType.POWER, color, "")
			game_state.all_units.append(power)
			player.add_to_reserve(power)
			resolution_log.emit("%s gagne 1 Power (territoire %s)" % [
				_color_name(color), _color_name(enemy_color)])

# --- Phase 6: Capture des drapeaux ---

func _phase_capture_flags() -> void:
	game_state.current_phase = GameEnums.GamePhase.CAPTURE_FLAGS
	phase_changed.emit(GameEnums.GamePhase.CAPTURE_FLAGS)

	for color in game_state.get_active_players():
		_check_flag_captures(color)

	# Jouer les animations de capture de drapeau
	if anim_manager:
		anim_manager.play_all()
		await anim_manager.animation_finished

	_check_game_over()

func _check_flag_captures(attacker: GameEnums.PlayerColor) -> void:
	for enemy_color in game_state.player_order:
		if enemy_color == attacker:
			continue
		var enemy_player := game_state.get_player(enemy_color)
		if enemy_player.is_eliminated:
			continue

		var prefix := game_state.board.get_territory_prefix(enemy_color)
		var hq_id := "HQ_" + prefix
		var hq := game_state.board.get_sector(hq_id)
		if hq == null or not hq.has_units_of_player(attacker):
			continue

		var has_infantry := false
		for unit in hq.get_units_of_player(attacker):
			if unit.unit_type == GameEnums.UnitType.SOLDIER or unit.unit_type == GameEnums.UnitType.REGIMENT:
				has_infantry = true
				break

		if not has_infantry:
			continue

		if hq.get_player_power(attacker) <= hq.get_player_power(enemy_color):
			continue

		_capture_flag(attacker, enemy_color)

func _capture_flag(capturer: GameEnums.PlayerColor, captured: GameEnums.PlayerColor) -> void:
	var capturer_player := game_state.get_player(capturer)
	var captured_player := game_state.get_player(captured)

	captured_player.is_eliminated = true
	capturer_player.flags_captured.append(captured)

	var units_to_transfer := []
	for unit in game_state.all_units:
		if unit.owner == captured and unit.unit_type != GameEnums.UnitType.FLAG:
			units_to_transfer.append(unit)

	for unit in units_to_transfer:
		unit.owner = capturer
		if not unit.in_reserve:
			var sector := game_state.board.get_sector(unit.sector_id)
			if sector:
				var idx: int = sector.units.find(unit)
				if idx >= 0:
					sector.units.remove_at(idx)
		capturer_player.add_to_reserve(unit)

	resolution_log.emit("DRAPEAU CAPTURÉ: %s élimine %s!" % [
		_color_name(capturer), _color_name(captured)])

	if anim_manager:
		anim_manager.play_flag_capture(capturer, captured)

	flag_captured.emit(capturer, captured)
	player_eliminated.emit(captured)

func _check_game_over() -> bool:
	var active := game_state.get_active_players()
	if active.size() <= 1:
		var winner: GameEnums.PlayerColor = active[0] if active.size() == 1 else GameEnums.PlayerColor.NONE
		game_state.current_phase = GameEnums.GamePhase.GAME_OVER
		game_over.emit(winner)
		return true
	return false

func _end_game_by_timeout() -> void:
	var best_color: GameEnums.PlayerColor = GameEnums.PlayerColor.NONE
	var best_power := -1
	for color in game_state.get_active_players():
		var total: int = game_state.calculate_player_total_power(color)
		if total > best_power:
			best_power = total
			best_color = color
	game_state.current_phase = GameEnums.GamePhase.GAME_OVER
	resolution_log.emit("TEMPS ÉCOULÉ! Victoire de %s (puissance %d)" % [
		_color_name(best_color), best_power])
	game_over.emit(best_color)

func _color_name(c: GameEnums.PlayerColor) -> String:
	match c:
		GameEnums.PlayerColor.GREEN: return "Vert"
		GameEnums.PlayerColor.BLUE: return "Bleu"
		GameEnums.PlayerColor.YELLOW: return "Jaune"
		GameEnums.PlayerColor.RED: return "Rouge"
		_: return "?"
