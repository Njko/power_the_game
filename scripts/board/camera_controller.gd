extends Node
class_name CameraController

## Contrôle l'orbite, le zoom et le panoramique de la caméra autour du plateau.
## Clic-droit + drag = rotation (azimuth + élévation)
## Clic-milieu + drag = panoramique (déplacement du target sur le plan XZ)
## Flèches du clavier = panoramique
## Molette = zoom (rapprocher/éloigner)

var camera: Camera3D
var target := Vector3.ZERO  # Centre du plateau

# Paramètres d'orbite
var azimuth := 0.0          # Angle horizontal (radians)
var elevation := deg_to_rad(60.0)  # Angle vertical (radians)
var distance := 10.0        # Distance au centre

# Limites
const ELEVATION_MIN := deg_to_rad(20.0)
const ELEVATION_MAX := deg_to_rad(85.0)
const DISTANCE_MIN := 4.0
const DISTANCE_MAX := 20.0
const MOUSE_SENSITIVITY := 0.005
const ZOOM_SPEED := 0.5
const PAN_SENSITIVITY := 0.01
const PAN_KEYBOARD_SPEED := 5.0

var _is_orbiting := false
var _is_panning := false

func _ready() -> void:
	pass

func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return

	# Clic droit: début/fin orbite
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_is_orbiting = event.pressed

		# Clic milieu: début/fin panoramique
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = event.pressed

		# Molette: zoom
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			distance = clampf(distance - ZOOM_SPEED, DISTANCE_MIN, DISTANCE_MAX)
			_update_camera_position()

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			distance = clampf(distance + ZOOM_SPEED, DISTANCE_MIN, DISTANCE_MAX)
			_update_camera_position()

	# Mouvement souris
	elif event is InputEventMouseMotion:
		if _is_orbiting:
			azimuth -= event.relative.x * MOUSE_SENSITIVITY
			elevation = clampf(elevation + event.relative.y * MOUSE_SENSITIVITY, ELEVATION_MIN, ELEVATION_MAX)
			_update_camera_position()
		elif _is_panning:
			_pan_camera(event.relative)

func _process(delta: float) -> void:
	if camera == null:
		return

	# Flèches du clavier: panoramique
	var pan_input := Vector2.ZERO
	if Input.is_action_pressed("ui_left"):
		pan_input.x -= 1.0
	if Input.is_action_pressed("ui_right"):
		pan_input.x += 1.0
	if Input.is_action_pressed("ui_up"):
		pan_input.y -= 1.0
	if Input.is_action_pressed("ui_down"):
		pan_input.y += 1.0

	if pan_input != Vector2.ZERO:
		var speed: float = PAN_KEYBOARD_SPEED * delta
		# Projeter sur le plan XZ relatif à l'azimuth
		var right := Vector3(cos(azimuth), 0, -sin(azimuth))
		var forward := Vector3(sin(azimuth), 0, cos(azimuth))
		target += right * pan_input.x * speed + forward * pan_input.y * speed
		_update_camera_position()

func _pan_camera(relative: Vector2) -> void:
	## Déplace le target sur le plan XZ en fonction du mouvement souris.
	var factor: float = distance * PAN_SENSITIVITY
	var right := Vector3(cos(azimuth), 0, -sin(azimuth))
	var forward := Vector3(sin(azimuth), 0, cos(azimuth))
	target += right * relative.x * factor + forward * relative.y * factor
	_update_camera_position()

func _update_camera_position() -> void:
	if camera == null:
		return
	# Position sphérique autour du target
	var x := distance * cos(elevation) * sin(azimuth)
	var y := distance * sin(elevation)
	var z := distance * cos(elevation) * cos(azimuth)
	camera.global_position = target + Vector3(x, y, z)
	camera.look_at(target, Vector3.UP)
