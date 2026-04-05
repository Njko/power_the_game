# Mega-Missile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement full Mega-Missile mechanics: creation (sacrifice 100+ power worth of units), launch (destroy all non-flag units on target sector), and AI strategy.

**Architecture:** Extend the existing order system with `OrderType.LAUNCH` and a new `create_missile_exchange()` factory. Launch orders execute inline during `_phase_execution()` like any other order. The OrderPanel gets two new modes: missile creation (unit selection with power counter) and missile launch (unlimited range targeting). Animation reuses the existing `play_explosion()` infrastructure.

**Tech Stack:** Godot 4.6, GDScript, procedural `_draw()` rendering

**Spec:** `docs/superpowers/specs/2026-04-05-mega-missile-design.md`

---

### Task 1: Add OrderType.LAUNCH and Order factory methods

**Files:**
- Modify: `scripts/core/game_enums.gd:34-37`
- Modify: `scripts/core/order.gd`

- [ ] **Step 1: Add LAUNCH to OrderType enum**

In `scripts/core/game_enums.gd`, change:

```gdscript
enum OrderType {
	MOVE,
	EXCHANGE
}
```

to:

```gdscript
enum OrderType {
	MOVE,
	EXCHANGE,
	LAUNCH
}
```

- [ ] **Step 2: Add create_launch() factory method**

In `scripts/core/order.gd`, after the `create_exchange()` method (after line 36), add:

```gdscript
static func create_launch(p_player: GameEnums.PlayerColor, p_from: String, p_to: String) -> Order:
	var order = Order.new()
	order.order_type = GameEnums.OrderType.LAUNCH
	order.player = p_player
	order.unit_type = GameEnums.UnitType.MEGA_MISSILE
	order.from_sector = p_from
	order.to_sector = p_to
	return order
```

- [ ] **Step 3: Add create_missile_exchange() factory method**

In `scripts/core/order.gd`, after `create_launch()`, add:

```gdscript
static func create_missile_exchange(p_player: GameEnums.PlayerColor, p_sacrificed: Array, p_location: String) -> Order:
	var order = Order.new()
	order.order_type = GameEnums.OrderType.EXCHANGE
	order.player = p_player
	order.exchange_units = p_sacrificed
	order.exchange_result = GameEnums.UnitType.MEGA_MISSILE
	order.exchange_location = p_location
	order.unit_type = GameEnums.UnitType.MEGA_MISSILE  # marker for description
	return order
```

- [ ] **Step 4: Update get_description() for LAUNCH and missile EXCHANGE**

In `scripts/core/order.gd`, replace the `get_description()` method:

```gdscript
func get_description() -> String:
	if order_type == GameEnums.OrderType.MOVE:
		return "%s: %s → %s" % [
			GameEnums.get_unit_name(unit_type),
			from_sector,
			to_sector
		]
	elif order_type == GameEnums.OrderType.LAUNCH:
		return "Méga-Missile: %s → %s" % [from_sector, to_sector]
	else:
		if exchange_result == GameEnums.UnitType.MEGA_MISSILE:
			return "Création Méga-Missile (%s)" % exchange_location
		return "Échange → %s (%s)" % [
			GameEnums.get_unit_name(exchange_result),
			exchange_location
		]
```

- [ ] **Step 5: Commit**

```bash
git add scripts/core/game_enums.gd scripts/core/order.gd
git commit -m "feat: add OrderType.LAUNCH and missile factory methods"
```

---

### Task 2: Implement missile creation logic in GameManager

**Files:**
- Modify: `scripts/core/game_manager.gd:305-340`

- [ ] **Step 1: Extend _execute_exchange_order() for MEGA_MISSILE creation**

In `scripts/core/game_manager.gd`, find the `_execute_exchange_order()` function (line 305). After the reserve exchange block (lines 308-318) and before the on-board exchange block (line 320), insert a new block to handle missile creation:

```gdscript
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
```

