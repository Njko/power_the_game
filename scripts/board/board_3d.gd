extends Node3D
class_name Board3D

## Gère la scène 3D du plateau: SubViewport pour le rendu 2D du board,
## MeshInstance3D pour le plan 3D, et Camera3D pour la perspective.
## Fournit les conversions de coordonnées grille ↔ 3D ↔ écran.

signal sector_clicked(sector_id: String)
signal sector_clicked_with_pos(sector_id: String, screen_pos: Vector2)
signal sector_hovered(sector_id: String)

# Le plateau logique va de (0, 0) à (8, 8) en coordonnées grille.
# En 3D, on centre tout à l'origine: grid (4, 4) → Vector3(0, 0, 0).
const GRID_CENTER := Vector2(4.0, 4.0)
const SCALE_3D := 1.0  # 1 unité 3D par cellule de grille

# Hauteurs par type de secteur (en unités 3D)
const HEIGHT_SEA := -0.08
const HEIGHT_COASTAL := 0.0
const HEIGHT_LAND := 0.08
const HEIGHT_HILL := 0.22
const HEIGHT_ISLAND := 0.15
const HEIGHT_HQ := 0.06

# SubViewport pour le rendu 2D du board
var board_viewport: SubViewport
var board_renderer: BoardRenderer

# Scène 3D
var board_mesh: MeshInstance3D
var camera: Camera3D

# Référence vers le board_data pour le hit test
var board_data: BoardData:
	set(value):
		board_data = value
		if board_data != null:
			_build_grid_positions()
			_build_terrain_mesh()

# Positions grille de tous les secteurs (reconverties depuis les pixels du BoardRenderer)
var _grid_positions: Dictionary = {}  # sector_id -> Vector2 (grille logique)
var _grid_rects: Dictionary = {}  # sector_id -> Rect2 (rectangle en coordonnées grille)

var _hovered_sector: String = ""

func _ready() -> void:
	_setup_subviewport()
	_setup_3d_scene()
	_build_grid_positions()
	# Le mesh terrain sera construit quand board_data est assigné
	# En attendant, on garde un plan plat
	_build_flat_mesh()

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
	# Mesh 3D avec relief (hauteurs par secteur)
	board_mesh = MeshInstance3D.new()
	add_child(board_mesh)

	# Matériau avec la texture du SubViewport
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = board_viewport.get_texture()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	board_mesh.material_override = mat

	# Caméra
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 50.0
	add_child(camera)

func _build_flat_mesh() -> void:
	## Mesh plat par défaut avant que board_data soit disponible.
	var plane := PlaneMesh.new()
	plane.size = Vector2(1024.0 / 55.0, 1024.0 / 55.0)
	board_mesh.mesh = plane

func _build_terrain_mesh() -> void:
	## Construit un ArrayMesh avec relief basé sur le type de chaque secteur.
	## Appelé quand board_data est assigné.
	var plane_size: float = 1024.0 / 55.0  # ~18.618 unités
	var half := plane_size / 2.0
	var subdivs := 90  # Nombre de subdivisions (~10 par cellule)
	var step := plane_size / subdivs

	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	# Créer la grille de vertices avec hauteurs
	for iz in range(subdivs + 1):
		for ix in range(subdivs + 1):
			var x: float = -half + ix * step
			var z: float = -half + iz * step
			var u: float = float(ix) / float(subdivs)
			var v: float = float(iz) / float(subdivs)

			# Convertir UV en coordonnées grille (via pixels du SubViewport)
			var pixel_x: float = u * 1024.0
			var pixel_y: float = v * 1024.0
			var grid_pos := Vector2(
				(pixel_x - BoardRenderer.BOARD_ORIGIN.x) / BoardRenderer.CELL_SIZE,
				(pixel_y - BoardRenderer.BOARD_ORIGIN.y) / BoardRenderer.CELL_SIZE)
			var height: float = _get_height_at_grid(grid_pos)

			vertices.append(Vector3(x, height, z))
			uvs.append(Vector2(u, v))

	# Créer les triangles (2 par quad, counter-clockwise vu du dessus)
	var row_size: int = subdivs + 1
	for iz in range(subdivs):
		for ix in range(subdivs):
			var i: int = iz * row_size + ix
			# Triangle 1 (CCW vu du dessus = face vers Y+)
			indices.append(i)
			indices.append(i + 1)
			indices.append(i + row_size)
			# Triangle 2
			indices.append(i + 1)
			indices.append(i + row_size + 1)
			indices.append(i + row_size)

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vertices
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	board_mesh.mesh = mesh

func _get_height_at_grid(grid_pos: Vector2) -> float:
	## Retourne la hauteur 3D pour une position grille, avec lissage aux bordures.
	# Trouver le secteur principal
	var main_sector := ""
	for sector_id in _grid_rects:
		var rect: Rect2 = _grid_rects[sector_id]
		if rect.has_point(grid_pos):
			main_sector = sector_id
			break

	if main_sector == "":
		return HEIGHT_SEA

	var main_height: float = _get_sector_height(main_sector)
	var main_rect: Rect2 = _grid_rects[main_sector]

	# Lissage : si on est près d'un bord, interpoler avec le secteur voisin
	var margin := 0.15  # Zone de transition (en unités grille)
	var dist_left: float = grid_pos.x - main_rect.position.x
	var dist_right: float = main_rect.end.x - grid_pos.x
	var dist_top: float = grid_pos.y - main_rect.position.y
	var dist_bottom: float = main_rect.end.y - grid_pos.y
	var min_dist: float = minf(minf(dist_left, dist_right), minf(dist_top, dist_bottom))

	if min_dist < margin:
		# Trouver le secteur voisin dans la direction la plus proche
		var probe := grid_pos
		if min_dist == dist_left:
			probe = Vector2(grid_pos.x - margin, grid_pos.y)
		elif min_dist == dist_right:
			probe = Vector2(grid_pos.x + margin, grid_pos.y)
		elif min_dist == dist_top:
			probe = Vector2(grid_pos.x, grid_pos.y - margin)
		else:
			probe = Vector2(grid_pos.x, grid_pos.y + margin)

		var neighbor_height: float = HEIGHT_SEA
		for sector_id in _grid_rects:
			if sector_id == main_sector:
				continue
			if _grid_rects[sector_id].has_point(probe):
				neighbor_height = _get_sector_height(sector_id)
				break

		# Interpolation douce
		var t: float = min_dist / margin
		return lerpf(neighbor_height, main_height, t * t * (3.0 - 2.0 * t))  # smoothstep

	return main_height

