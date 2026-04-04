class_name AIPlayer
extends RefCounted

## IA pour le jeu Power.
## Stratégie en priorité:
## 1. Échanger des pièces si possible (monter en puissance)
## 2. Déployer les unités de la réserve vers le QG
## 3. Envoyer des unités rapides (chasseurs) en territoire ennemi pour gagner des Power
## 4. Attaquer les QG ennemis avec des soldats + escorte
## 5. Défendre son propre QG si menacé

var color: GameEnums.PlayerColor
var game_state: GameState
var _rng := RandomNumberGenerator.new()

func _init(p_color: GameEnums.PlayerColor, p_state: GameState) -> void:
	color = p_color
	game_state = p_state
	_rng.randomize()

func generate_orders() -> Array[Order]:
	var orders: Array[Order] = []
	var my_units := _get_my_board_units()
	var moved_units: Array[UnitData] = []

	# Priorité 1: Échanges (monter en puissance)
	_try_exchanges(orders)

	# Priorité 2: Déployer depuis la réserve
	_try_deploy_reserve(orders)

	# Priorité 3: Défendre le QG si menacé
	_try_defend_hq(orders, my_units, moved_units)

	# Priorité 4: Envoyer des chasseurs/bombardiers en territoire ennemi (Power)
	_try_raid_for_power(orders, my_units, moved_units)

	# Priorité 5: Avancer des troupes terrestres vers l'ennemi
	_try_advance_ground(orders, my_units, moved_units)

	# Priorité 6: Déplacer les navires en soutien
	_try_move_ships(orders, my_units, moved_units)

	# Si on n'a toujours aucun ordre, faire un mouvement aléatoire
	if orders.is_empty():
		_try_random_move(orders, my_units, moved_units)

	return orders

# ===== ÉCHANGES =====

func _try_exchanges(orders: Array[Order]) -> void:
	if orders.size() >= 5:
		return

	var player := game_state.get_player(color)

	# Échanger Power -> unités depuis la réserve
	var power_count := player.get_reserve_power_count()

	# Priorité: acheter des soldats (coût 2) pour capturer des drapeaux
	while power_count >= 2 and orders.size() < 4:  # garder 1 slot pour un déplacement
		var order := Order.create_exchange(color, [], GameEnums.UnitType.SOLDIER, "RV")
		orders.append(order)
		power_count -= 2

	# Échanges 3 petites → 1 grosse sur le plateau
	_try_upgrade_on_board(orders)

func _try_upgrade_on_board(orders: Array[Order]) -> void:
	if orders.size() >= 5:
		return

	var board := game_state.board
	for sector_id in board.sectors:
		var sector: Sector = board.get_sector(sector_id)
		if sector == null:
			continue

		# Compter mes unités par type
		var counts: Dictionary = {}
		for unit in sector.units:
			if unit.owner == color:
				var group := GameEnums.get_unit_group(unit.unit_type)
				if group == 1:
					if unit.unit_type not in counts:
						counts[unit.unit_type] = 0
					counts[unit.unit_type] += 1

		for unit_type in counts:
			if counts[unit_type] >= 3 and orders.size() < 5:
				var result := GameEnums.get_upgrade_type(unit_type)
				var order := Order.create_exchange(color, [], result, sector_id)
				order.unit_type = unit_type
				orders.append(order)
				counts[unit_type] -= 3

# ===== DÉPLOIEMENT RÉSERVE =====

func _try_deploy_reserve(orders: Array[Order]) -> void:
	if orders.size() >= 5:
		return

	var player := game_state.get_player(color)
	var prefix := game_state.board.get_territory_prefix(color)
	var hq_id := "HQ_" + prefix

	for unit in player.reserve:
		if orders.size() >= 5:
			break
		if unit.unit_type == GameEnums.UnitType.POWER or unit.unit_type == GameEnums.UnitType.FLAG:
			continue
		if unit.unit_type == GameEnums.UnitType.MEGA_MISSILE:
			continue  # On gère les missiles séparément

		var order := Order.create_move(color, unit.unit_type, "RV", hq_id)
		orders.append(order)

