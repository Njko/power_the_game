extends Node2D
class_name UnitRenderer

## Affiche les unités sur le plateau en utilisant des symboles textuels.

var board_renderer: BoardRenderer
var game_state: GameState

# Symboles pour chaque type d'unité
const UNIT_SYMBOLS := {
	GameEnums.UnitType.FLAG: "⚑",
	GameEnums.UnitType.POWER: "★",
	GameEnums.UnitType.SOLDIER: "♟",
	GameEnums.UnitType.TANK: "▣",
	GameEnums.UnitType.FIGHTER: "✈",
	GameEnums.UnitType.DESTROYER: "⛵",
	GameEnums.UnitType.REGIMENT: "♟♟",
	GameEnums.UnitType.HEAVY_TANK: "▣▣",
	GameEnums.UnitType.BOMBER: "✈✈",
	GameEnums.UnitType.CRUISER: "⛵⛵",
	GameEnums.UnitType.MEGA_MISSILE: "☢",
}

func update_display() -> void:
	queue_redraw()

func _draw() -> void:
	if game_state == null or board_renderer == null:
		return

	# Parcourir tous les secteurs et dessiner les unités présentes
	for sector_id in board_renderer.sector_positions:
		var sector: Sector = game_state.board.get_sector(sector_id)
		if sector == null or sector.units.is_empty():
			continue

		var base_pos: Vector2 = board_renderer.sector_positions[sector_id]
		_draw_units_at_sector(sector.units, base_pos)

func _draw_units_at_sector(units: Array, base_pos: Vector2) -> void:
	# Grouper les unités par propriétaire
	var by_player: Dictionary = {}
	for unit in units:
		if unit.owner not in by_player:
			by_player[unit.owner] = []
		by_player[unit.owner].append(unit)

	var player_count := by_player.size()
	var player_idx := 0

	for player_color in by_player:
		var player_units: Array = by_player[player_color]
		var color: Color = GameEnums.get_player_color(player_color)

		# Décaler si plusieurs joueurs sur le même secteur
		var offset := Vector2.ZERO
		if player_count > 1:
			var angle := TAU * player_idx / player_count
			offset = Vector2.from_angle(angle) * 12

		# Grouper par type d'unité
		var by_type: Dictionary = {}
		for unit in player_units:
			if unit.unit_type not in by_type:
				by_type[unit.unit_type] = 0
			by_type[unit.unit_type] += 1

		# Afficher un résumé compact
		var text_lines: Array[String] = []
		for unit_type in by_type:
			var count: int = by_type[unit_type]
			var abbr := GameEnums.get_unit_abbreviation(unit_type)
			if count > 1:
				text_lines.append("%dx%s" % [count, abbr])
			else:
				text_lines.append(abbr)

		var display_text := " ".join(text_lines)
		var font := ThemeDB.fallback_font
		var font_size := 10

		# Fond coloré pour la lisibilité
		var text_size := font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var text_pos := base_pos + offset - text_size / 2
		var bg_rect := Rect2(text_pos - Vector2(2, font_size * 0.2), text_size + Vector2(4, 4))
		draw_rect(bg_rect, color.darkened(0.3))
		draw_string(font, text_pos + Vector2(0, font_size * 0.7), display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

		player_idx += 1
