# CLAUDE.md
**Verdant Coil** — Godot 4.4.1 turn-based grid roguelike. GDScript only.
- **ExploreMode** — navigate grid, avoid hazards, reach Heartroot goal
- **BuilderMode** — level editor: create, validate, publish coils (maps)

Project root: `verdant-coil/`. Run entry: `Scenes/Heartroot/heartroot.tscn` (F5).

---

## MCP
Godot MCP active. Executable: `E:/Game Dev/Godot/4.4.1/Godot_v4.4.1-stable_win64.exe/Godot_v4.4.1-stable_win64.exe`
- Use `run_project` and `get_debug_output` to verify behaviour before claiming something works.
- Add `print()` at function entry, branching decisions, and silent failures during diagnosis. Remove once fixed.

---

## Session Protocol

**Start (REQUIRED):**
1. Read `devlog.md` in full.
2. Read the phase progress log if devlog references it.
3. State back: current phase, last completed stage, intended work.
4. Write no code until user confirms the plan.

**End (REQUIRED):**
1. Append session entry to `devlog.md`: what was done, files changed, outstanding issues.
2. State what the next session should start with.

**Devlog rules — STRICT:** Append only. Never edit, rewrite, or delete any existing entry. Treat as an immutable log.

---

## Architecture
Full reference: `Design docs/VERDANT_COIL_CLAUDE_CODE_BRIEF_1.md`

**Scene flow:** Heartroot hub → CoilSession.start_coil() → ExploreMode or BuilderMode → CoilSession.end_coil()

**Key autoloads:** `Grid` (tile math, TILE_SIZE=32), `GameFlags`, `CoilSession`, `ProfileManager`, `HealthSystem`, `UpgradeState`, `BuildInfo`

**Tile layers (index order is fixed):** 0=Base (walkable), 1=Walls (digestible), 2=Hazards (acid/sticky), 3=Markers (spawn/heartroot)

**Upgrade system:** `UpgradeState` autoload = equipped loadout. `UpgradeController` (Crawler child) = runtime toggle. `ProfileManager` tracks owned.

**Coil files:** JSON in `user://coils/` and `user://Published/`. Schema is FROZEN — do not change it.

---

## Claude Code Rules
- **Edit `.gd` files only** — no `.tscn`, `.tres`, file moves, or renames
- **Exception:** new `TileMapLayer` nodes may be added to `ExploreMode.tscn` when explicitly instructed
- **Do NOT refactor `builder_mode.gd` (~1415 lines) or `profile_manager.gd` (~1700 lines)**
- **Do NOT change the coil JSON schema** — breaks CoilIO, CoilValidator, and all saved coils
- **Do NOT implement unrequested features** — ask if scope is unclear
- Comments required on all non-trivial logic; write for a beginner reader
- Confirm API exists in **Godot 4.4.1** before using it
- Variant safety pattern required — see brief. Use `.call()`, `push_error` not `assert`, UK English, disconnect signals in `_exit_tree()`
- If retrying the same approach twice without progress, stop and ask

---

## Gotchas (add to this list when Claude makes a mistake)
- `max_renderable_lights` project setting defaults to 2 in testing builds — raise it explicitly
- `map_to_local()` returns tile top-left, not centre — add `Vector2(TILE_SIZE, TILE_SIZE) / 2`
- `add_child()` ordering matters for PointLight2D positioning — position after adding to tree
- Stale tile data can be baked into `.tscn` — verify map dimensions at runtime, not from scene

---

## Current Phase
**Phase 5 — Guard Nodule** ← CURRENT
See `devlog.md` for exact stage. Roadmap: Phase 5=Guard Nodule, 6=Move counter, 7=Campaign coils.

---

## Compact Instructions
Preserve: current phase and stage, last confirmed working state, active bug and symptoms, architecture decisions made this session, files modified this session.
Discard: diagnostic dead ends, superseded approaches, resolved bugs.
