extends Node2D
class_name UnitRenderer

## Affiche les unités sur le plateau avec des badges colorés.
## Chaque joueur a un badge compact montrant ses unités par secteur.

var board_renderer: BoardRenderer
var game_state: GameState

# Icônes par type d'unité (caractères Unicode)
const ICONS := {
	GameEnums.UnitType.FLAG: "F",
	GameEnums.UnitType.POWER: "P",
	GameEnums.UnitType.SOLDIER: "S",
	GameEnums.UnitType.TANK: "T",
	GameEnums.UnitType.FIGHTER: "C",
	GameEnums.UnitType.DESTROYER: "D",
	GameEnums.UnitType.REGIMENT: "R",
	GameEnums.UnitType.HEAVY_TANK: "A",
	GameEnums.UnitType.BOMBER: "B",
	GameEnums.UnitType.CRUISER: "Cr",
	GameEnums.UnitType.MEGA_MISSILE: "M",
}

const BADGE_HEIGHT := 16.0
const BADGE_PADDING := 3.0
const BADGE_FONT_SIZE := 10
const POWER_FONT_SIZE := 8

func update_display() -> void:
	queue_redraw()

func _draw() -> void:
	if game_state == null or board_renderer == null:
		return

	for sector_id in board_renderer.sector_positions:
		var sector: Sector = game_state.board.get_sector(sector_id)
		if sector == null or sector.units.is_empty():
			continue
		var base_pos: Vector2 = board_renderer.sector_positions[sector_id]
		_draw_units_at_sector(sector, base_pos)

func _draw_units_at_sector(sector: Sector, base_pos: Vector2) -> void:
	# Grouper par joueur
	var by_player: Dictionary = {}
	for unit in sector.units:
		if unit.owner not in by_player:
			by_player[unit.owner] = []
		by_player[unit.owner].append(unit)

	var player_count := by_player.size()
	var badge_idx := 0

	for player_color in by_player:
		var units: Array = by_player[player_color]
		var color: Color = GameEnums.get_player_color(player_color)

		# Construire le texte du badge
		var badge_text := _build_badge_text(units)
		var total_power := _calc_total_power(units)

		# Position du badge (empilé verticalement si plusieurs joueurs)
		var y_offset := (badge_idx - player_count / 2.0 + 0.5) * (BADGE_HEIGHT + 2)
		var badge_pos := base_pos + Vector2(0, y_offset)

		_draw_badge(badge_pos, badge_text, total_power, color)
		badge_idx += 1

func _build_badge_text(units: Array) -> String:
	var by_type: Dictionary = {}
	for unit in units:
		var icon: String = ICONS.get(unit.unit_type, "?")
		if icon not in by_type:
			by_type[icon] = 0
		by_type[icon] += 1

	var parts := []
	for icon in by_type:
		var count: int = by_type[icon]
		if count > 1:
			parts.append("%d%s" % [count, icon])
		else:
			parts.append(icon)

	return " ".join(parts)

func _calc_total_power(units: Array) -> int:
	var total := 0
	for unit in units:
		total += unit.get_power()
	return total

func _draw_badge(pos: Vector2, text: String, total_power: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FONT_SIZE)

	# Ajouter l'indicateur de puissance
	var power_text := ""
	if total_power > 0:
		power_text = " %d" % total_power
	var power_size := font.get_string_size(power_text, HORIZONTAL_ALIGNMENT_LEFT, -1, POWER_FONT_SIZE)

	var badge_width := text_size.x + power_size.x + BADGE_PADDING * 2 + 2
	var badge_height := BADGE_HEIGHT

	var badge_rect := Rect2(
		pos - Vector2(badge_width / 2, badge_height / 2),
		Vector2(badge_width, badge_height))

	# Ombre
	var shadow_rect := Rect2(badge_rect.position + Vector2(1, 1), badge_rect.size)
	draw_rect(shadow_rect, Color(0, 0, 0, 0.4))

	# Fond du badge
	draw_rect(badge_rect, color.darkened(0.35))

	# Barre de couleur à gauche
	var stripe := Rect2(badge_rect.position, Vector2(3, badge_height))
	draw_rect(stripe, color)

	# Texte des unités
	var text_pos := Vector2(
		badge_rect.position.x + BADGE_PADDING + 3,
		badge_rect.position.y + badge_height * 0.72)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FONT_SIZE, Color.WHITE)

	# Texte de puissance (plus petit, en jaune)
	if power_text != "":
		var power_pos := Vector2(
			text_pos.x + text_size.x + 2,
			badge_rect.position.y + badge_height * 0.68)
		draw_string(font, power_pos, power_text, HORIZONTAL_ALIGNMENT_LEFT, -1, POWER_FONT_SIZE, Color(1.0, 0.9, 0.4, 0.8))
