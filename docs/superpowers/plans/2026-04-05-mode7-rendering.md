# Mode 7 Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat 2D board rendering with a Mode 7-style perspective view using a SubViewport + Camera3D approach, with 2D sprite units projected onto the screen.

**Architecture:** The board is drawn in 2D inside a SubViewport, textured onto a 3D plane (MeshInstance3D). A Camera3D orbits the plane for perspective. Units are 2D sprites on a CanvasLayer overlay, positioned via `camera.unproject_position()`. Hit detection uses raycast from camera to the Y=0 plane.

**Tech Stack:** Godot 4.6, GDScript, GL Compatibility renderer, SubViewport, Camera3D, MeshInstance3D

**Spec:** `docs/superpowers/specs/2026-04-05-mode7-rendering-design.md`

---

### Task 1: Create Board3D — the 3D scene manager

This is the central coordinator: it owns the SubViewport, the 3D plane, the Camera3D, and provides coordinate conversion methods. Other components call into Board3D for all projection needs.

**Files:**
- Create: `scripts/board/board_3d.gd`

- [ ] **Step 1: Create the Board3D script**

```gdscript
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

# Positions grille de tous les secteurs (copie du board_renderer.sector_positions converti en grille)
var _grid_positions: Dictionary = {}  # sector_id -> Vector2 (grille logique)

func _ready() -> void:
	_setup_subviewport()
	_setup_3d_scene()
	_build_grid_positions()

func _setup_subviewport() -> void:
	board_viewport = SubViewport.new()
	board_viewport.size = Vector2i(1024, 1024)
	board_viewport.transparent_bg = false
	board_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(board_viewport)

	# Le BoardRenderer dessine dans ce SubViewport
	board_renderer = BoardRenderer.new()
	board_viewport.add_child(board_renderer)

func _setup_3d_scene() -> void:
	# Plan 3D horizontal (XZ) pour le plateau
	board_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	# Le plateau fait environ 11x10 cellules. On le rend carré pour la texture (1024x1024).
	plane.size = Vector2(12.0, 12.0)
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

	# Éclairage minimal (même si unshaded, certaines choses le requièrent)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	add_child(light)

func _build_grid_positions() -> void:
	## Copie les positions grille du BoardRenderer (pixel) et les reconvertit en coordonnées grille.
	## Appelé après _setup_subviewport() quand board_renderer est prêt.
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
	if camera == null:
		return Vector2.ZERO
	return camera.unproject_position(world_pos)

func get_sector_screen_scale(sector_id: String) -> float:
	## Retourne un facteur d'échelle basé sur la distance caméra (pour les sprites).
	if sector_id not in _grid_positions or camera == null:
		return 1.0
	var grid_pos: Vector2 = _grid_positions[sector_id]
	var world_pos := grid_to_3d(grid_pos)
	var dist := camera.global_position.distance_to(world_pos)
	# Référence: distance ~8 unités = scale 1.0
	return clampf(8.0 / dist, 0.3, 2.0)

# ===== HIT DETECTION =====

func screen_to_board_sector(screen_pos: Vector2) -> String:
	## Raycast depuis la caméra vers le plan Y=0, retourne le sector_id le plus proche.
	if camera == null:
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

	# Trouver le secteur le plus proche (distance < 0.6 cellule)
	var best_id := ""
	var best_dist := 0.6
	for sector_id in _grid_positions:
		var sector_grid: Vector2 = _grid_positions[sector_id]
		var dist := grid_pos.distance_to(sector_grid)
		if dist < best_dist:
			best_dist = dist
			best_id = sector_id
	return best_id
```

- [ ] **Step 2: Commit**

```bash
git add scripts/board/board_3d.gd
git commit -m "feat: add Board3D scene manager with SubViewport, 3D plane, and coordinate projection"
```

---

### Task 2: Create CameraController — orbit and zoom

**Files:**
- Create: `scripts/board/camera_controller.gd`

