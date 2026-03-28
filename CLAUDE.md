# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Verdant Coil** is a Godot 4.4.1 turn-based grid roguelike with two modes:
- **ExploreMode** — player navigates a grid map, avoids hazards, reaches the Heartroot goal
- **BuilderMode** — in-game level editor for creating, validating, and publishing coils (maps)

The project root is `verdant-coil/` inside this repository. Open that folder as the Godot project.

## Running the Game

- Open `verdant-coil/` in **Godot 4.4.1**
- Press **F5** to run (starts at `Scenes/Heartroot/heartroot.tscn`)
- Press **Ctrl+Alt+D** in-game to toggle developer mode (`GameFlags.dev_mode_enabled`)
- In BuilderMode, press **Alt+D** to open dev controls

There is no external build system — this is a pure Godot project.

## Architecture Overview

### Scene Flow

```
Heartroot (hub) ──────────────────────────────────────────────────┐
  ↓ CoilSession.start_coil(coil_dict, "hub"|"builder")             │
ExploreMode                                                         │
  → loads JSON coil into 4 TileMapLayers                           │
  → spawns Crawler at LAYER_MARKERS spawn tile                      │
  → win: Crawler._win_and_return() → CoilSession.end_coil(true)    │
  → loss: HealthSystem reaches 0 → CoilSession.end_coil(false) ────┘

BuilderMode ←→ Heartroot via CoilSession
  → Playtest: CoilSession.start_coil(coil_dict, "builder")
```

### Autoload Singletons (always available)

| Singleton | File | Purpose |
|---|---|---|
| `Grid` | `System/grid.gd` | Tile↔world coordinate math; `TILE_SIZE = 32` |
| `GameFlags` | `System/game_flags.gd` | Dev mode toggle and feature flags |
| `CoilSession` | `System/autoload/coil_session.gd` | Scene transitions and coil handoff between modes |
| `ProfileManager` | `System/profile_manager.gd` | JSON-persisted player profiles, resources, upgrades |
| `HealthSystem` | `System/autoload/health_system.gd` | Global HP tracker; emits `health_changed` / death signals |
| `UpgradeState` | `System/autoload/upgrade_state.gd` | Active upgrade loadout across scenes |
| `BuildInfo` | `System/build_info.gd` | Build metadata/version |

### Coil (Map) Format

Coils are JSON files stored in `user://coils/` (editable) and `user://Published/` (published):

```json
{
  "meta": { "name": "...", "author": "...", "biomass": 0 },
  "layers": {
    "base":   [ [atlas_x, atlas_y], ... ],
    "walls":  [ [atlas_x, atlas_y] | null, ... ],
    "hazard": [ ... ],
    "marker": [ ... ]
  }
}
```

Key coil system files:
- `System/coil_io.gd` — TileMapLayer ↔ JSON serialization
- `System/coil_validator.gd` — validates spawn/heartroot presence, BFS reachability, biomass cap
- `System/coil_query.gd` — BFS pathfinding used by validator

### Tile Layers (load order matters)

| Constant | Index | Contents |
|---|---|---|
| `LAYER_BASE` | 0 | Floor tiles (walkable/non-walkable via metadata) |
| `LAYER_WALLS` | 1 | Wall tiles (digestible via Acid Sac upgrade) |
| `LAYER_HAZARDS` | 2 | Hazard tiles: `acid` (damages), `sticky` (skips input) |
| `LAYER_MARKERS` | 3 | Spawn marker, Heartroot goal marker |

Tile behavior is driven by **custom metadata** on atlas tiles (e.g., `walkable: bool`, `digestible: bool`, `hazard_type: String`).

### Upgrade System

Three upgrades with two representations:
- **`UpgradeState`** (autoload) — the globally active loadout
- **`UpgradeController`** (scene-local in Crawler) — runtime toggle state

Upgrades: `HARDENED_SKIN` (reduces acid damage), `ACID_SAC` (digest walls), `GHOST_TRAIL` (unimplemented).