- [ ] **Step 2: Add _execute_missile_creation() function**

Add this new function after `_execute_exchange_order()`:

```gdscript
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
```

- [ ] **Step 3: Commit**

```bash
git add scripts/core/game_manager.gd
git commit -m "feat: implement mega-missile creation from sacrificed units"
```

---

### Task 3: Implement missile launch logic in GameManager

**Files:**
- Modify: `scripts/core/game_manager.gd:245-249`

- [ ] **Step 1: Add LAUNCH case to _validate_and_execute_order()**

In `scripts/core/game_manager.gd`, replace `_validate_and_execute_order()`:

```gdscript
func _validate_and_execute_order(order: Order, player: PlayerData) -> bool:
	if order.order_type == GameEnums.OrderType.MOVE:
		return _execute_move_order(order, player)
	elif order.order_type == GameEnums.OrderType.LAUNCH:
		return _execute_launch_order(order, player)
	else:
		return _execute_exchange_order(order, player)
```

- [ ] **Step 2: Add _execute_launch_order() function**

Add this function after `_execute_reserve_deploy()`:

```gdscript
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

	# Animation d'explosion
	if anim_manager:
		anim_manager.play_move(GameEnums.UnitType.MEGA_MISSILE, player.color,
			order.from_sector, order.to_sector)
		anim_manager.play_explosion(order.to_sector)

	return true
```

- [ ] **Step 3: Commit**

```bash
git add scripts/core/game_manager.gd
git commit -m "feat: implement mega-missile launch with destruction logic"
```

---

### Task 4: Add missile creation UI to OrderPanel

**Files:**
- Modify: `scripts/ui/order_panel.gd`

- [ ] **Step 1: Add missile mode state variables**

In `scripts/ui/order_panel.gd`, after `_is_exchange_mode` (line 18), add:

```gdscript
var _is_missile_create_mode: bool = false
var _missile_create_sector: String = ""
var _missile_selected_units: Dictionary = {}  # UnitType -> count
var _missile_available_units: Dictionary = {}  # UnitType -> max available count
var _missile_total_power: int = 0
```

- [ ] **Step 2: Add missile creation button in _build_ui()**

In `_build_ui()`, after the `_exchange_button` block (after line 81), add:

```gdscript
var _missile_button := Button.new()
_missile_button.text = "Créer Méga-Missile"
_missile_button.name = "MissileButton"
_missile_button.pressed.connect(_on_missile_create_pressed)
btn_box.add_child(_missile_button)
```

- [ ] **Step 3: Add missile creation mode handlers**

Add these functions before `_get_color_name()` at the end of the file:

```gdscript
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

	var color_str := "VERT" if _missile_total_power >= 100 else "ROUGE"
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
```

- [ ] **Step 4: Wire missile create mode into handle_sector_click()**

Replace `handle_sector_click()`:

```gdscript
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
		_try_select_unit(sector_id)
	else:
		_try_set_destination(sector_id)
```

- [ ] **Step 5: Reset missile state in activate()**

In the `activate()` function, after `_is_exchange_mode = false` (line 123), add:

```gdscript
_is_missile_create_mode = false
_missile_create_sector = ""
_missile_selected_units.clear()
_missile_available_units.clear()
_missile_total_power = 0
```

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/order_panel.gd
git commit -m "feat: add mega-missile creation UI with unit selection"
```

---

### Task 5: Add missile launch UI to OrderPanel

**Files:**
- Modify: `scripts/ui/order_panel.gd`

- [ ] **Step 1: Handle MEGA_MISSILE selection in _try_select_unit()**

In `_try_select_unit()`, the existing code at line 177 already allows selecting mega-missiles. We need to modify the destination highlighting to show all sectors for unlimited range. Replace the reachable sectors block (lines 198-210):

```gdscript
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
```

- [ ] **Step 2: Handle MEGA_MISSILE destination in _try_set_destination()**

In `_try_set_destination()`, add a special case for missiles before the accessibility check (before line 228). Replace the function:

```gdscript
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
```

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/order_panel.gd
git commit -m "feat: add mega-missile launch UI with unlimited range"
```

