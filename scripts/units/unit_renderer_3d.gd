extends Node3D

## Rendu 3D des unités sur le plateau.
## Remplace l'ancien UnitRenderer 2D par des MeshInstance3D positionnées
## directement sur le terrain 3D avec des silhouettes militaires.

var board_3d: Board3D
var board_renderer  # Compatibilité avec l'ancien UnitRenderer (non utilisé en 3D)
var game_state: GameState
var selected_unit: UnitData

const UNIT_SCALE := 0.15       # Échelle de base des pions
const ELITE_FACTOR := 1.3      # Facteur pour unités élite
const SPACING := 0.3           # Espacement entre pions dans un secteur
const MAX_PER_ROW := 3

# Cache des meshes par unité
var _unit_nodes: Dictionary = {}  # UnitData -> Node3D
var _unit_positions_3d: Array = []  # Pour hit-detection : {pos: Vector3, unit: UnitData, screen_pos: Vector2}

func update_display() -> void:
	_sync_units()
	_position_units()

func _process(_delta: float) -> void:
	# Mettre à jour les positions écran pour la détection de clic
	if board_3d and board_3d.camera and board_3d.camera.is_inside_tree():
		_update_screen_positions()

func _sync_units() -> void:
	## Synchronise les meshes 3D avec l'état du jeu.
	if game_state == null or game_state.board == null:
		return

	# Collecter toutes les unités actuelles
	var current_units: Dictionary = {}
	for sector_id in game_state.board.sectors:
		var sector: Sector = game_state.board.get_sector(sector_id)
		if sector == null:
			continue
		for unit in sector.units:
			current_units[unit] = true

	# Supprimer les meshes d'unités disparues
	var to_remove: Array = []
	for unit in _unit_nodes:
		if unit not in current_units:
			to_remove.append(unit)
	for unit in to_remove:
		_unit_nodes[unit].queue_free()
		_unit_nodes.erase(unit)

	# Créer les meshes pour les nouvelles unités
	for unit in current_units:
		if unit not in _unit_nodes:
			var mesh_node: Node3D = _create_unit_mesh(unit)
			add_child(mesh_node)
			_unit_nodes[unit] = mesh_node

	# Mettre à jour la sélection visuelle
	for unit in _unit_nodes:
		_set_selection(_unit_nodes[unit], unit == selected_unit)

func _position_units() -> void:
	## Positionne chaque unité au bon endroit sur le terrain.
	if game_state == null or board_3d == null:
		return

	_unit_positions_3d.clear()

	for sector_id in game_state.board.sectors:
		var sector: Sector = game_state.board.get_sector(sector_id)
		if sector == null or sector.units.is_empty():
			continue

		# Position 3D du centre du secteur (hauteur directe, sans lissage)
		var grid_pos: Vector2 = board_3d._grid_positions.get(sector_id, Vector2.ZERO)
		var height: float = board_3d._get_sector_height(sector_id)
		var base_pos := Vector3(
			(grid_pos.x - Board3D.GRID_CENTER.x) * Board3D.SCALE_3D, height,
			(grid_pos.y - Board3D.GRID_CENTER.y) * Board3D.SCALE_3D)

		var units: Array = sector.units
		var count: int = units.size()
		var cols: int = mini(count, MAX_PER_ROW)
		var rows: int = ceili(float(count) / cols)
		var start_x: float = -(cols - 1) * SPACING * 0.5
		var start_z: float = -(rows - 1) * SPACING * 0.5

		for i in range(count):
			var unit: UnitData = units[i]
			if unit not in _unit_nodes:
				continue
			var col: int = i % cols
			var row: int = i / cols
			var offset := Vector3(start_x + col * SPACING, 0, start_z + row * SPACING)
			var pos := base_pos + offset
			_unit_nodes[unit].position = pos
			_unit_positions_3d.append({"pos": pos, "unit": unit})

func _update_screen_positions() -> void:
	## Met à jour les positions écran pour la détection de clic.
	if board_3d == null or board_3d.camera == null:
		return
	for entry in _unit_positions_3d:
		entry["screen_pos"] = board_3d.camera.unproject_position(entry["pos"])

func get_unit_at_screen_pos(screen_pos: Vector2) -> UnitData:
	## Retourne l'unité la plus proche d'une position écran.
	var best_unit: UnitData = null
	var best_dist := 30.0  # Rayon de détection en pixels
	for entry in _unit_positions_3d:
		if "screen_pos" not in entry:
			continue
		var dist: float = screen_pos.distance_to(entry["screen_pos"])
		if dist < best_dist:
			best_dist = dist
			best_unit = entry["unit"]
	return best_unit