`ProfileManager` tracks *owned* upgrades; `UpgradeState` tracks *equipped* upgrades for the current run.

### Key Large Files

- `Scenes/BuilderMode/builder_mode.gd` (~1415 lines) — brush painting, undo/redo stack, live validation, save/load/publish, playtest handoff
- `System/profile_manager.gd` (~1700 lines) — profile CRUD, resource economy, upgrade ownership

Both files are well-commented internally.

---

## Current Status

**Active Phase: Phase 4 — Fog of War + Ghost Trail** (Phase 3 complete)

### Phase 2 Bug Fixes — Status
1. ~~**Death awards win reward**~~ — Already correctly implemented. `coil_session.gd:end_coil()` guards `if success and (_origin == "hub")`. `lose_overlay.gd` calls `end_coil(false)` on exit. No code change needed.
2. ✅ **`UpgradeState.load_active_loadout()` fixed** — Now reads `desired_loadout` cross-checked against `owned_upgrades` from `ProfileManager`. Falls back to all-off if ProfileManager unavailable.
3. ✅ **Ghost Trail disabled** — Toggle blocked in `crawler.gd`. Icon always renders as `locked_modulate` in `upgrade_row.gd`.

---

## Engineering Principles

All code in this repository follows these principles. They are not aspirational — they are constraints.

### Rob Pike's 5 Rules of Programming

1. **You can't tell where a program is going to spend its time.** Bottlenecks occur in surprising places, so don't try to second guess and put in a speed hack until you've proven that's where the bottleneck is.
2. **Measure.** Don't tune for speed until you've measured, and even then don't unless one part of the code overwhelms the rest.
3. **Fancy algorithms are slow when n is small, and n is usually small.** Fancy algorithms have big constants. Until you know that n is frequently going to be big, don't get fancy. (Even if n does get big, use Rule 2 first.)
4. **Fancy algorithms are buggier than simple ones, and they're much harder to implement.** Use simple algorithms as well as simple data structures.
5. **Data dominates.** If you've chosen the right data structures and organised things well, the algorithms will almost always be self-evident. Data structures, not algorithms, are central to programming.

### SOLID Principles

- **Single Responsibility:** A class/function should have only one reason to change.
- **Open/Closed:** Code should be open for extension but closed for modification.
- **Liskov Substitution:** You should be able to swap a component with its "child" without breaking the system.
- **Interface Segregation:** Don't force a module to depend on things it doesn't use.
- **Dependency Inversion:** Depend on abstractions, not hard-coded specifics.

---

## Claude Code Rules

- **Only edit `.gd` script files** unless explicitly told otherwise
- **Do NOT move, rename, or delete any files**
- **Do NOT modify `.tscn` or `.tres` files**
- **Do NOT refactor `builder_mode.gd` or `profile_manager.gd`** — too large, too risky
- **Do NOT change the coil JSON schema** — any change requires updates to `CoilIO`, `CoilValidator`, and every saved coil
- Always add inline comments explaining logic; write for a beginner reader
- Godot version is **4.4.1** — confirm any API before using it
- Follow all coding standards in `Design docs/VERDANT_COIL_CLAUDE_CODE_BRIEF_1.md` (Variant safety, `.call()` pattern, UK English, `push_error` not `assert`, signal disconnect in `_exit_tree()`, etc.)

---

## Roadmap

- ~~Phase 2 — Fix three known bugs~~
- ~~Phase 3 — Resolution shift (768×768 → 1024×576) + scrollable builder camera~~
- **Phase 4 — Fog of war (LightMaskLayer) + Ghost Trail light trail** ← CURRENT
- Phase 5 — First static enemy (Guard Nodule, cyclic attacker)
- Phase 6 — Move counter + par score
- Phase 7 — 8–10 handcrafted campaign coils + unlock gates
- Phase 8 — Heartroot redesign as home base / resource console
- Phase 9 — Time portals
- Phase 10+ — Multiplayer / async community features