- [ ] **Step 1: Create the CameraController script**

```gdscript
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
```

- [ ] **Step 2: Commit**

```bash
git add scripts/board/camera_controller.gd
git commit -m "feat: add CameraController with orbit and zoom controls"
```

---

### Task 3: Restructure main.tscn — replace Node2D GameBoard with 3D scene

This is the most critical task: rewire the scene tree. The GameBoard Node2D becomes a Node3D with a Board3D child. The UnitRenderer moves to a CanvasLayer overlay. The AnimationManager's world overlay also moves.

**Files:**
- Modify: `scenes/main.tscn`
- Modify: `scripts/main.gd`

- [ ] **Step 1: Update main.tscn scene tree**

The new scene tree structure:

```
Main (Node)
├── Board3D (Node3D, script board_3d.gd)
│   ├── SubViewport (auto-created by board_3d.gd)
│   │   └── BoardRenderer (auto-created by board_3d.gd)
│   ├── MeshInstance3D (auto-created)
│   ├── Camera3D (auto-created)
│   └── CameraController (Node, script camera_controller.gd)
├── UnitOverlay (CanvasLayer, layer=5)
│   └── UnitRenderer (Node2D, script unit_renderer.gd)
├── AnimOverlay (CanvasLayer, layer=10)
│   └── AnimationManager (Node2D, script animation_manager.gd)
├── GameManager (Node)
└── GameUI (CanvasLayer)
    └── [same as before]
```

Replace the entire `scenes/main.tscn` file. The key changes:
- Remove `GameBoard` (Node2D) and its children
- Add `Board3D` (Node3D) with `board_3d.gd` script
- Add `CameraController` as child of Board3D
- Move `UnitRenderer` into a new `UnitOverlay` CanvasLayer
- Move `AnimationManager` into a new `AnimOverlay` CanvasLayer
- Keep `GameUI` CanvasLayer unchanged

Write the complete .tscn file (note: Board3D creates BoardRenderer, SubViewport, Camera3D, and MeshInstance3D dynamically in `_ready()`):

