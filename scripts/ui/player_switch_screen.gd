extends ColorRect
class_name PlayerSwitchScreen

## Écran de transition entre joueurs en mode hotseat.

signal player_ready

var _label: Label
var _sub_label: Label
var _button: Button

func _ready() -> void:
	color = Color(0.05, 0.07, 0.14, 0.97)
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_STOP

	var center := CenterContainer.new()
	center.anchors_preset = Control.PRESET_FULL_RECT
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	# Icône
	var icon := Label.new()
	icon.text = "⚔"
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 48)
	vbox.add_child(icon)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 32)
	vbox.add_child(_label)

	_sub_label = Label.new()
	_sub_label.text = "Programmez vos 5 ordres avant la fin du sablier!"
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.add_theme_font_size_override("font_size", 14)
	_sub_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	vbox.add_child(_sub_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)

	_button = Button.new()
	_button.text = "C'est parti!"
	_button.custom_minimum_size = Vector2(200, 50)
	_button.pressed.connect(_on_ready_pressed)
	vbox.add_child(_button)

	# Style du bouton
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.5, 0.3)
	style.border_color = Color(0.3, 0.7, 0.4)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	_button.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.bg_color = Color(0.25, 0.6, 0.35)
	_button.add_theme_stylebox_override("hover", hover)

	_button.add_theme_font_size_override("font_size", 18)
	_button.add_theme_color_override("font_color", Color.WHITE)

func show_for_player(player_color: GameEnums.PlayerColor) -> void:
	var color_name := _get_color_name(player_color)
	var player_clr := GameEnums.get_player_color(player_color)

	_label.text = "Joueur %s" % color_name
	_label.add_theme_color_override("font_color", player_clr)
	visible = true

func _on_ready_pressed() -> void:
	visible = false
	player_ready.emit()

func _get_color_name(c: GameEnums.PlayerColor) -> String:
	match c:
		GameEnums.PlayerColor.GREEN: return "Vert"
		GameEnums.PlayerColor.BLUE: return "Bleu"
		GameEnums.PlayerColor.YELLOW: return "Jaune"
		GameEnums.PlayerColor.RED: return "Rouge"
		_: return "?"
