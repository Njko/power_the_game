extends Control

## Écran titre du jeu Power - version polie.

signal game_start_requested(num_players: int, human_color: GameEnums.PlayerColor, is_solo: bool)

func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	_build_ui()

func _build_ui() -> void:
	# Fond avec dégradé simulé
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.16)
	bg.anchors_preset = Control.PRESET_FULL_RECT
	add_child(bg)

	# Lignes décoratives de fond
	var deco := Control.new()
	deco.anchors_preset = Control.PRESET_FULL_RECT
	add_child(deco)

	var center := CenterContainer.new()
	center.anchors_preset = Control.PRESET_FULL_RECT
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	center.add_child(vbox)

	# Titre principal
	var title := Label.new()
	title.text = "P O W E R"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 80)
	title.add_theme_color_override("font_color", Color(1.0, 0.65, 0.1))
	vbox.add_child(title)

	# Ligne dorée
	var line := ColorRect.new()
	line.color = Color(1.0, 0.7, 0.2, 0.6)
	line.custom_minimum_size = Vector2(400, 2)
	var line_center := CenterContainer.new()
	line_center.add_child(line)
	vbox.add_child(line_center)

	# Sous-titre
	var subtitle := Label.new()
	subtitle.text = "Jeu de Strategie Militaire"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.65, 0.65, 0.75))
	vbox.add_child(subtitle)

	_add_spacer(vbox, 8)

	# Description
	var desc := Label.new()
	desc.text = "Programmez vos ordres. Deployez vos armees.\nCapturez les drapeaux ennemis. Aucun hasard."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.50, 0.50, 0.58))
	vbox.add_child(desc)

	_add_spacer(vbox, 16)

	# --- Solo ---
	_add_section_title(vbox, "SOLO CONTRE L'IA", Color(0.4, 0.7, 1.0))

	var solo_box := HBoxContainer.new()
	solo_box.alignment = BoxContainer.ALIGNMENT_CENTER
	solo_box.add_theme_constant_override("separation", 12)
	vbox.add_child(solo_box)

	_add_game_button(solo_box, "1 vs 1", "Duel", Color(0.3, 0.6, 0.9), _on_solo.bind(2))
	_add_game_button(solo_box, "1 vs 2", "Classique", Color(0.3, 0.6, 0.9), _on_solo.bind(3))
	_add_game_button(solo_box, "1 vs 3", "Total", Color(0.3, 0.6, 0.9), _on_solo.bind(4))

	_add_spacer(vbox, 10)

	# --- Hotseat ---
	_add_section_title(vbox, "MULTIJOUEUR LOCAL", Color(0.9, 0.6, 0.3))

	var hot_box := HBoxContainer.new()
	hot_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hot_box.add_theme_constant_override("separation", 12)
	vbox.add_child(hot_box)

	_add_game_button(hot_box, "2", "Joueurs", Color(0.85, 0.55, 0.25), _on_hotseat.bind(2))
	_add_game_button(hot_box, "3", "Joueurs", Color(0.85, 0.55, 0.25), _on_hotseat.bind(3))
	_add_game_button(hot_box, "4", "Joueurs", Color(0.85, 0.55, 0.25), _on_hotseat.bind(4))

	_add_spacer(vbox, 20)

	# Crédits
	var credits := Label.new()
	credits.text = "Inspire du jeu de societe Power (Spear's Games, 1981)"
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits.add_theme_font_size_override("font_size", 10)
	credits.add_theme_color_override("font_color", Color(0.3, 0.3, 0.38))
	vbox.add_child(credits)

func _add_spacer(parent: Control, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	parent.add_child(spacer)

func _add_section_title(parent: Control, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color.darkened(0.1))
	parent.add_child(label)

func _add_game_button(parent: Control, main_text: String, sub_text: String,
		color: Color, callback: Callable) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(130, 55)
	btn.add_theme_font_size_override("font_size", 14)

	# Texte combiné
	btn.text = "%s\n%s" % [main_text, sub_text]
	btn.pressed.connect(callback)

	# Style
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.4)
	style.border_color = color.darkened(0.1)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.bg_color = color.darkened(0.2)
	hover.border_color = color
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := style.duplicate()
	pressed.bg_color = color.darkened(0.5)
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 0.9))

	parent.add_child(btn)

func _on_solo(num_players: int) -> void:
	game_start_requested.emit(num_players, GameEnums.PlayerColor.GREEN, true)
	queue_free()

func _on_hotseat(num_players: int) -> void:
	game_start_requested.emit(num_players, GameEnums.PlayerColor.NONE, false)
	queue_free()
