# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Digital recreation of the 1981 Spear's Games board game "Power" built with **Godot 4.6** (GDScript, GL Compatibility renderer). A no-luck strategy game for 2-4 players where each round players simultaneously program up to 5 orders (movement/exchange), then resolution happens automatically. Original rules are in `regles_power.htm`, board photo in `regles_power_files/plateau.jpg`.

## Running the Game

```bash
# Launch via Steam-installed Godot
"/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --path .

# Open in editor
"/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --editor --path .
```

Target: 1280x720 viewport, `canvas_items` stretch mode.

## Architecture

### Data vs Logic vs Rendering

- **Data layer** (`scripts/core/`): All `RefCounted` classes — `GameState`, `BoardData`, `PlayerData`, `UnitData`, `Sector`, `Order`, `GameEnums`. No signals, no Nodes. Pure data and lookups.
- **Logic layer** (`scripts/core/game_manager.gd`): Single `Node` state machine controlling the 6-phase game loop. Owns `GameState`. Uses `await` for async phase transitions with animations.
- **Rendering layer** (`scripts/board/`, `scripts/units/`): `Node2D` classes using `_draw()` for all visuals. No per-unit Node2D objects — everything is procedurally drawn in batch.
- **UI layer** (`scripts/ui/`): Dynamically-built controls (no .tscn for panels). `OrderPanel` builds its UI in `_build_ui()`. `PhaseTimeline` widget in TopBar shows phase progression.
- **AI** (`scripts/ai/ai_player.gd`): `RefCounted`, generates `Order` arrays. Strategic phases (DEVELOP/ATTACK/CAPTURE/DEFEND), target focus on weakest enemy, unit coordination via rally points, rebond memory.
- **Arbiter** (`scripts/core/game_arbiter.gd`): `RefCounted`, validates every game action in real-time against official rules. Logs violations via `push_warning()` and `resolution_log` signal.
- **Logger** (`scripts/core/game_logger.gd`): `RefCounted`, writes structured per-turn log to `user://game_log.txt` with board state snapshots, orders, combats, and diffs.

### Game Loop (per round)

```
PLANNING → EXECUTION → CONFLICT → COLLECT_POWER → CAPTURE_FLAGS → next round
```

Phases 2-6 run asynchronously via `_run_resolution_phases()`. **Execution and conflict phases are sequential**: each order/combat is animated individually, then the display updates before the next one.

```gdscript
await _phase_execution()      # Execute orders one by one with animation after each
await _phase_conflict()       # Resolve combats one by one with animation after each
await _phase_collect_power()  # Award Power for territory occupation
await _phase_capture_flags()  # Check flag captures + play flag animations
```

### Signal Flow

`GameManager` emits → `main.gd` receives and updates UI. `BoardRenderer` emits `sector_clicked`/`sector_hovered` → `main.gd` delegates to `OrderPanel` during PLANNING phase. `AnimationManager` emits `animation_finished` → `GameManager` awaits it between each order/combat.

### Board Layout (9×9 grid, faithful to 1981 original)

```
Col:  0    1    2    3    4    5    6    7    8
R0: HQ_V  S5   S5   S5   IN   S1   S1   S1  HQ_B
R1: S4    [--- V territory ---] S6  [--- B territory ---] S2
R2: S4    [--- V territory ---] S6  [--- B territory ---] S2
R3: S4    [--- V territory ---] S6  [--- B territory ---] S2
R4: IW    S3   S3   S3   IX   S9   S9   S9   IE
R5: S12   [--- J territory ---] S8  [--- R territory ---] S10
R6: S12   [--- J territory ---] S8  [--- R territory ---] S10
R7: S12   [--- J territory ---] S8  [--- R territory ---] S10
R8: HQ_J  S11  S11  S11  IS   S7   S7   S7  HQ_R
```

**Sector numbering**: Diagonal from IX corner (Manhattan distance). Sector 0 = closest to IX, sector 8 = closest to HQ.
```
0  2  5
1  4  7
3  6  8
```
Per-territory flip orients sector 0 toward IX: V=flip XY, B=flip Y, J=flip X, R=no flip.

**Sea sectors**: All 12 are 3-cell strips (horizontal or vertical). No direct S↔S adjacency — must pass through island or coastal sector.

**Islands**: Octogonal rendering. IW/IE connect to adjacent territories. IN/IS/IX connect to territory corners diagonally.

**HQs**: 2× cell size, at diagonal corners. Connect to sector 8 of their territory.

### Movement Rules (enforced in `get_reachable_sectors`)

- **Land units** (Soldier/Regiment/Tank/Heavy Tank): LAND, COASTAL, ISLAND, HQ. **Must stop on island or HQ** (can't enter and exit in same turn).
- **Air units** (Fighter/Bomber): All except SEA. Can fly over islands without stopping.
- **Naval units** (Destroyer/Cruiser): SEA, COASTAL only. Sector 4 (LAND center) inaccessible.
- **Movement validation**: `game_manager` uses `get_reachable_sectors()` (not `get_distance()`) to enforce island/HQ stopping rule.

## GDScript Conventions

- **Strict typing required**: Godot 4.6 rejects `:=` with untyped returns (Dictionary access, `.find()`, `.size()` on untyped arrays). Always use `var x: Type = ...` instead of `var x := ...` when the RHS involves Variant.
- **French throughout**: All variable names, comments, UI text, and game terminology in French.
- **Static lookups**: `GameEnums` contains all game constants as static functions (`get_unit_power()`, `get_unit_max_move()`, etc.).
- **Factory methods**: `Order.create_move()`, `Order.create_exchange()`, `Order.create_launch()`, `Order.create_missile_exchange()`.
- **Transient state via metadata**: `unit.set_meta("origin_sector", id)` for per-turn tracking (rebound logic).
- **Preload for new classes**: New `RefCounted` scripts (GameLogger, GameArbiter) are loaded via `const XClass = preload("res://...")` in game_manager since Godot may not auto-detect `class_name` for files created outside the editor.

## Key Gotchas

- **Animation await deadlock**: `play_all()` must defer `animation_finished` emission when queue is empty, otherwise the `await` on the calling side misses the synchronous signal. See `_emit_finished_deferred()`.
- **Sequential execution**: Orders and combats are executed one at a time with `await` after each animation. The `_animation_queue` is checked with `not anim_manager._animation_queue.is_empty()` before calling `play_all()`.
- **Arbiter rotation**: Affects both planning order AND execution order. Built from `arbiter_index % active.size()`.
- **Flag capture requires infantry**: Only `SOLDIER` or `REGIMENT` in the enemy HQ triggers capture, plus strictly greater power than defender.
- **Board uses `_unhandled_input`**: So CanvasLayer UI panels get click priority over the board.
- **Single scene**: `scenes/main.tscn` is the only scene file. Title screen (in CanvasLayer 30) and player switch screen are created dynamically.
- **Debug adjacency**: `board_renderer.debug_adjacency = true` draws colored lines between adjacent sectors (green=land, blue=naval, yellow=mixed). Currently enabled for debugging.
- **Game log location**: `%APPDATA%/Godot/app_userdata/Power - Le Jeu de Stratégie/game_log.txt`

## Game Modes

- **Solo vs IA**: 1 human (Green) vs 1-3 AI players
- **Multijoueur local (Hotseat)**: 2-4 human players, turn-based with switch screen
- **Spectateur (4 IA)**: All 4 players are AI, human observes. Title screen button "4 IA / Observer"
