# CLAUDE.md

**Verdant Coil** — Godot 4.4.1 turn-based grid roguelike.
- **ExploreMode** — navigate grid, avoid hazards, reach Heartroot goal
- **BuilderMode** — level editor: create, validate, publish coils (maps)

Project root: `verdant-coil/`. Open that folder as the Godot project.

## Running

- **F5** — run (entry: `Scenes/Heartroot/heartroot.tscn`)
- **Ctrl+Alt+D** — toggle dev mode (`GameFlags.dev_mode_enabled`)
- **Alt+D** — BuilderMode dev controls
- No external build system.

## MCP

Godot MCP active. Executable: `G:/Game Dev/Godot/4.4.1/Godot_v4.4.1-stable_win64.exe/Godot_v4.4.1-stable_win64.exe`
Use `run_project` and `get_debug_output` to verify behaviour before claiming something works.

**Debugging principle:** Add `print()` statements liberally during diagnosis. Printed output
is readable directly via `get_debug_output` — far faster than asking the user to describe
what they see. Always print: key values at function entry, branching decisions, and
unexpected-but-silent failures. Remove prints once the fix is confirmed.

---

## Session Start — REQUIRED

1. Read `devlog.md` in full (last completed, known-broken, next action).
2. Read the phase progress log if devlog references it.
3. State back: current phase, last completed stage, intended work.
4. **Write no code until user confirms the plan.**

## Session End — REQUIRED

1. Append a session entry to `devlog.md`: what was done, files changed, outstanding issues.
2. State what the next session should start with.

### Devlog Rules — STRICT

- **APPEND ONLY.** New entries at the bottom.
- **NEVER edit, rewrite, or delete any existing entry** — not even a typo.
- Treat it as an immutable git log.

---

## Architecture

### Scene Flow

```
Heartroot (hub) ──────────────────────────────────────────────┐
  ↓ CoilSession.start_coil(coil_dict, "hub"|"builder")         │
ExploreMode                                                     │
  → loads JSON coil into 4 TileMapLayers                       │
  → spawns Crawler at LAYER_MARKERS spawn tile                  │
  → win:  Crawler._win_and_return() → CoilSession.end_coil(true)  │
  → loss: HealthSystem → 0 → CoilSession.end_coil(false) ──────┘

BuilderMode ←→ Heartroot via CoilSession
  → Playtest: CoilSession.start_coil(coil_dict, "builder")
```

### Autoloads

| Singleton | File | Purpose |
|---|---|---|
| `Grid` | `System/grid.gd` | Tile↔world math; `TILE_SIZE = 32` |
| `GameFlags` | `System/game_flags.gd` | Dev mode + feature flags |
| `CoilSession` | `System/autoload/coil_session.gd` | Scene transitions, coil handoff |
| `ProfileManager` | `System/profile_manager.gd` | Profiles, resources, upgrade ownership |
| `HealthSystem` | `System/autoload/health_system.gd` | Global HP; emits `health_changed`, `died` |
| `UpgradeState` | `System/autoload/upgrade_state.gd` | Equipped upgrade loadout for current run |
| `BuildInfo` | `System/build_info.gd` | Build metadata/version |

### Coil Format

Stored in `user://coils/` (editable) and `user://Published/` (published):

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

- `System/coil_io.gd` — TileMapLayer ↔ JSON
- `System/coil_validator.gd` — spawn/heartroot presence, BFS reachability, biomass cap
- `System/coil_query.gd` — BFS pathfinding (used by validator)

### Tile Layers (order matters)

| Constant | Index | Contents |
|---|---|---|
| `LAYER_BASE` | 0 | Floor tiles (`walkable: bool` metadata) |
| `LAYER_WALLS` | 1 | Wall tiles (`digestible: bool` via Acid Sac) |
| `LAYER_HAZARDS` | 2 | `acid` (damages), `sticky` (skips input) |
| `LAYER_MARKERS` | 3 | Spawn + Heartroot markers |

Tile behaviour driven by atlas **custom metadata** (`walkable`, `digestible`, `hazard_type`).

### Upgrade System

| Representation | Scope | Role |
|---|---|---|
| `UpgradeState` (autoload) | Global | Equipped loadout for the run |
| `UpgradeController` (Crawler child) | Scene-local | Runtime toggle state |

Upgrades: `HARDENED_SKIN` (−1 acid damage), `ACID_SAC` (digest walls), `GHOST_TRAIL` (Phase 4, disabled).
`ProfileManager` tracks *owned*; `UpgradeState` tracks *equipped*.

### Large Files — Do Not Refactor

- `Scenes/BuilderMode/builder_mode.gd` (~1415 lines) — painting, undo/redo, validation, save/publish, playtest
- `System/profile_manager.gd` (~1700 lines) — profile CRUD, economy, upgrade ownership

---

## Current Status

See `devlog.md` — it is the live source of truth for phase, last completed work, and known issues. Always read it before starting.

---

## Engineering Principles (constraints, not suggestions)

**Rob Pike's Rules:** Don't optimise early. Measure before tuning. Prefer simple algorithms and simple data structures. Data structures dominate.

**SOLID:** Single responsibility. Open for extension, closed for modification. Substitutable components. No forced dependencies. Depend on abstractions.

---

## Claude Code Rules

- **Edit `.gd` files only** — no `.tscn`, `.tres`, file moves, or renames
- **Exception:** new `TileMapLayer` nodes may be added to `ExploreMode.tscn` when explicitly instructed for a planned phase
- **Do NOT refactor `builder_mode.gd` or `profile_manager.gd`**
- **Do NOT change the coil JSON schema** — breaks `CoilIO`, `CoilValidator`, and all saved coils
- **Do NOT implement unrequested features** — ask if scope is unclear
- Comments required on all logic; write for a beginner reader
- API must be confirmed for **Godot 4.4.1** before use
- Follow `Design docs/VERDANT_COIL_CLAUDE_CODE_BRIEF_1.md`: Variant safety, `.call()` pattern, UK English, `push_error` not `assert`, disconnect signals in `_exit_tree()`

---

## Roadmap

- ~~Phase 2 — Bug fixes~~
- ~~Phase 3 — Resolution shift (768×768 → 1024×576) + builder camera~~
- **Phase 4 — Fog of war + Ghost Trail** ← CURRENT
- Phase 5 — Guard Nodule (static cyclic enemy)
- Phase 6 — Move counter + par score
- Phase 7 — 8–10 campaign coils + unlock gates
- Phase 8 — Heartroot as home base / resource console
- Phase 9 — Time portals
- Phase 10+ — Async community features