```tscn
[gd_scene load_steps=12 format=3]

[ext_resource type="Script" path="res://scripts/main.gd" id="1"]
[ext_resource type="Script" path="res://scripts/board/board_3d.gd" id="2"]
[ext_resource type="Script" path="res://scripts/board/camera_controller.gd" id="3"]
[ext_resource type="Script" path="res://scripts/units/unit_renderer.gd" id="4"]
[ext_resource type="Script" path="res://scripts/ui/animation_manager.gd" id="5"]
[ext_resource type="Script" path="res://scripts/core/game_manager.gd" id="6"]
[ext_resource type="Script" path="res://scripts/ui/order_panel.gd" id="7"]

[sub_resource type="StyleBoxFlat" id="topbar_style"]
bg_color = Color(0.08, 0.1, 0.18, 0.92)
border_color = Color(0.3, 0.35, 0.5, 0.4)
border_width_bottom = 1
corner_radius_bottom_left = 4
corner_radius_bottom_right = 4
content_margin_left = 16.0
content_margin_top = 6.0
content_margin_right = 16.0
content_margin_bottom = 6.0

[sub_resource type="StyleBoxFlat" id="bottombar_style"]
bg_color = Color(0.08, 0.1, 0.18, 0.92)
border_color = Color(0.3, 0.35, 0.5, 0.4)
border_width_top = 1
corner_radius_top_left = 4
corner_radius_top_right = 4
content_margin_left = 12.0
content_margin_top = 6.0
content_margin_right = 12.0
content_margin_bottom = 6.0

[sub_resource type="StyleBoxFlat" id="resolution_style"]
bg_color = Color(0.06, 0.08, 0.15, 0.95)
border_color = Color(0.35, 0.4, 0.6, 0.5)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
corner_radius_top_left = 6
corner_radius_top_right = 6
corner_radius_bottom_left = 6
corner_radius_bottom_right = 6
content_margin_left = 10.0
content_margin_top = 8.0
content_margin_right = 10.0
content_margin_bottom = 8.0

[sub_resource type="StyleBoxFlat" id="orderpanel_style"]
bg_color = Color(0.07, 0.09, 0.16, 0.95)
border_color = Color(0.35, 0.4, 0.55, 0.5)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
corner_radius_top_left = 6
corner_radius_top_right = 6
corner_radius_bottom_left = 6
corner_radius_bottom_right = 6
content_margin_left = 10.0
content_margin_top = 8.0
content_margin_right = 10.0
content_margin_bottom = 8.0

[node name="Main" type="Node"]
script = ExtResource("1")

[node name="Board3D" type="Node3D" parent="."]
script = ExtResource("2")

[node name="CameraController" type="Node" parent="Board3D"]
script = ExtResource("3")

[node name="UnitOverlay" type="CanvasLayer" parent="."]
layer = 5

[node name="UnitRenderer" type="Node2D" parent="UnitOverlay"]
script = ExtResource("4")

[node name="AnimOverlay" type="CanvasLayer" parent="."]
layer = 10

[node name="AnimationManager" type="Node2D" parent="AnimOverlay"]
script = ExtResource("5")

[node name="GameManager" type="Node" parent="."]
script = ExtResource("6")

[node name="GameUI" type="CanvasLayer" parent="."]

[node name="TopBar" type="PanelContainer" parent="GameUI"]
anchors_preset = 10
anchor_right = 1.0
offset_bottom = 38.0
grow_horizontal = 2
theme_override_styles/panel = SubResource("topbar_style")

[node name="HBox" type="HBoxContainer" parent="GameUI/TopBar"]
layout_mode = 2

[node name="RoundLabel" type="Label" parent="GameUI/TopBar/HBox"]
layout_mode = 2
size_flags_horizontal = 3
theme_override_colors/font_color = Color(0.7, 0.75, 0.9, 1)
theme_override_font_sizes/font_size = 14
text = "Manche 0"

[node name="PhaseLabel" type="Label" parent="GameUI/TopBar/HBox"]
layout_mode = 2
size_flags_horizontal = 3
theme_override_colors/font_color = Color(1, 0.85, 0.4, 1)
theme_override_font_sizes/font_size = 15
text = "POWER"
horizontal_alignment = 1

[node name="GameTimerLabel" type="Label" parent="GameUI/TopBar/HBox"]
layout_mode = 2
size_flags_horizontal = 3
theme_override_colors/font_color = Color(0.7, 0.75, 0.9, 1)
theme_override_font_sizes/font_size = 14
text = "2:00:00"
horizontal_alignment = 2

[node name="BottomBar" type="PanelContainer" parent="GameUI"]
anchors_preset = 12
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_top = -50.0
grow_horizontal = 2
grow_vertical = 0
theme_override_styles/panel = SubResource("bottombar_style")

[node name="VBox" type="VBoxContainer" parent="GameUI/BottomBar"]
layout_mode = 2

[node name="InfoLabel" type="Label" parent="GameUI/BottomBar/VBox"]
layout_mode = 2
theme_override_colors/font_color = Color(0.85, 0.85, 0.9, 1)
theme_override_font_sizes/font_size = 13
text = "Bienvenue dans Power!"

[node name="SectorInfo" type="Label" parent="GameUI/BottomBar/VBox"]
layout_mode = 2
theme_override_colors/font_color = Color(0.6, 0.62, 0.72, 1)
theme_override_font_sizes/font_size = 12
text = "Cliquez sur un secteur pour voir les détails."

[node name="ResolutionPanel" type="PanelContainer" parent="GameUI"]
anchors_preset = 3
anchor_left = 0.0
anchor_top = 1.0
anchor_right = 0.5
anchor_bottom = 1.0
offset_left = 5.0
offset_top = -290.0
offset_right = -5.0
offset_bottom = -55.0
grow_horizontal = 2
grow_vertical = 0
visible = false
theme_override_styles/panel = SubResource("resolution_style")

[node name="VBox" type="VBoxContainer" parent="GameUI/ResolutionPanel"]
layout_mode = 2

[node name="LogTitle" type="Label" parent="GameUI/ResolutionPanel/VBox"]
layout_mode = 2
theme_override_colors/font_color = Color(0.8, 0.75, 0.55, 1)
theme_override_font_sizes/font_size = 13
text = "Journal de résolution"
horizontal_alignment = 1

[node name="ResolutionLog" type="RichTextLabel" parent="GameUI/ResolutionPanel/VBox"]
layout_mode = 2
size_flags_vertical = 3
theme_override_font_sizes/normal_font_size = 11
bbcode_enabled = true
scroll_following = true

[node name="OrderPanel" type="PanelContainer" parent="GameUI"]
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
offset_left = -265.0
offset_top = 42.0
offset_right = -5.0
offset_bottom = 560.0
grow_horizontal = 0
visible = false
theme_override_styles/panel = SubResource("orderpanel_style")
script = ExtResource("7")
```

