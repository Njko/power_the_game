# Power - Le Jeu de Strategie

Digital recreation of the 1981 Spear's Games board game **"Power"**, built with **Godot 4.6** (GDScript, GL Compatibility renderer).

A no-luck strategy game for 2-4 players where each round players simultaneously program up to 5 orders (movement/exchange), then resolution happens automatically.

## Screenshots

*Coming soon*

## Game Modes

- **Solo vs AI** - 1 human player vs 1-3 AI opponents
- **Local Multiplayer (Hotseat)** - 2-4 human players, turn-based with switch screen
- **Spectator (4 AI)** - All 4 players are AI, human observes

## How to Play

Each round follows 5 phases:

1. **Planning** - Program up to 5 orders (move units, exchange positions)
2. **Execution** - Orders resolve one by one with animations
3. **Conflict** - Combats resolve where opposing units meet; ties cause rebounds
4. **Collect Power** - Earn Power points for occupying enemy territory
5. **Capture Flags** - Infantry in an enemy HQ with superior power captures the flag

Win by capturing all enemy flags.

### Units

| Unit | Type | Power | Movement | Special |
|------|------|-------|----------|---------|
| Soldier | Land | 1 | 2 | Can capture flags |
| Regiment | Land | 3 | 2 | Can capture flags |
| Tank | Land | 2 | 3 | Fast ground unit |
| Heavy Tank | Land | 4 | 2 | Strongest ground unit |
| Fighter | Air | 1 | 4 | Fast air unit |
| Bomber | Air | 3 | 3 | Strong air unit |
| Destroyer | Naval | 2 | 3 | Fast naval unit |
| Cruiser | Naval | 4 | 2 | Strongest naval unit |
| Mega-Missile | Special | - | - | One-shot area attack |

### Board Layout

A 9x9 grid with 4 territories (Green, Blue, Yellow, Red), 5 islands, 12 sea lanes, and 4 headquarters at the corners. The central island (IX) connects all four quadrants.

## Running

Requires [Godot 4.6](https://godotengine.org/).

```bash
# Run the game
godot --path .

# Open in editor
godot --editor --path .
```

Target resolution: 1280x720

## Architecture

- **Data layer** (`scripts/core/`) - Pure data classes (GameState, BoardData, UnitData, etc.)
- **Logic layer** (`scripts/core/game_manager.gd`) - State machine controlling the game loop
- **Rendering layer** (`scripts/board/`, `scripts/units/`) - Procedural drawing via `_draw()`, 3D terrain heightmap
- **UI layer** (`scripts/ui/`) - Dynamically-built panels, phase timeline, order interface
- **AI** (`scripts/ai/ai_player.gd`) - Strategic AI with phases (develop/attack/capture/defend)

## Credits

Based on the original **Power** board game by Spear's Games (1981).

## License

This project is a fan recreation for educational and personal use.