---

### Task 6: Add AI mega-missile strategy

**Files:**
- Modify: `scripts/ai/ai_player.gd`

- [ ] **Step 1: Replace the missile skip with strategy in generate_orders()**

In `scripts/ai/ai_player.gd`, add a new priority between exchanges and deploy reserve. Replace `generate_orders()`:

```gdscript
func generate_orders() -> Array[Order]:
	var orders: Array[Order] = []
	var my_units := _get_my_board_units()
	var moved_units: Array[UnitData] = []

	# Priorité 1: Échanges (monter en puissance)
	_try_exchanges(orders)

	# Priorité 1b: Lancer les méga-missiles existants
	_try_launch_missiles(orders, my_units, moved_units)

	# Priorité 1c: Créer un méga-missile si puissance suffisante
	_try_create_missile(orders)

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
```

- [ ] **Step 2: Add _try_launch_missiles() function**

After `_try_upgrade_on_board()`, add:

```gdscript
func _try_launch_missiles(orders: Array[Order], my_units: Array, moved: Array[UnitData]) -> void:
	if orders.size() >= 5:
		return

	# Trouver mes méga-missiles sur le plateau
	for unit in my_units:
		if orders.size() >= 5:
			break
		if unit.unit_type != GameEnums.UnitType.MEGA_MISSILE:
			continue
		if unit in moved:
			continue

		# Trouver la meilleure cible
		var best_target := ""
		var best_score := 0

		for sector_id in game_state.board.sectors:
			var sector: Sector = game_state.board.get_sector(sector_id)
			if sector == null:
				continue

			# Ne pas cibler ses propres unités seules
			var has_enemy := false
			var has_own := false
			var enemy_power := 0
			for u in sector.units:
				if u.unit_type == GameEnums.UnitType.FLAG:
					continue
				if u.owner == color:
					has_own = true
				else:
					has_enemy = true
					enemy_power += GameEnums.get_unit_power(u.unit_type)

			if not has_enemy or has_own:
				continue

			# Score basé sur la puissance ennemie détruite
			var score := enemy_power

			# Bonus pour les QG ennemis
			if sector.sector_type == GameEnums.SectorType.HQ and sector.owner_territory != color:
				score += 20

			if score > best_score:
				best_score = score
				best_target = sector_id

		# Ne lancer que si on détruit au moins 30 de puissance
		if best_target != "" and best_score >= 30:
			var order := Order.create_launch(color, unit.sector_id, best_target)
			orders.append(order)
			moved.append(unit)
```

- [ ] **Step 3: Add _try_create_missile() function**

After `_try_launch_missiles()`, add:

```gdscript
func _try_create_missile(orders: Array[Order]) -> void:
	if orders.size() >= 4:  # Garder des slots pour d'autres ordres
		return

	# Chercher un secteur avec assez de puissance pour créer un missile
	for sector_id in game_state.board.sectors:
		if orders.size() >= 4:
			break

		var sector: Sector = game_state.board.get_sector(sector_id)
		if sector == null:
			continue

		var my_units_here: Dictionary = {}  # UnitType -> count
		var total_power := 0
		for unit in sector.units:
			if unit.owner == color and unit.unit_type != GameEnums.UnitType.FLAG and unit.unit_type != GameEnums.UnitType.MEGA_MISSILE:
				var ut: GameEnums.UnitType = unit.unit_type
				if ut not in my_units_here:
					my_units_here[ut] = 0
				my_units_here[ut] += 1
				total_power += GameEnums.get_unit_power(ut)

		# Ne créer un missile que si on a largement plus de 100
		# (on sacrifie tout, donc il faut que ça en vaille la peine)
		if total_power < 120:
			continue

		# Construire la liste de sacrifice
		var sacrificed: Array = []
		for ut in my_units_here:
			sacrificed.append({"type": ut, "count": my_units_here[ut]})

		var order := Order.create_missile_exchange(color, sacrificed, sector_id)
		orders.append(order)
```