- [ ] **Step 2: Update main.gd to use new scene tree**

Replace the `@onready` declarations and signal connections:

```gdscript
extends Node

## Scène racine du jeu Power.
## Orchestre les composants: plateau 3D, unités, game manager, UI, ordres.

@onready var board_3d: Board3D = $Board3D
@onready var board_renderer: BoardRenderer  # Initialisé dans _on_game_start_requested
@onready var unit_renderer: UnitRenderer = $UnitOverlay/UnitRenderer
@onready var game_manager: Node = $GameManager
@onready var order_panel: OrderPanel = $GameUI/OrderPanel
@onready var anim_manager: AnimationManager = $AnimOverlay/AnimationManager
@onready var camera_controller: CameraController = $Board3D/CameraController

# UI
@onready var phase_label: Label = $GameUI/TopBar/HBox/PhaseLabel
@onready var game_timer_label: Label = $GameUI/TopBar/HBox/GameTimerLabel
@onready var round_label: Label = $GameUI/TopBar/HBox/RoundLabel
@onready var info_label: Label = $GameUI/BottomBar/VBox/InfoLabel
@onready var sector_info: Label = $GameUI/BottomBar/VBox/SectorInfo
@onready var resolution_panel: PanelContainer = $GameUI/ResolutionPanel
@onready var resolution_log: RichTextLabel = $GameUI/ResolutionPanel/VBox/ResolutionLog

var _switch_screen: PlayerSwitchScreen
var _game_started := false

func _ready() -> void:
	# Cacher les éléments de jeu pendant l'écran titre
	$Board3D.visible = false
	$UnitOverlay.visible = false
	$AnimOverlay.visible = false
	$GameUI.visible = false

	# Récupérer le board_renderer créé dynamiquement par Board3D
	board_renderer = board_3d.board_renderer

	# Connecter la caméra
	camera_controller.camera = board_3d.camera

	# Afficher l'écran titre
	var title := preload("res://scripts/ui/title_screen.gd").new()
	title.game_start_requested.connect(_on_game_start_requested)
	add_child(title)

func _on_game_start_requested(num_players: int, human_color: GameEnums.PlayerColor, is_solo: bool) -> void:
	# Montrer les éléments de jeu
	$Board3D.visible = true
	$UnitOverlay.visible = true
	$AnimOverlay.visible = true
	$GameUI.visible = true

	# Connecter les signaux du Board3D (hit detection 3D)
	board_3d.sector_clicked.connect(_on_sector_clicked)
	board_3d.sector_hovered.connect(_on_sector_hovered)

	# Connecter les signaux du game manager
	game_manager.phase_changed.connect(_on_phase_changed)
	game_manager.round_started.connect(_on_round_started)
	game_manager.planning_player_changed.connect(_on_planning_player_changed)
	game_manager.planning_timer_updated.connect(_on_planning_timer_updated)
	game_manager.combat_resolved.connect(_on_combat_resolved)
	game_manager.flag_captured.connect(_on_flag_captured)
	game_manager.game_over.connect(_on_game_over)
	game_manager.resolution_log.connect(_on_resolution_log)

	# Connecter le panneau d'ordres
	order_panel.orders_confirmed.connect(_on_orders_confirmed)

	# Créer l'écran de transition
	_switch_screen = PlayerSwitchScreen.new()
	_switch_screen.visible = false
	_switch_screen.player_ready.connect(_on_player_ready)
	$GameUI.add_child(_switch_screen)

	# Connecter l'animation manager au board_3d pour les positions projetées
	if anim_manager:
		anim_manager.board_renderer = board_renderer

	# Démarrer la partie
	if is_solo:
		game_manager.start_game(num_players, human_color)
	else:
		game_manager.start_game_hotseat(num_players)
	_game_started = true

	# Connecter l'état du jeu au panneau d'ordres
	order_panel.game_state = game_manager.game_state
	order_panel.board_renderer = board_renderer

	# Connecter l'état du jeu au Board3D pour le hit detection
	board_3d.board_data = game_manager.game_state.board

	# Passer le board_3d au unit_renderer pour la projection
	unit_renderer.board_3d = board_3d
	unit_renderer.game_state = game_manager.game_state
	unit_renderer.update_display()
```