# ===== DÉFENSE DU QG =====

func _try_defend_hq(orders: Array[Order], my_units: Array, moved: Array[UnitData]) -> void:
	if orders.size() >= 5:
		return

	var prefix := game_state.board.get_territory_prefix(color)
	var hq_id := "HQ_" + prefix
	var hq := game_state.board.get_sector(hq_id)
	if hq == null:
		return

	# Vérifier si des ennemis sont proches du QG (distance <= 2)
	var threat := false
	var nearby_sectors := game_state.board.get_reachable_sectors(hq_id, GameEnums.UnitType.SOLDIER, 2)
	for sid in nearby_sectors:
		var sector := game_state.board.get_sector(sid)
		if sector == null:
			continue
		for unit in sector.units:
			if unit.owner != color and unit.unit_type != GameEnums.UnitType.FLAG:
				threat = true
				break
		if threat:
			break

	if not threat:
		return

	# Rappeler des unités proches vers le QG
	for unit in my_units:
		if orders.size() >= 5:
			break
		if unit in moved:
			continue
		if unit.unit_type == GameEnums.UnitType.FLAG:
			continue

		var dist := game_state.board.get_distance(unit.sector_id, hq_id, unit.unit_type)
		if dist > 0 and dist <= unit.get_max_move():
			var order := Order.create_move(color, unit.unit_type, unit.sector_id, hq_id)
			orders.append(order)
			moved.append(unit)

# ===== RAIDS AÉRIENS POUR POWER =====

func _try_raid_for_power(orders: Array[Order], my_units: Array, moved: Array[UnitData]) -> void:
	if orders.size() >= 5:
		return

	# Trouver les territoires ennemis non occupés par nous
	var enemy_territories := _get_enemy_territory_sectors()

	for unit in my_units:
		if orders.size() >= 5:
			break
		if unit in moved:
			continue
		if not GameEnums.is_air_unit(unit.unit_type):
			continue

		# Chercher un secteur ennemi atteignable et peu défendu
		var best_target := ""
		var best_score := -1

		var reachable := game_state.board.get_reachable_sectors(
			unit.sector_id, unit.unit_type, unit.get_max_move())

		for target_id in reachable:
			if target_id not in enemy_territories:
				continue

			var target := game_state.board.get_sector(target_id)
			if target == null:
				continue

			# Score: préférer les secteurs vides ou faibles
			var enemy_power := 0
			for u in target.units:
				if u.owner != color:
					enemy_power += u.get_power()

			var score := 10 - enemy_power
			if not target.has_units_of_player(color):
				score += 5  # Bonus si on n'occupe pas encore ce territoire

			if score > best_score:
				best_score = score
				best_target = target_id

		if best_target != "":
			var order := Order.create_move(color, unit.unit_type, unit.sector_id, best_target)
			orders.append(order)
			moved.append(unit)

# ===== AVANCÉE TERRESTRE =====

func _try_advance_ground(orders: Array[Order], my_units: Array, moved: Array[UnitData]) -> void:
	if orders.size() >= 5:
		return

	# Objectif: avancer les soldats/tanks vers les QG ennemis
	var enemy_hqs := _get_enemy_hq_ids()

	for unit in my_units:
		if orders.size() >= 5:
			break
		if unit in moved:
			continue
		if not GameEnums.is_land_unit(unit.unit_type):
			continue
		if unit.unit_type == GameEnums.UnitType.FLAG:
			continue

		# Trouver le QG ennemi le plus proche
		var best_hq := ""
		var best_dist := 999

		for hq_id in enemy_hqs:
			var dist := game_state.board.get_distance(unit.sector_id, hq_id, unit.unit_type)
			if dist > 0 and dist < best_dist:
				best_dist = dist
				best_hq = hq_id

		if best_hq == "":
			continue

		# Avancer d'un pas vers ce QG
		var path := game_state.board.find_path(unit.sector_id, best_hq, unit.unit_type)
		if path.size() < 2:
			continue

		# Avancer du max de mouvement possible le long du chemin
		var max_move := unit.get_max_move()
		var target_idx := mini(max_move, path.size() - 1)
		var target_id: String = path[target_idx]

		var order := Order.create_move(color, unit.unit_type, unit.sector_id, target_id)
		orders.append(order)
		moved.append(unit)

