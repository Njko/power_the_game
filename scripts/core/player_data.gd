class_name PlayerData
extends RefCounted

var color: GameEnums.PlayerColor
var is_eliminated: bool = false
var reserve: Array = []  # UnitData en réserve
var flags_captured: Array[GameEnums.PlayerColor] = []  # Drapeaux capturés
var orders: Array = []  # Orders pour la manche en cours

func _init(p_color: GameEnums.PlayerColor) -> void:
	color = p_color

func add_to_reserve(unit: UnitData) -> void:
	unit.in_reserve = true
	unit.sector_id = ""
	reserve.append(unit)

func remove_from_reserve(unit: UnitData) -> void:
	var idx := reserve.find(unit)
	if idx >= 0:
		reserve.remove_at(idx)
		unit.in_reserve = false

func get_reserve_power_count() -> int:
	var count := 0
	for unit in reserve:
		if unit.unit_type == GameEnums.UnitType.POWER:
			count += 1
	return count

func get_reserve_units_of_type(unit_type: GameEnums.UnitType) -> Array:
	var result := []
	for unit in reserve:
		if unit.unit_type == unit_type:
			result.append(unit)
	return result

func get_total_power_value() -> int:
	## Calcule la puissance totale (plateau + réserve) pour le score final.
	var total := 0
	for unit in reserve:
		total += unit.get_power()
	return total

func clear_orders() -> void:
	orders.clear()

func add_order(order: Order) -> void:
	if orders.size() < 5:
		orders.append(order)