Note: The rest of `main.gd` (signal handlers like `_on_sector_clicked`, `_on_sector_hovered`, etc.) stays exactly the same — they already receive `sector_id: String` and don't care about coordinates.

- [ ] **Step 3: Commit**

```bash
git add scenes/main.tscn scripts/main.gd
git commit -m "feat: restructure scene tree for 3D board with 2D overlays"
```

---

### Task 4: Add input handling to Board3D (raycast hit detection)

Board3D needs to handle mouse input for sector clicking and hovering via 3D raycast.

**Files:**
- Modify: `scripts/board/board_3d.gd`

- [ ] **Step 1: Add input handling to Board3D**

Add to the end of `board_3d.gd`:

```gdscript
var _hovered_sector: String = ""

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
```

- [ ] **Step 2: Disable the old input handling in BoardRenderer**

In `scripts/board/board_renderer.gd`, remove or comment out the `_unhandled_input` method entirely. Board3D now handles all input. Replace the function:

```gdscript
# Input est géré par Board3D (raycast 3D)
# func _unhandled_input(event: InputEvent) -> void:
#     pass
```

- [ ] **Step 3: Commit**

```bash
git add scripts/board/board_3d.gd scripts/board/board_renderer.gd
git commit -m "feat: add 3D raycast hit detection to Board3D, disable old 2D input"
```

---

### Task 5: Adapt BoardRenderer for SubViewport rendering

The BoardRenderer currently assumes it draws at screen coordinates with a specific BOARD_ORIGIN. Inside the SubViewport (1024x1024), it needs to draw at a centered position within that viewport.

**Files:**
- Modify: `scripts/board/board_renderer.gd`

- [ ] **Step 1: Adjust BOARD_ORIGIN for SubViewport coordinates**

The SubViewport is 1024x1024. The grid is ~11x10 cells at 55px each = ~605x550. We need to center this in the 1024x1024 viewport.

Replace the `BOARD_ORIGIN` constant:

```gdscript
# Pour SubViewport 1024x1024: centrer la grille (~11x10 cellules)
# Centre grille logique: (3.75, 3.5). Centre viewport: (512, 512)
const BOARD_ORIGIN := Vector2(512 - 3.75 * 55.0, 512 - 3.5 * 55.0)  # ~(305.75, 319.5)
```

- [ ] **Step 2: Add get_sector_position that returns screen-projected position**

The `get_sector_position()` method is used by AnimationManager and other components. It currently returns the pixel position within the board. Now it needs to return the screen-projected position via Board3D.

