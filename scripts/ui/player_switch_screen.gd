extends ColorRect
class_name PlayerSwitchScreen

## Écran de transition entre joueurs en mode hotseat.
## Masque le plateau et demande au prochain joueur de prendre place.

signal player_ready

var _label: Label
var _button: Button

func _ready() -> void:
	color = Color(0.1, 0.1, 0.15, 0.95)
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_STOP

	var center := CenterContainer.new()
	center.anchors_preset = Control.PRESET_FULL_RECT
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(_label)

	_button = Button.new()
	_button.text = "Je suis prêt!"
	_button.add_theme_font_size_override("font_size", 20)
	_button.custom_minimum_size = Vector2(200, 50)
	_button.pressed.connect(_on_ready_pressed)
	vbox.add_child(_button)

func show_for_player(player_color: GameEnums.PlayerColor) -> void:
	var color_name := _get_color_name(player_color)
	var player_clr := GameEnums.get_player_color(player_color)

	_label.text = "Au tour du joueur %s\nde programmer ses ordres" % color_name
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
