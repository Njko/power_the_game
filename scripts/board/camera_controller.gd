extends Node
class_name CameraController

## Contrôle l'orbite et le zoom de la caméra autour du plateau.
## Clic-droit + drag = rotation (azimuth + élévation)
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

var _is_orbiting := false

func _ready() -> void:
	_update_camera_position()

func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return

	# Clic droit: début/fin orbite
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_is_orbiting = event.pressed

		# Molette: zoom
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			distance = clampf(distance - ZOOM_SPEED, DISTANCE_MIN, DISTANCE_MAX)
			_update_camera_position()

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			distance = clampf(distance + ZOOM_SPEED, DISTANCE_MIN, DISTANCE_MAX)
			_update_camera_position()

	# Mouvement souris: orbite
	elif event is InputEventMouseMotion and _is_orbiting:
		azimuth -= event.relative.x * MOUSE_SENSITIVITY
		elevation = clampf(elevation + event.relative.y * MOUSE_SENSITIVITY, ELEVATION_MIN, ELEVATION_MAX)
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