func queue_redraw() -> void:
	## Compatibilité avec l'ancien UnitRenderer.
	update_display()

# ===== CRÉATION DES MESHES =====

func _create_unit_mesh(unit: UnitData) -> Node3D:
	## Crée le mesh 3D composite pour une unité.
	var root := Node3D.new()
	var color: Color = GameEnums.get_player_color(unit.owner)

	match unit.unit_type:
		GameEnums.UnitType.SOLDIER:
			_build_soldier(root, color, 1.0)
		GameEnums.UnitType.REGIMENT:
			_build_soldier(root, color, ELITE_FACTOR)
		GameEnums.UnitType.TANK:
			_build_tank(root, color, 1.0)
		GameEnums.UnitType.HEAVY_TANK:
			_build_tank(root, color, ELITE_FACTOR)
		GameEnums.UnitType.FIGHTER:
			_build_fighter(root, color, 1.0)
		GameEnums.UnitType.BOMBER:
			_build_bomber(root, color, 1.0)
		GameEnums.UnitType.DESTROYER:
			_build_ship(root, color, 1.0)
		GameEnums.UnitType.CRUISER:
			_build_ship(root, color, ELITE_FACTOR)
		GameEnums.UnitType.FLAG:
			_build_flag(root, color)
		GameEnums.UnitType.POWER:
			_build_power(root)
		GameEnums.UnitType.MEGA_MISSILE:
			_build_missile(root, color)
		_:
			_build_soldier(root, color, 1.0)

	root.scale = Vector3.ONE * UNIT_SCALE
	return root