Add a reference to Board3D and update `get_sector_position`:

```gdscript
var board_3d: Board3D  # Set by main.gd or Board3D

func get_sector_position(sector_id: String) -> Vector2:
	## Retourne la position écran projetée du secteur.
	## Si board_3d est disponible, projette via la caméra 3D.
	## Sinon, retourne la position pixel brute (fallback).
	if board_3d != null:
		return board_3d.get_sector_screen_position(sector_id)
	return sector_positions.get(sector_id, Vector2.ZERO)
```

- [ ] **Step 3: Set board_3d reference from Board3D._setup_subviewport()**

In `board_3d.gd`, in `_setup_subviewport()`, after creating the BoardRenderer, set the back-reference:

```gdscript
func _setup_subviewport() -> void:
	board_viewport = SubViewport.new()
	board_viewport.size = Vector2i(1024, 1024)
	board_viewport.transparent_bg = false
	board_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(board_viewport)

	board_renderer = BoardRenderer.new()
	board_renderer.board_3d = self  # Back-reference pour la projection
	board_viewport.add_child(board_renderer)
```

- [ ] **Step 4: Commit**

```bash
git add scripts/board/board_renderer.gd scripts/board/board_3d.gd
git commit -m "feat: adapt BoardRenderer for SubViewport and add projected sector positions"
```

---

### Task 6: Adapt UnitRenderer for 2D overlay projection

The UnitRenderer currently uses batch `_draw()` with positions from BoardRenderer. Now it needs to use projected screen positions from Board3D, running in a CanvasLayer overlay.

**Files:**
- Modify: `scripts/units/unit_renderer.gd`

- [ ] **Step 1: Add board_3d reference and _process-based positioning**

Replace the beginning of `unit_renderer.gd`:

```gdscript
extends Node2D
class_name UnitRenderer

## Affiche les unités sur le plateau avec des icônes géométriques distinctes.
## En mode 3D, les unités sont positionnées via projection Camera3D → écran.

var board_renderer: BoardRenderer
var board_3d: Board3D
var game_state: GameState

const ICON_SIZE := 8.0
const ICON_SPACING := 18.0
const MAX_PER_ROW := 3

func update_display() -> void:
	queue_redraw()

func _process(_delta: float) -> void:
	# Redessiner chaque frame car la caméra peut bouger
	if board_3d != null and game_state != null:
		queue_redraw()
```

- [ ] **Step 2: Update _draw() to use projected positions**

Replace the `_draw()` method:

```gdscript
func _draw() -> void:
	if game_state == null:
		return

	# Utiliser board_3d pour les positions projetées, sinon fallback sur board_renderer
	var position_source_3d := board_3d != null
	var positions: Dictionary = {}

	if position_source_3d:
		for sector_id in board_3d._grid_positions:
			positions[sector_id] = board_3d.get_sector_screen_position(sector_id)
	elif board_renderer != null:
		positions = board_renderer.sector_positions

	for sector_id in positions:
		var sector: Sector = game_state.board.get_sector(sector_id)
		if sector == null or sector.units.is_empty():
			continue
		var base_pos: Vector2 = positions[sector_id]

		# Facteur d'échelle selon la distance (effet de profondeur)
		var scale_factor := 1.0
		if position_source_3d:
			scale_factor = board_3d.get_sector_screen_scale(sector_id)

		_draw_units_at_sector(sector.units, base_pos, scale_factor)
```

- [ ] **Step 3: Update _draw_units_at_sector to accept scale factor**

Replace `_draw_units_at_sector`:

```gdscript
func _draw_units_at_sector(units: Array, base_pos: Vector2, scale_factor: float = 1.0) -> void:
	var count := units.size()
	if count == 0:
		return

	var spacing := ICON_SPACING * scale_factor
	var cols: int = mini(count, MAX_PER_ROW)
	var rows: int = ceili(float(count) / cols)
	var start_x: float = -(cols - 1) * spacing * 0.5
	var start_y: float = -(rows - 1) * spacing * 0.5

	for i in range(count):
		var unit: UnitData = units[i]
		var col: int = i % cols
		var row: int = i / cols
		var offset := Vector2(start_x + col * spacing, start_y + row * spacing)
		var pos := base_pos + offset
		var color: Color = GameEnums.get_player_color(unit.owner)

		_draw_unit_icon(pos, unit.unit_type, color, unit.owner, scale_factor)
```

- [ ] **Step 4: Add scale_factor parameter to _draw_unit_icon**

Update `_draw_unit_icon` signature and pass scale to all drawing functions. Add a `_scaled` helper:

```gdscript
func _draw_unit_icon(pos: Vector2, unit_type: GameEnums.UnitType, color: Color, owner: GameEnums.PlayerColor, scale_factor: float = 1.0) -> void:
	var shadow_offset := Vector2(1, 1) * scale_factor

	match unit_type:
		GameEnums.UnitType.SOLDIER:
			_draw_soldier(pos, color, shadow_offset, false, scale_factor)
		GameEnums.UnitType.REGIMENT:
			_draw_soldier(pos, color, shadow_offset, true, scale_factor)
		GameEnums.UnitType.TANK:
			_draw_tank(pos, color, shadow_offset, false, scale_factor)
		GameEnums.UnitType.HEAVY_TANK:
			_draw_tank(pos, color, shadow_offset, true, scale_factor)
		GameEnums.UnitType.FIGHTER:
			_draw_plane(pos, color, shadow_offset, false, scale_factor)
		GameEnums.UnitType.BOMBER:
			_draw_plane(pos, color, shadow_offset, true, scale_factor)
		GameEnums.UnitType.DESTROYER:
			_draw_ship(pos, color, shadow_offset, false, scale_factor)
		GameEnums.UnitType.CRUISER:
			_draw_ship(pos, color, shadow_offset, true, scale_factor)
		GameEnums.UnitType.FLAG:
			_draw_flag(pos, color, shadow_offset, scale_factor)
		GameEnums.UnitType.POWER:
			_draw_power(pos, color, shadow_offset, scale_factor)
		GameEnums.UnitType.MEGA_MISSILE:
			_draw_missile(pos, color, shadow_offset, scale_factor)
```

Then update each drawing function to multiply its `s` (size) by `scale_factor`. For example, `_draw_soldier`:

```gdscript
func _draw_soldier(pos: Vector2, color: Color, shadow: Vector2, is_big: bool, sf: float = 1.0) -> void:
	var s: float = ICON_SIZE * (1.3 if is_big else 1.0) * sf
	# ... rest unchanged, using s which now includes scale_factor
```

Apply the same pattern to ALL drawing functions: `_draw_tank`, `_draw_plane`, `_draw_ship`, `_draw_flag`, `_draw_power`, `_draw_missile`, `_draw_star`. Each gets a `sf: float = 1.0` parameter and multiplies its base size by `sf`.

- [ ] **Step 5: Commit**

```bash
git add scripts/units/unit_renderer.gd
git commit -m "feat: adapt UnitRenderer for 3D-projected positions with depth scaling"
```

---

### Task 7: Adapt AnimationManager for overlay rendering

The AnimationManager's world overlay needs to work in screen space (CanvasLayer) with projected positions.

**Files:**
- Modify: `scripts/ui/animation_manager.gd`

- [ ] **Step 1: Remove _world_overlay creation, use self as overlay**

The AnimationManager is now a child of a CanvasLayer (`AnimOverlay`). It can use itself as the overlay for world-space animations. Remove `_world_overlay` creation and use `self`:

In `_ready()`, replace:

```gdscript
func _ready() -> void:
	# En mode 3D, AnimationManager est dans un CanvasLayer overlay.
	# Les animations sont en coordonnées écran (projetées par Board3D).
	_world_overlay = self  # On utilise soi-même comme overlay (déjà dans un CanvasLayer)

	_screen_overlay = CanvasLayer.new()
	_screen_overlay.layer = 50
	add_child(_screen_overlay)
```

