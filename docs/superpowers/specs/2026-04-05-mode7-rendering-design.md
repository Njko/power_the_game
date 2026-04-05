# Spec : Rendu Mode 7 (SubViewport + Camera3D)

## Contexte

Le rendu actuel du jeu Power est entièrement 2D plat : `BoardRenderer._draw()` dessine des rectangles à des positions pixel fixes, `UnitRenderer` positionne les icônes géométriques relativement à ces positions, et le hit test compare directement les coordonnées souris aux Rect2 des secteurs. Il n'y a ni caméra ni transformation.

L'objectif est de passer à un rendu style Mode 7 SNES : le plateau est en perspective (surface inclinée), les unités sont des sprites 2D qui restent face caméra (billboards). Une caméra permet de tourner autour du plateau et de zoomer. C'est une première implémentation simple, à enrichir ensuite.

## Architecture

### Pipeline de rendu

```
SubViewport (2D, 1024x1024)            Scène 3D
  └── BoardRenderer._draw()     ���      MeshInstance3D (PlaneMesh, axe XZ)
      (même code de dessin qu'avant)      texture = SubViewport.get_texture()
                                          └── Camera3D (orbite autour du centre)

CanvasLayer (overlay 2D)
  └── UnitOverlay (Node2D)
        └���─ sprites 2D positionnés via camera.unproject_position()
```

Le plateau 2D est dessiné dans un SubViewport (texture 1024x1024). Cette texture est plaquée sur un plan 3D horizontal. La Camera3D orbite autour du centre du plan. Les unités sont des sprites 2D sur un CanvasLayer séparé, positionnés en projetant leurs coordonnées 3D sur l'écran.

### Mapping de coordonnées

3 espaces de coordonnées :

1. **Grille logique** (0-8 flottant) — défini par `BoardData._grid_positions`
2. **Espace 3D** — plan XZ centré à l'origine. Formule : `Vector3((grid_x - 4.0) * SCALE_3D, 0, (grid_y - 4.0) * SCALE_3D)` où `SCALE_3D` est une constante (ex: 1.0 par cellule logique)
3. **Espace écran** — pixel. Obtenu via `camera.unproject_position(pos_3d)`

Conversion grille → 3D → écran pour positionner les sprites.
Conversion écran → 3D (raycast) → grille pour le hit detection.

### Contrôles caméra

- **Orbit** : clic-droit + drag → rotation azimuth (horizontal) et élévation (vertical, clampée entre 20° et 85°)
- **Zoom** : molette souris → rapprocher/éloigner (distance clampée entre min et max)
- **Centre** : toujours le centre du plateau (Vector3.ZERO), pas de pan
- **Angle initial** : élévation ~60°, azimuth 0° (face au joueur vert)
- Le clic-gauche reste réservé à la sélection de secteurs/unités (non capturé par la caméra)

### Hit detection (clic secteur)

1. Clic gauche → `camera.project_ray_origin(mouse_pos)` + `camera.project_ray_normal(mouse_pos)`
2. Intersection rayon/plan Y=0 → point 3D sur le plateau
3. Conversion 3D → grille logique : `grid_x = point.x / SCALE_3D + 4.0`, `grid_y = point.z / SCALE_3D + 4.0`
4. Lookup du secteur le plus proche dans `BoardData._grid_positions`
5. Émettre `sector_clicked` / `sector_hovered` comme avant

### Unités (sprites 2D projetés)

- `UnitRenderer` ne dessine plus via `_draw()` batch
- À la place, il maintient un pool de `Node2D` enfants d'un overlay CanvasLayer
- Chaque unité visible a un sprite positionné via `camera.unproject_position(unit_world_pos)`
- Les icônes géométriques existantes (`_draw_soldier`, `_draw_tank`, etc.) sont réutilisées en dessinant dans chaque Node2D sprite
- Le scale des sprites est ajusté selon la distance caméra (plus loin = plus petit) pour un effet de profondeur

### Animations

`AnimationManager` utilise déjà `board_renderer.get_sector_position()` pour obtenir les positions. Cette méthode retournera maintenant la position écran projetée. Les animations tweenent en espace écran comme avant. Le `_world_overlay` devient enfant du CanvasLayer overlay au lieu du GameBoard 3D.

## Fichiers

### Nouveaux fichiers

| Fichier | Responsabilité |
|---------|---------------|
| `scripts/board/camera_controller.gd` | Contrôles orbit/zoom sur Camera3D. Input handling (clic-droit drag, molette). |
| `scripts/board/board_3d.gd` | Gère le SubViewport, le MeshInstance3D, la projection grille↔3D↔écran. Point d'entrée pour hit detection. |

### Fichiers modifiés

| Fichier | Nature du changement |
|---------|---------------------|
| `scripts/board/board_renderer.gd` | Dessine dans un SubViewport enfant au lieu de directement à l'écran. `get_sector_position()` retourne la position écran projetée via Board3D. Hit detection déléguée à Board3D (raycast). `_unhandled_input` adapté pour le raycast 3D. |
| `scripts/units/unit_renderer.gd` | Passe de `_draw()` batch à des Node2D enfants positionnés via projection. `_process()` met à jour les positions chaque frame (la caméra peut bouger). |
| `scripts/ui/animation_manager.gd` | `_world_overlay` déplacé sur le CanvasLayer overlay. Positions obtenues via `board_renderer.get_sector_position()` (déjà projetées). |
| `scenes/main.tscn` | Restructurer la scène : ajouter Node3D + SubViewport + MeshInstance3D + Camera3D + CanvasLayer overlay. |

### Fichiers inchangés

- `scripts/core/*` — Toutes les données et la logique de jeu
- `scripts/ui/order_panel.gd` — UI en CanvasLayer, pas affect��e
- `scripts/ai/ai_player.gd` — Pas de rendu
- `scripts/ui/title_screen.gd`, `scripts/ui/player_switch_screen.gd` — UI overlay

## Vérification

1. Le plateau s'affiche en perspective (incliné, pas plat)
2. Les unités sont visibles comme sprites 2D face caméra
3. Clic-droit + drag fait tourner la vue autour du plateau
4. Molette zoome/dézoome
5. Clic-gauche sur un secteur fonctionne (sélection, ordres) à tout angle de caméra
6. Les animations (déplacement, combat, explosion) fonctionnent correctement
7. L'UI (OrderPanel, TopBar, BottomBar) reste en place et fonctionnelle
8. Les highlights de secteurs (reachable, selected, hovered) sont visibles en perspective