func _get_sector_height(sector_id: String) -> float:
	## Retourne la hauteur d'un secteur selon son type.
	if board_data == null:
		return 0.0
	var sector: Sector = board_data.get_sector(sector_id)
	if sector == null:
		return HEIGHT_SEA

	match sector.sector_type:
		GameEnums.SectorType.SEA:
			return HEIGHT_SEA
		GameEnums.SectorType.COASTAL:
			return HEIGHT_COASTAL
		GameEnums.SectorType.ISLAND:
			return HEIGHT_ISLAND
		GameEnums.SectorType.HQ:
			return HEIGHT_HQ
		GameEnums.SectorType.LAND:
			# Secteur 4 = colline
			var num := sector_id.right(1).to_int() if sector_id.length() > 1 else -1
			if num == 4:
				return HEIGHT_HILL
			return HEIGHT_LAND
		_:
			return 0.0


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
	# Construire les rectangles grille depuis les sector_rects pixel du renderer
	for sector_id in board_renderer.sector_rects:
		var pixel_rect: Rect2 = board_renderer.sector_rects[sector_id]
		var grid_origin := (pixel_rect.position - BoardRenderer.BOARD_ORIGIN) / BoardRenderer.CELL_SIZE
		var grid_size := pixel_rect.size / BoardRenderer.CELL_SIZE
		_grid_rects[sector_id] = Rect2(grid_origin, grid_size)

# ===== CONVERSIONS DE COORDONNÉES =====

const GRID_OFFSET := 0.5  # Décalage entre centre mesh (grid 4.5) et GRID_CENTER (4.0)

func grid_to_3d(grid_pos: Vector2, with_height := true) -> Vector3:
	## Convertit une position grille en position 3D monde.
	var y: float = _get_height_at_grid(grid_pos) if with_height else 0.0
	return Vector3(
		(grid_pos.x - GRID_CENTER.x - GRID_OFFSET) * SCALE_3D, y,
		(grid_pos.y - GRID_CENTER.y - GRID_OFFSET) * SCALE_3D)

func world_to_grid(world_pos: Vector3) -> Vector2:
	## Convertit une position 3D monde en position grille.
	return Vector2(
		world_pos.x / SCALE_3D + GRID_CENTER.x + GRID_OFFSET,
		world_pos.z / SCALE_3D + GRID_CENTER.y + GRID_OFFSET)

func get_sector_screen_position(sector_id: String) -> Vector2:
	## Retourne la position écran d'un secteur (projetée depuis le 3D).
	if sector_id not in _grid_positions:
		return Vector2.ZERO
	var grid_pos: Vector2 = _grid_positions[sector_id]
	# Utiliser la hauteur connue du secteur directement (plus fiable que _get_height_at_grid)
	var height: float = _get_sector_height(sector_id)
	var world_pos := Vector3(
		(grid_pos.x - GRID_CENTER.x - GRID_OFFSET) * SCALE_3D, height,
		(grid_pos.y - GRID_CENTER.y - GRID_OFFSET) * SCALE_3D)
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

	# Tester l'intersection à plusieurs hauteurs pour trouver le bon secteur
	# (les secteurs sont à des hauteurs différentes)
	var best_id := ""
	var best_dist := 0.8

	# Test rapide: intersections aux différentes hauteurs possibles
	var heights_to_test := [HEIGHT_HILL, HEIGHT_ISLAND, HEIGHT_LAND, HEIGHT_HQ, HEIGHT_COASTAL, HEIGHT_SEA]
	for test_height in heights_to_test:
		if abs(ray_dir.y) < 0.001:
			continue
		var t: float = (test_height - ray_origin.y) / ray_dir.y
		if t < 0:
			continue
		var hit_point := ray_origin + ray_dir * t
		var grid_pos := world_to_grid(hit_point)

		# Chercher dans les rectangles grille
		for sector_id in _grid_rects:
			var rect: Rect2 = _grid_rects[sector_id]
			if rect.has_point(grid_pos):
				var sector_height: float = _get_sector_height(sector_id)
				if absf(sector_height - test_height) < 0.05:
					return sector_id

	# Fallback: intersection Y=0 + secteur le plus proche
	if abs(ray_dir.y) >= 0.001:
		var t: float = -ray_origin.y / ray_dir.y
		if t > 0:
			var hit_point := ray_origin + ray_dir * t
			var grid_pos := world_to_grid(hit_point)
			for sector_id in _grid_rects:
				var rect: Rect2 = _grid_rects[sector_id]
				if rect.has_point(grid_pos):
					return sector_id
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
				sector_clicked_with_pos.emit(clicked, event.position)