- [ ] **Step 4: Update _try_deploy_reserve() to handle missiles**

In `_try_deploy_reserve()`, replace the skip at lines 113-114:

```gdscript
		if unit.unit_type == GameEnums.UnitType.POWER or unit.unit_type == GameEnums.UnitType.FLAG:
			continue
		if unit.unit_type == GameEnums.UnitType.MEGA_MISSILE:
			# Déployer les missiles capturés vers le QG
			var order := Order.create_move(color, unit.unit_type, "RV", hq_id)
			orders.append(order)
			continue
```

Wait — missiles have 0 max_move, so they can't be deployed via MOVE from reserve to HQ with standard validation. The reserve deploy doesn't check max_move (line 286-303 in game_manager.gd just checks the unit is in reserve and destination is HQ). So this should work. But actually, let me re-read: `_execute_reserve_deploy` doesn't check max_move, it just checks the unit exists in reserve and target is HQ. So deploying a captured missile from reserve is fine.

Replace lines 111-114 with:

```gdscript
		if unit.unit_type == GameEnums.UnitType.POWER or unit.unit_type == GameEnums.UnitType.FLAG:
			continue
```

This removes the missile skip entirely, allowing missiles to be deployed from reserve like any other unit.

- [ ] **Step 5: Commit**

```bash
git add scripts/ai/ai_player.gd
git commit -m "feat: add AI mega-missile creation and launch strategy"
```

---

### Task 7: Add missile animation enhancement

**Files:**
- Modify: `scripts/ui/animation_manager.gd`

The existing `play_explosion()` and `_animate_explosion()` already work. The launch order in Task 3 already queues `play_move()` + `play_explosion()`. However, we should add a more dramatic missile-specific animation.

- [ ] **Step 1: Add play_missile_strike() method**

In `scripts/ui/animation_manager.gd`, after `play_explosion()` (line 78), add:

```gdscript
func play_missile_strike(owner: GameEnums.PlayerColor, from_sector: String, to_sector: String) -> void:
	_animation_queue.append({
		"type": "missile_strike",
		"owner": owner,
		"from": from_sector,
		"to": to_sector,
	})
```

- [ ] **Step 2: Handle missile_strike in _play_next()**

In `_play_next()`, add a case in the match statement (after "explosion"):

```gdscript
		"missile_strike":
			_animate_missile_strike(anim)
```

- [ ] **Step 3: Add _animate_missile_strike() function**

After `_animate_explosion()`, add:

```gdscript
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
```

- [ ] **Step 4: Update _execute_launch_order() to use play_missile_strike()**

In `scripts/core/game_manager.gd`, in `_execute_launch_order()`, replace the animation lines:

```gdscript
	# Animation de frappe missile
	if anim_manager:
		anim_manager.play_missile_strike(player.color, order.from_sector, order.to_sector)
```