- [ ] **Step 2: Commit**

```bash
git add scripts/ui/animation_manager.gd
git commit -m "feat: adapt AnimationManager for CanvasLayer overlay rendering"
```

---

### Task 8: Wire GameManager references for Board3D

The GameManager gets board_renderer and unit_renderer from main.gd. We need to update this wiring for the new scene tree.

**Files:**
- Modify: `scripts/core/game_manager.gd`

- [ ] **Step 1: Update start_game to find renderers via new paths**

In `game_manager.gd`, `start_game()` currently uses:
```gdscript
board_renderer = get_node_or_null("../GameBoard/BoardRenderer") as BoardRenderer
unit_renderer = get_node_or_null("../GameBoard/UnitRenderer") as UnitRenderer
anim_manager = get_node_or_null("../GameBoard/AnimationManager") as AnimationManager
```

Replace with the new paths:
```gdscript
# Board3D crée le BoardRenderer dans son SubViewport
var board_3d_node = get_node_or_null("../Board3D") as Board3D
if board_3d_node:
	board_renderer = board_3d_node.board_renderer
unit_renderer = get_node_or_null("../UnitOverlay/UnitRenderer") as UnitRenderer
anim_manager = get_node_or_null("../AnimOverlay/AnimationManager") as AnimationManager
```

Apply the same change in `start_game_hotseat()`.

- [ ] **Step 2: Commit**

```bash
git add scripts/core/game_manager.gd
git commit -m "feat: update GameManager paths for new 3D scene tree"
```

---

### Task 9: Update OrderPanel board_renderer reference

The OrderPanel receives `board_renderer` from main.gd. It uses `board_renderer` for highlights. This should still work since `board_renderer` is the same object (just inside a SubViewport now). But we need to verify `board_renderer.highlight_sectors()` and `board_renderer.clear_highlights()` still work — they just call `queue_redraw()` which redraws inside the SubViewport.

**Files:**
- Verify: `scripts/ui/order_panel.gd` — no changes expected

- [ ] **Step 1: Verify OrderPanel still works**

The OrderPanel calls:
- `board_renderer.highlight_sectors(typed)` → calls `queue_redraw()` on BoardRenderer inside SubViewport → OK
- `board_renderer.clear_highlights()` → same → OK
- `board_renderer.selected_sector = sector_id` → sets state → OK

No code changes needed. The OrderPanel's `board_renderer` reference points to the BoardRenderer inside the SubViewport, which is the same object.

- [ ] **Step 2: Commit (no changes, just verification)**

No commit needed for this task.

---

### Task 10: Integration test — run the game

**Files:**
- Possibly fix any issues in all modified files

- [ ] **Step 1: Launch the game**

```bash
"/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --path .
```

- [ ] **Step 2: Verify visuals**

Check:
- The board appears in perspective (not flat)
- Clic-droit + drag rotates the camera around the board
- Molette zooms in/out
- Units are visible as 2D sprites that scale with distance
- Clic-gauche on sectors works (selection, highlights visible)
- Start a game: title screen → solo → planning phase → order entry
- Verify animations (movement, combat) play correctly
- Verify UI panels (OrderPanel, TopBar, BottomBar, ResolutionPanel) display correctly

- [ ] **Step 3: Fix any issues found**

Common issues to watch for:
- SubViewport texture not appearing on the 3D plane → check material assignment
- Camera not showing anything → check camera.current = true and initial position
- Units not visible → check CanvasLayer layer ordering
- Clicks not registering → check raycast math and sector distance threshold
- Board too dark → ensure `shading_mode = UNSHADED` on the material

- [ ] **Step 4: Final commit**

```bash
git add -u
git commit -m "feat: Mode 7 perspective rendering with Camera3D orbit and zoom"
```
