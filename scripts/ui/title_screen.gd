extends Control

## Écran titre du jeu Power.
## Étape 1: choisir le mode (solo vs IA / hotseat multijoueur)
## Étape 2: choisir le nombre de joueurs

signal game_start_requested(num_players: int, human_color: GameEnums.PlayerColor, is_solo: bool)

var _is_solo := true

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	# Fond
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.12, 0.22)
	bg.anchors_preset = Control.PRESET_FULL_RECT
	add_child(bg)

	var center := CenterContainer.new()
	center.anchors_preset = Control.PRESET_FULL_RECT
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	# Titre
	var title := Label.new()
	title.text = "POWER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.0))
	vbox.add_child(title)

	# Sous-titre
	var subtitle := Label.new()
	subtitle.text = "Jeu de Stratégie Militaire"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	vbox.add_child(subtitle)

	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(400, 20)
	vbox.add_child(sep)

	# Mode solo
	var solo_label := Label.new()
	solo_label.text = "Solo contre l'IA"
	solo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	solo_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(solo_label)

	var solo_box := HBoxContainer.new()
	solo_box.alignment = BoxContainer.ALIGNMENT_CENTER
	solo_box.add_theme_constant_override("separation", 15)
	vbox.add_child(solo_box)

	# Boutons solo: 1 vs 1 IA, 1 vs 2 IA, 1 vs 3 IA
	for n in [2, 3, 4]:
		var btn := Button.new()
		btn.text = "1 vs %d IA" % (n - 1)
		btn.custom_minimum_size = Vector2(130, 45)
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(_on_solo_selected.bind(n))
		solo_box.add_child(btn)

	var sep2 := HSeparator.new()
	sep2.custom_minimum_size = Vector2(400, 15)
	vbox.add_child(sep2)

	# Mode hotseat
	var hotseat_label := Label.new()
	hotseat_label.text = "Multijoueur local (hotseat)"
	hotseat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hotseat_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(hotseat_label)

	var hotseat_box := HBoxContainer.new()
	hotseat_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hotseat_box.add_theme_constant_override("separation", 15)
	vbox.add_child(hotseat_box)

	for n in [2, 3, 4]:
		var btn := Button.new()
		btn.text = "%d Joueurs" % n
		btn.custom_minimum_size = Vector2(130, 45)
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(_on_hotseat_selected.bind(n))
		hotseat_box.add_child(btn)

	var sep3 := HSeparator.new()
	sep3.custom_minimum_size = Vector2(400, 10)
	vbox.add_child(sep3)

	# Crédits
	var credits := Label.new()
	credits.text = "Inspiré du jeu de société Power (Spear's Games, 1981)"
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits.add_theme_font_size_override("font_size", 11)
	credits.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
	vbox.add_child(credits)

func _on_solo_selected(num_players: int) -> void:
	game_start_requested.emit(num_players, GameEnums.PlayerColor.GREEN, true)
	queue_free()

func _on_hotseat_selected(num_players: int) -> void:
	# En hotseat, pas de joueur IA → on passe NONE comme human_color
	# pour indiquer que tous les joueurs sont humains
	game_start_requested.emit(num_players, GameEnums.PlayerColor.NONE, false)
	queue_free()
