# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Digital recreation of the 1981 Spear's Games board game "Power" built with **Godot 4.6** (GDScript, GL Compatibility renderer). A no-luck strategy game for 2-4 players where each round players simultaneously program up to 5 orders (movement/exchange), then resolution happens automatically. Original rules are in `regles_power.htm`.

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
- **UI layer** (`scripts/ui/`): Dynamically-built controls (no .tscn for panels). `OrderPanel` builds its UI in `_build_ui()`.
- **AI** (`scripts/ai/ai_player.gd`): `RefCounted`, generates `Order` arrays. No Node dependency.

### Game Loop (per round)

```
PLANNING → EXECUTION → CONFLICT → COLLECT_POWER → CAPTURE_FLAGS → next round
```

Phases 2-6 run asynchronously via `_run_resolution_phases()`:
```gdscript
await _phase_execution()      # Execute orders + play move animations
await _phase_conflict()       # Resolve combats + play combat animations
await _phase_collect_power()  # Award Power for territory occupation
await _phase_capture_flags()  # Check flag captures + play flag animations
```

### Signal Flow

`GameManager` emits → `main.gd` receives and updates UI. `BoardRenderer` emits `sector_clicked`/`sector_hovered` → `main.gd` delegates to `OrderPanel` during PLANNING phase. `AnimationManager` emits `animation_finished` → `GameManager` awaits it between phases.

### Board Graph

`BoardData` builds a graph of ~60 sectors: 36 territory sectors (4 territories × 3×3 grid), 4 HQs, 5 islands, 12 sea sectors. Adjacencies are hardcoded. Pathfinding via BFS in `find_path()` / `get_reachable_sectors()`. Sector accessibility depends on unit type (land/air/naval).

## GDScript Conventions

- **Strict typing required**: Godot 4.6 rejects `:=` with untyped returns (Dictionary access, `.find()`, `.size()` on untyped arrays). Always use `var x: Type = ...` instead of `var x := ...` when the RHS involves Variant.
- **French throughout**: All variable names, comments, UI text, and game terminology in French.
- **Static lookups**: `GameEnums` contains all game constants as static functions (`get_unit_power()`, `get_unit_max_move()`, etc.).
- **Factory methods**: `Order.create_move()` and `Order.create_exchange()` for order creation.
- **Transient state via metadata**: `unit.set_meta("origin_sector", id)` for per-turn tracking (rebound logic).

## Key Gotchas

- **Animation await deadlock**: `play_all()` must defer `animation_finished` emission when queue is empty, otherwise the `await` on the calling side misses the synchronous signal. See `_emit_finished_deferred()`.
- **Arbiter rotation**: Affects both planning order AND execution order. Built from `arbiter_index % active.size()`.
- **Flag capture requires infantry**: Only `SOLDIER` or `REGIMENT` in the enemy HQ triggers capture, plus strictly greater power than defender.
- **Board uses `_unhandled_input`**: So CanvasLayer UI panels get click priority over the board.
- **Single scene**: `scenes/main.tscn` is the only scene file. Title screen and player switch screen are created dynamically as child nodes.
