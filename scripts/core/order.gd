class_name Order
extends RefCounted

var order_type: GameEnums.OrderType
var player: GameEnums.PlayerColor

# Pour les déplacements
var unit_type: GameEnums.UnitType
var from_sector: String
var to_sector: String

# Pour les échanges
var exchange_units: Array = []       # Unités à échanger
var exchange_result: GameEnums.UnitType  # Unité résultante
var exchange_location: String        # Secteur ou "RV" (réserve)

var is_valid: bool = true
var invalid_reason: String = ""

static func create_move(p_player: GameEnums.PlayerColor, p_unit: GameEnums.UnitType, p_from: String, p_to: String) -> Order:
	var order = Order.new()
	order.order_type = GameEnums.OrderType.MOVE
	order.player = p_player
	order.unit_type = p_unit
	order.from_sector = p_from
	order.to_sector = p_to
	return order

static func create_exchange(p_player: GameEnums.PlayerColor, p_units: Array, p_result: GameEnums.UnitType, p_location: String) -> Order:
	var order = Order.new()
	order.order_type = GameEnums.OrderType.EXCHANGE
	order.player = p_player
	order.exchange_units = p_units
	order.exchange_result = p_result
	order.exchange_location = p_location
	return order

static func create_launch(p_player: GameEnums.PlayerColor, p_from: String, p_to: String) -> Order:
	var order = Order.new()
	order.order_type = GameEnums.OrderType.LAUNCH
	order.player = p_player
	order.unit_type = GameEnums.UnitType.MEGA_MISSILE
	order.from_sector = p_from
	order.to_sector = p_to
	return order

static func create_missile_exchange(p_player: GameEnums.PlayerColor, p_sacrificed: Array, p_location: String) -> Order:
	var order = Order.new()
	order.order_type = GameEnums.OrderType.EXCHANGE
	order.player = p_player
	order.exchange_units = p_sacrificed
	order.exchange_result = GameEnums.UnitType.MEGA_MISSILE
	order.exchange_location = p_location
	order.unit_type = GameEnums.UnitType.MEGA_MISSILE  # marker for description
	return order

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