# ===== NAVIRES =====

func _try_move_ships(orders: Array[Order], my_units: Array, moved: Array[UnitData]) -> void:
	if orders.size() >= 5:
		return

	var enemy_territories := _get_enemy_territory_sectors()

	for unit in my_units:
		if orders.size() >= 5:
			break
		if unit in moved:
			continue
		if not GameEnums.is_naval_unit(unit.unit_type):
			continue

		# Les navires: avancer vers des secteurs côtiers ennemis pour soutenir
		var reachable := game_state.board.get_reachable_sectors(
			unit.sector_id, unit.unit_type, unit.get_max_move())

		var best_target := ""
		var best_score := -1

		for target_id in reachable:
			var target := game_state.board.get_sector(target_id)
			if target == null:
				continue

			var score := 0
			# Préférer les secteurs côtiers ennemis
			if target_id in enemy_territories:
				score += 5
			# Préférer les secteurs avec des ennemis faibles
			for u in target.units:
				if u.owner != color:
					if u.get_power() < unit.get_power():
						score += 3  # On peut les capturer

			# Éviter de rester au même endroit
			if target_id != unit.sector_id and score > best_score:
				best_score = score
				best_target = target_id

		if best_target != "":
			var order := Order.create_move(color, unit.unit_type, unit.sector_id, best_target)
			orders.append(order)
			moved.append(unit)

# ===== MOUVEMENT ALÉATOIRE (FALLBACK) =====

func _try_random_move(orders: Array[Order], my_units: Array, moved: Array[UnitData]) -> void:
	# Mélanger les unités pour ne pas toujours déplacer les mêmes
	var shuffled := my_units.duplicate()
	_shuffle_array(shuffled)

	for unit in shuffled:
		if orders.size() >= 1:  # Au moins 1 ordre pour éviter la pénalité
			break
		if unit in moved:
			continue
		if unit.unit_type == GameEnums.UnitType.FLAG:
			continue
		if unit.get_max_move() <= 0:
			continue

		var reachable := game_state.board.get_reachable_sectors(
			unit.sector_id, unit.unit_type, unit.get_max_move())

		if reachable.is_empty():
			continue

		var target_id: String = reachable[_rng.randi_range(0, reachable.size() - 1)]
		var order := Order.create_move(color, unit.unit_type, unit.sector_id, target_id)
		orders.append(order)
		moved.append(unit)

# ===== UTILITAIRES =====

func _get_my_board_units() -> Array:
	var result := []
	for unit in game_state.all_units:
		if unit.owner == color and not unit.in_reserve and unit.sector_id != "":
			result.append(unit)
	return result

func _get_enemy_territory_sectors() -> Array[String]:
	## Retourne les IDs des secteurs de territoires ennemis (pas les îles/mer).
	var result: Array[String] = []
	for enemy_color in game_state.player_order:
		if enemy_color == color:
			continue
		var player := game_state.get_player(enemy_color)
		if player.is_eliminated:
			continue

		var prefix := game_state.board.get_territory_prefix(enemy_color)
		for i in range(9):
			result.append("%s%d" % [prefix, i])
	return result

func _get_enemy_hq_ids() -> Array[String]:
	var result: Array[String] = []
	for enemy_color in game_state.player_order:
		if enemy_color == color:
			continue
		var player := game_state.get_player(enemy_color)
		if player.is_eliminated:
			continue
		var prefix := game_state.board.get_territory_prefix(enemy_color)
		result.append("HQ_" + prefix)
	return result

func _shuffle_array(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
