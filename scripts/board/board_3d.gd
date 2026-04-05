extends Node3D
class_name Board3D

## Gère la scène 3D du plateau: SubViewport pour le rendu 2D du board,
## MeshInstance3D pour le plan 3D, et Camera3D pour la perspective.
## Fournit les conversions de coordonnées grille ↔ 3D ↔ écran.

signal sector_clicked(sector_id: String)
signal sector_hovered(sector_id: String)

# Le plateau logique va de ~(-1, -1.5) à ~(9, 8.5) en coordonnées grille.
# En 3D, on centre tout à l'origine: grid (4, 3.5) → Vector3(0, 0, 0).
const GRID_CENTER := Vector2(4.0, 3.5)
const SCALE_3D := 1.0  # 1 unité 3D par cellule de grille

# SubViewport pour le rendu 2D du board
var board_viewport: SubViewport
var board_renderer: BoardRenderer

# Scène 3D
var board_mesh: MeshInstance3D
var camera: Camera3D

# Référence vers le board_data pour le hit test
var board_data: BoardData

# Positions grille de tous les secteurs (reconverties depuis les pixels du BoardRenderer)
var _grid_positions: Dictionary = {}  # sector_id -> Vector2 (grille logique)

var _hovered_sector: String = ""

func _ready() -> void:
	_setup_subviewport()
	_setup_3d_scene()
	_build_grid_positions()

func _setup_subviewport() -> void:
	board_viewport = SubViewport.new()
	board_viewport.size = Vector2i(1024, 1024)
	board_viewport.transparent_bg = false
	board_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	board_viewport.gui_disable_input = true  # Ne pas intercepter les clics
	board_viewport.handle_input_locally = true
	add_child(board_viewport)

	# Le BoardRenderer dessine dans ce SubViewport
	board_renderer = BoardRenderer.new()
	board_renderer.board_3d = self  # Back-reference pour la projection
	board_viewport.add_child(board_renderer)

func _setup_3d_scene() -> void:
	# Plan 3D horizontal (XZ) pour le plateau
	board_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	# 1 unité 3D = 1 cellule grille = CELL_SIZE pixels dans le SubViewport
	# → plane_size = viewport_size / CELL_SIZE = 1024/55 ≈ 18.618
	plane.size = Vector2(1024.0 / 55.0, 1024.0 / 55.0)
	board_mesh.mesh = plane
	add_child(board_mesh)

	# Matériau avec la texture du SubViewport
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = board_viewport.get_texture()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # Pas d'éclairage, couleurs fidèles
	board_mesh.material_override = mat

	# Caméra
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 50.0
	add_child(camera)


func get_all_sector_ids() -> Array:
	## Retourne tous les sector_ids connus.
	return _grid_positions.keys()

func _build_grid_positions() -> void:
	## Copie les positions grille du BoardRenderer (pixel) et les reconvertit en coordonnées grille.
	if board_renderer == null:
		return
	for sector_id in board_renderer.sector_positions:
		var pixel_pos: Vector2 = board_renderer.sector_positions[sector_id]
		# Inverse de la formule: pixel = BOARD_ORIGIN + grid * CELL_SIZE + CELL_SIZE/2
		var grid_pos := (pixel_pos - BoardRenderer.BOARD_ORIGIN - Vector2(BoardRenderer.CELL_SIZE / 2, BoardRenderer.CELL_SIZE / 2)) / BoardRenderer.CELL_SIZE
		_grid_positions[sector_id] = grid_pos

# ===== CONVERSIONS DE COORDONNÉES =====

func grid_to_3d(grid_pos: Vector2) -> Vector3:
	## Convertit une position grille en position 3D monde.
	return Vector3((grid_pos.x - GRID_CENTER.x) * SCALE_3D, 0.0, (grid_pos.y - GRID_CENTER.y) * SCALE_3D)

func world_to_grid(world_pos: Vector3) -> Vector2:
	## Convertit une position 3D monde en position grille.
	return Vector2(world_pos.x / SCALE_3D + GRID_CENTER.x, world_pos.z / SCALE_3D + GRID_CENTER.y)

func get_sector_screen_position(sector_id: String) -> Vector2:
	## Retourne la position écran d'un secteur (projetée depuis le 3D).
	if sector_id not in _grid_positions:
		return Vector2.ZERO
	var grid_pos: Vector2 = _grid_positions[sector_id]
	var world_pos := grid_to_3d(grid_pos)
	if camera == null or not camera.is_inside_tree():
		return Vector2.ZERO
	if not camera.is_current():
		return Vector2.ZERO
	return camera.unproject_position(world_pos)

func get_sector_screen_scale(sector_id: String) -> float:
	## Retourne un facteur d'échelle basé sur la distance caméra (pour les sprites).
	if sector_id not in _grid_positions or camera == null:
		return 1.0
	if not camera.is_inside_tree() or not camera.is_current():
		return 1.0
	var grid_pos: Vector2 = _grid_positions[sector_id]
	var world_pos := grid_to_3d(grid_pos)
	var dist := camera.global_position.distance_to(world_pos)
	# Référence: distance ~10 unités = scale 1.0. Min 0.5 pour rester lisible.
	return clampf(10.0 / dist, 0.5, 2.0)

# ===== HIT DETECTION =====

func screen_to_board_sector(screen_pos: Vector2) -> String:
	## Raycast depuis la caméra vers le plan Y=0, retourne le sector_id le plus proche.
	if camera == null:
		return ""
	if not camera.is_inside_tree() or not camera.is_current():
		return ""
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)

	# Intersection avec le plan Y=0
	if abs(ray_dir.y) < 0.001:
		return ""  # Rayon parallèle au plan
	var t := -ray_origin.y / ray_dir.y
	if t < 0:
		return ""  # Derrière la caméra
	var hit_point := ray_origin + ray_dir * t

	# Convertir en coordonnées grille
	var grid_pos := world_to_grid(hit_point)

	# Trouver le secteur le plus proche (distance < 0.8 cellule pour faciliter le clic)
	var best_id := ""
	var best_dist := 0.8
	for sector_id in _grid_positions:
		var sector_grid: Vector2 = _grid_positions[sector_id]
		var dist := grid_pos.distance_to(sector_grid)
		if dist < best_dist:
			best_dist = dist
			best_id = sector_id
	return best_id

# ===== INPUT =====

func _unhandled_input(event: InputEvent) -> void:
	# Ne pas intercepter le clic droit (réservé à la caméra)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return

	if event is InputEventMouseMotion:
		var new_hovered := screen_to_board_sector(event.position)
		if new_hovered != _hovered_sector:
			_hovered_sector = new_hovered
			if _hovered_sector != "":
				sector_hovered.emit(_hovered_sector)
			# Mettre à jour le highlight sur le board renderer
			board_renderer.hovered_sector = _hovered_sector
			board_renderer.queue_redraw()

	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var clicked := screen_to_board_sector(event.position)
			if clicked != "":
				board_renderer.selected_sector = clicked
				board_renderer.queue_redraw()
				sector_clicked.emit(clicked)