(This replaces the previous `play_move()` + `play_explosion()` combo.)

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/animation_manager.gd scripts/core/game_manager.gd
git commit -m "feat: add dedicated missile strike animation (fly + explosion)"
```

---

### Task 8: Integration testing and edge cases

**Files:**
- Modify: `scripts/core/game_manager.gd` (if fixes needed)
- Modify: `scripts/ui/order_panel.gd` (if fixes needed)

- [ ] **Step 1: Test missile creation and launch manually**

Launch the game:
```bash
"/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --path .
```

Test scenario:
1. Start a solo game
2. Move all units to a single sector over several rounds to build up power
3. Use "Créer Méga-Missile" button to select units totaling 100+
4. Create the missile
5. Next round, select the missile on the board and launch it at an enemy sector
6. Verify the explosion animation plays and all non-flag units are destroyed

- [ ] **Step 2: Test creation + launch in same turn**

1. Ensure you have 100+ power units on a sector
2. Create missile (order 1)
3. Select the newly-created missile and launch it (order 2) — Note: the missile isn't physically on the board yet during planning, so this needs the order panel to track "virtual" missile positions from pending creation orders

This is a known edge case. The missile from a creation order won't physically exist on the board during planning. To support same-turn creation + launch, we need the order panel to track pending missiles.

Add tracking in order_panel.gd — after `_on_missile_create_confirm()` succeeds, remember the sector where the missile will be created:

```gdscript
var _pending_missile_sectors: Array[String] = []  # Sectors where missiles will be created this turn
```

Initialize in `activate()`:
```gdscript
_pending_missile_sectors.clear()
```

In `_on_missile_create_confirm()`, after appending the order:
```gdscript
_pending_missile_sectors.append(_missile_create_sector)
```

In `_try_select_unit()`, add a check for pending missiles. After checking available_units from the sector, also check pending missiles:

```gdscript
	# Aussi vérifier les missiles créés ce tour (pas encore sur le plateau)
	if sector_id in _pending_missile_sectors and available_units.is_empty():
		# Simuler un missile pour la sélection
		_selected_unit = UnitData.new(GameEnums.UnitType.MEGA_MISSILE, current_player, sector_id)
		_selected_from_sector = sector_id
		var all_sectors: Array[String] = []
		for sid in game_state.board.sectors:
			if sid != sector_id:
				all_sectors.append(sid)
		if board_renderer:
			board_renderer.highlight_sectors(all_sectors)
			board_renderer.selected_sector = sector_id
			board_renderer.queue_redraw()
		_instruction_label.text = "Méga-Missile (en cours de création) en %s\nCliquez sur le secteur cible" % sector_id
		return
```

- [ ] **Step 3: Test AI missile behavior**

1. Play several rounds and observe AI behavior
2. The AI should create missiles when a sector accumulates 120+ power (rare in normal play)
3. The AI should launch missiles at enemy concentrations with 30+ power
4. Verify no crashes from AI missile orders

- [ ] **Step 4: Test missile capture in combat**

1. Place a missile on a contested sector (via creation without launching)
2. Let enemies attack that sector
3. The missile has 0 power → the attacker wins
4. Verify the missile is captured to the winner's reserve

- [ ] **Step 5: Test missile on sector with flags**

1. Launch a missile at an enemy HQ that has a flag + units
2. Verify units are destroyed but the flag remains

- [ ] **Step 6: Commit any fixes**

```bash
git add -u
git commit -m "fix: edge cases for mega-missile creation, launch, and capture"
```

---

### Task 9: Final cleanup and visual verification

**Files:**
- Review all modified files

- [ ] **Step 1: Verify unit_renderer.gd missile icon is adequate**

The `_draw_missile()` function already exists at line 275 of `scripts/units/unit_renderer.gd`. It draws a missile body with ogive, fins, and a radioactive symbol. No changes needed.

- [ ] **Step 2: Verify get_players_present() excludes MEGA_MISSILE from conflict trigger**

In `scripts/core/sector.gd:58-63`, `get_players_present()` excludes FLAGs but not MEGA_MISSILEs. Since missiles have 0 power, they correctly don't contribute to combat power calculations (line 42: `get_unit_power()` returns 0 for missiles). But they DO trigger conflict resolution since they count as a "player present". This is correct — a missile alone on a contested sector means the attacker wins (captures the missile). No changes needed.

- [ ] **Step 3: Run the game end-to-end**

```bash
"/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --path .
```

Play a full game verifying:
- Missile creation works with the selection UI
- Missile launch works with unlimited range
- Explosion animation plays
- Combat with missiles (0 power capture)
- AI creates/launches missiles when appropriate
- No console errors

- [ ] **Step 4: Final commit**

```bash
git add -u
git commit -m "feat: complete mega-missile implementation (creation, launch, AI, animations)"
```