func _make_mat(color: Color, metallic := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = 0.7
	return mat

func _add_mesh(parent: Node3D, mesh: Mesh, mat: StandardMaterial3D, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	if rot != Vector3.ZERO:
		inst.rotation_degrees = rot
	inst.cast_shadow = MeshInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(inst)
	return inst

func _build_soldier(root: Node3D, color: Color, scale_f: float) -> void:
	var mat := _make_mat(color)
	var dark := _make_mat(color.darkened(0.3))
	var s := scale_f

	# Corps (cylindre)
	var body := CylinderMesh.new()
	body.top_radius = 0.25 * s
	body.bottom_radius = 0.3 * s
	body.height = 1.0 * s
	_add_mesh(root, body, mat, Vector3(0, 0.5 * s, 0))

	# Tête (sphère)
	var head := SphereMesh.new()
	head.radius = 0.22 * s
	head.height = 0.44 * s
	_add_mesh(root, head, mat, Vector3(0, 1.1 * s, 0))

	# Casque (cylindre aplati)
	var helmet := CylinderMesh.new()
	helmet.top_radius = 0.15 * s
	helmet.bottom_radius = 0.28 * s
	helmet.height = 0.12 * s
	_add_mesh(root, helmet, dark, Vector3(0, 1.3 * s, 0))

	# Fusil (cylindre fin, diagonal)
	var rifle := CylinderMesh.new()
	rifle.top_radius = 0.03 * s
	rifle.bottom_radius = 0.03 * s
	rifle.height = 0.9 * s
	_add_mesh(root, rifle, dark, Vector3(0.2 * s, 0.6 * s, 0), Vector3(0, 0, -30))

func _build_tank(root: Node3D, color: Color, scale_f: float) -> void:
	var mat := _make_mat(color)
	var dark := _make_mat(color.darkened(0.3))
	var metal := _make_mat(Color(0.4, 0.4, 0.4), 0.5)
	var s := scale_f

	# Caisse (boîte)
	var hull := BoxMesh.new()
	hull.size = Vector3(0.8 * s, 0.3 * s, 1.0 * s)
	_add_mesh(root, hull, mat, Vector3(0, 0.15 * s, 0))

	# Chenilles (2 boîtes sombres)
	var track := BoxMesh.new()
	track.size = Vector3(0.15 * s, 0.2 * s, 1.1 * s)
	_add_mesh(root, track, dark, Vector3(-0.45 * s, 0.1 * s, 0))
	_add_mesh(root, track, dark, Vector3(0.45 * s, 0.1 * s, 0))

	# Tourelle (cylindre)
	var turret := CylinderMesh.new()
	turret.top_radius = 0.22 * s
	turret.bottom_radius = 0.25 * s
	turret.height = 0.2 * s
	_add_mesh(root, turret, mat, Vector3(0, 0.4 * s, -0.05 * s))

	# Canon (cylindre fin)
	var cannon := CylinderMesh.new()
	cannon.top_radius = 0.04 * s
	cannon.bottom_radius = 0.05 * s
	cannon.height = 0.7 * s
	_add_mesh(root, cannon, metal, Vector3(0, 0.42 * s, -0.5 * s), Vector3(90, 0, 0))

func _build_fighter(root: Node3D, color: Color, scale_f: float) -> void:
	var mat := _make_mat(color)
	var dark := _make_mat(color.darkened(0.2))
	var s := scale_f

	# Fuselage (cylindre couché)
	var fuselage := CylinderMesh.new()
	fuselage.top_radius = 0.08 * s
	fuselage.bottom_radius = 0.12 * s
	fuselage.height = 1.0 * s
	_add_mesh(root, fuselage, mat, Vector3(0, 0.3 * s, 0), Vector3(90, 0, 0))

	# Nez (cône)
	var nose := CylinderMesh.new()
	nose.top_radius = 0.0
	nose.bottom_radius = 0.08 * s
	nose.height = 0.3 * s
	_add_mesh(root, nose, dark, Vector3(0, 0.3 * s, -0.6 * s), Vector3(90, 0, 0))

	# Ailes delta (boîte plate)
	var wing := BoxMesh.new()
	wing.size = Vector3(0.9 * s, 0.02 * s, 0.4 * s)
	_add_mesh(root, wing, mat, Vector3(0, 0.28 * s, 0.1 * s))

	# Dérive (boîte plate verticale)
	var tail := BoxMesh.new()
	tail.size = Vector3(0.02 * s, 0.25 * s, 0.2 * s)
	_add_mesh(root, tail, dark, Vector3(0, 0.42 * s, 0.4 * s))

func _build_bomber(root: Node3D, color: Color, scale_f: float) -> void:
	var mat := _make_mat(color)
	var dark := _make_mat(color.darkened(0.2))
	var s := ELITE_FACTOR  # Bomber est toujours plus gros

	# Fuselage large
	var fuselage := CylinderMesh.new()
	fuselage.top_radius = 0.12 * s
	fuselage.bottom_radius = 0.14 * s
	fuselage.height = 1.2 * s
	_add_mesh(root, fuselage, mat, Vector3(0, 0.3 * s, 0), Vector3(90, 0, 0))

	# Nez arrondi
	var nose := SphereMesh.new()
	nose.radius = 0.12 * s
	nose.height = 0.24 * s
	_add_mesh(root, nose, mat, Vector3(0, 0.3 * s, -0.6 * s))

	# Ailes droites (larges)
	var wing := BoxMesh.new()
	wing.size = Vector3(1.4 * s, 0.02 * s, 0.3 * s)
	_add_mesh(root, wing, mat, Vector3(0, 0.28 * s, 0))

	# Dérive haute
	var tail := BoxMesh.new()
	tail.size = Vector3(0.02 * s, 0.35 * s, 0.25 * s)
	_add_mesh(root, tail, dark, Vector3(0, 0.48 * s, 0.5 * s))

	# Empennage horizontal
	var htail := BoxMesh.new()
	htail.size = Vector3(0.5 * s, 0.02 * s, 0.15 * s)
	_add_mesh(root, htail, dark, Vector3(0, 0.3 * s, 0.55 * s))

func _build_ship(root: Node3D, color: Color, scale_f: float) -> void:
	var mat := _make_mat(color)
	var dark := _make_mat(color.darkened(0.3))
	var metal := _make_mat(Color(0.5, 0.5, 0.5), 0.3)
	var s := scale_f

	# Coque (boîte allongée, effilée à l'avant via prisme)
	var hull := BoxMesh.new()
	hull.size = Vector3(0.4 * s, 0.2 * s, 1.2 * s)
	_add_mesh(root, hull, mat, Vector3(0, 0.1 * s, 0))

	# Proue (cône couché)
	var bow := CylinderMesh.new()
	bow.top_radius = 0.0
	bow.bottom_radius = 0.2 * s
	bow.height = 0.3 * s
	_add_mesh(root, bow, mat, Vector3(0, 0.1 * s, -0.7 * s), Vector3(90, 0, 0))

	# Superstructure
	var bridge := BoxMesh.new()
	bridge.size = Vector3(0.25 * s, 0.15 * s, 0.3 * s)
	_add_mesh(root, bridge, dark, Vector3(0, 0.27 * s, 0))

	# Mât
	var mast := CylinderMesh.new()
	mast.top_radius = 0.015 * s
	mast.bottom_radius = 0.02 * s
	mast.height = 0.35 * s
	_add_mesh(root, mast, metal, Vector3(0, 0.5 * s, 0))

	# Tourelle canon (croiseur)
	if scale_f > 1.0:
		var turret := CylinderMesh.new()
		turret.top_radius = 0.08 * s
		turret.bottom_radius = 0.1 * s
		turret.height = 0.08 * s
		_add_mesh(root, turret, dark, Vector3(0, 0.25 * s, -0.35 * s))
		_add_mesh(root, turret, dark, Vector3(0, 0.25 * s, 0.3 * s))

func _build_flag(root: Node3D, color: Color) -> void:
	var mat := _make_mat(color)
	var wood := _make_mat(Color(0.55, 0.4, 0.25))

	# Mât
	var mast := CylinderMesh.new()
	mast.top_radius = 0.04
	mast.bottom_radius = 0.05
	mast.height = 1.6
	_add_mesh(root, mast, wood, Vector3(0, 0.8, 0))

	# Drapeau (boîte plate)
	var flag := BoxMesh.new()
	flag.size = Vector3(0.6, 0.4, 0.02)
	_add_mesh(root, flag, mat, Vector3(0.32, 1.35, 0))

	# Base
	var base := CylinderMesh.new()
	base.top_radius = 0.15
	base.bottom_radius = 0.2
	base.height = 0.1
	_add_mesh(root, base, wood, Vector3(0, 0.05, 0))

func _build_power(root: Node3D) -> void:
	var gold := _make_mat(Color(1.0, 0.85, 0.2), 0.6)
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.85, 0.2)
	gold.emission_energy_multiplier = 0.3

	var orb := SphereMesh.new()
	orb.radius = 0.35
	orb.height = 0.7
	_add_mesh(root, orb, gold, Vector3(0, 0.35, 0))

func _build_missile(root: Node3D, color: Color) -> void:
	var mat := _make_mat(color)
	var dark := _make_mat(color.darkened(0.3))
	var fire := _make_mat(Color(1.0, 0.5, 0.1))
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.4, 0.0)
	fire.emission_energy_multiplier = 0.5

	# Corps
	var body := CylinderMesh.new()
	body.top_radius = 0.15
	body.bottom_radius = 0.18
	body.height = 1.2
	_add_mesh(root, body, mat, Vector3(0, 0.7, 0))

	# Ogive (cône)
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.15
	tip.height = 0.3
	_add_mesh(root, tip, dark, Vector3(0, 1.45, 0))

	# Ailerons (4 boîtes)
	var fin := BoxMesh.new()
	fin.size = Vector3(0.3, 0.2, 0.02)
	_add_mesh(root, fin, dark, Vector3(0, 0.2, -0.12))
	_add_mesh(root, fin, dark, Vector3(0, 0.2, 0.12))
	var fin2 := BoxMesh.new()
	fin2.size = Vector3(0.02, 0.2, 0.3)
	_add_mesh(root, fin2, dark, Vector3(-0.12, 0.2, 0))
	_add_mesh(root, fin2, dark, Vector3(0.12, 0.2, 0))

	# Flamme
	var flame := CylinderMesh.new()
	flame.top_radius = 0.0
	flame.bottom_radius = 0.12
	flame.height = 0.25
	_add_mesh(root, flame, fire, Vector3(0, -0.05, 0), Vector3(180, 0, 0))

# ===== SÉLECTION VISUELLE =====

func _set_selection(node: Node3D, is_selected: bool) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.material_override:
			var mat: StandardMaterial3D = child.material_override
			if is_selected:
				mat.emission_enabled = true
				mat.emission = Color.WHITE
				mat.emission_energy_multiplier = 0.4
			else:
				# Restaurer — sauf pour Power/Missile qui ont leur propre émission
				if mat.albedo_color != Color(1.0, 0.85, 0.2) and mat.albedo_color != Color(1.0, 0.5, 0.1):
					mat.emission_enabled = false
