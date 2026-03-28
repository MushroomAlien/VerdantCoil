# Verdant Coil — Claude Code Project Brief
**Godot 4.4.1 | GDScript | Phase 1.6 (near-complete)**

---

## 1. What This Project Is

Verdant Coil is a tile-based, asynchronous builder-explorer game.

The player has **two modes**:
- **Builder Mode** — paint a tile map level (a "coil"), validate it, and publish it.
- **Explore Mode** — play through a coil: move a crawler across tiles, avoid hazards, reach the Heartroot goal.

These are connected by a **Heartroot Hub** — a lobby/menu screen where the player manages profiles, browses published levels, buys upgrades, and navigates to either mode.

The game loop is:
```
Heartroot Hub → BuilderMode → [Playtest] → ExploreMode → Win/Lose → return to origin
                                                                           ↓
                                                                  Heartroot Hub
```

---

## 2. Godot Version & Language Rules

- **Engine:** Godot 4.4.1 only. Do not use APIs from 4.3 or earlier, or 4.5+.
- **Language:** GDScript only. No C#.
- **Typing:** Strict static typing throughout. Every variable must have a type annotation or be
  explicitly typed on assignment. No implicit `var x = something` without a clear type.
- **Variant safety:** Dictionary values are ALWAYS read as `Variant` first, then checked with
  `typeof(v) == TYPE_X` before casting. This pattern is non-negotiable and exists in every script.
  Do not skip this step. Examples:

```gdscript
# CORRECT — always do this
var layers_v: Variant = data.get("layers", {})
if typeof(layers_v) != TYPE_DICTIONARY:
    return
var layers: Dictionary = layers_v as Dictionary

# WRONG — never do this
var layers: Dictionary = data["layers"]  # crashes if key missing or type wrong
```

---

## 3. Autoloads (Global Singletons)

These nodes are registered in **Project → Project Settings → Autoload** and are always present at
`/root/NodeName` for the entire lifetime of the application.

**Never access them directly by type.** Always use the guard pattern shown below.

| Autoload Name | Script Path | Purpose |
|---|---|---|
| `CoilSession` | `res://System/coil_session.gd` | Scene transitions + coil snapshot handoff |
| `HealthSystem` | `res://System/autoload/health_system.gd` | HP for the current run |
| `ProfileManager` | `res://System/profile_manager.gd` | Persistent player data (JSON on disk) |
| `GameFlags` | `res://System/game_flags.gd` | Dev mode toggles |
| `UpgradeState` | `res://System/upgrade_state.gd` | Runtime upgrade loadout for this run |
| `BuildInfo` | `res://System/build_info.gd` | Version string |
| `Grid` | `res://System/grid.gd` | Tile ↔ world coordinate math |

### Standard autoload access pattern (use this everywhere):

```gdscript
if has_node("/root/CoilSession"):
    var cs: Node = get_node("/root/CoilSession")
    if cs.has_method("start_coil"):
        cs.call("start_coil", coil_data, "hub")
```

**Why `call()` instead of direct method calls?**
We use `.call("method_name", args)` when calling into autoloads from other scripts. This is a
deliberate loose-coupling pattern — it avoids class_name circular dependencies and makes scripts
more resilient to structural changes. Do not replace these with typed direct calls.

---

## 4. Scene Overview & File Paths

```
res://
├── Scenes/
│   ├── Actors/
│   │   └── Crawler.tscn          # Area2D — the player character
│   ├── BuilderMode/
│   │   └── BuilderMode.tscn      # Node2D — tile painting screen
│   ├── World/
│   │   └── ExploreMode.tscn      # Node2D — play a coil
│   └── Heartroot/
│       └── heartroot.tscn        # Control — hub/lobby
├── System/
│   ├── autoload/
│   │   └── health_system.gd
│   ├── grid.gd
│   ├── coil_io.gd
│   ├── coil_query.gd
│   ├── coil_validator.gd
│   ├── coil_session.gd
│   ├── profile_manager.gd
│   ├── upgrade_state.gd
│   ├── game_flags.gd
│   └── build_info.gd
└── UI/
    ├── hearts_row.gd
    ├── upgrade_row.gd
    ├── resource_counters.gd
    ├── lose_overlay.gd
    └── dev_controls_root.gd
```

---

## 5. The Four TileMapLayers — Critical Architecture

**Every scene that works with tiles uses exactly four `TileMapLayer` nodes**, always in this order
and with these names and roles:

| Layer | Variable Name | Purpose |
|---|---|---|
| Base | `base_layer` | Walkable flesh floor. Crawler can only walk on this. |
| Walls | `walls_layer` | Solid or digestible walls. Block movement unless Acid Sac is active. |
| Hazards | `hazard_layer` | Acid pools and Sticky tiles. Apply effects on arrival. |
| Markers | `marker_layer` | Spawn point (`is_spawn = true`) and Heartroot goal (`is_goal = true`). |

These are **always exported variables** and **assigned in the Inspector**, never looked up by path.

```gdscript
@export var base_layer: TileMapLayer
@export var walls_layer: TileMapLayer
@export var hazard_layer: TileMapLayer
@export var marker_layer: TileMapLayer
```

The Crawler scene receives these references from ExploreMode when it is spawned:

```gdscript
var crawler: Area2D = CRAWLER_SCENE.instantiate()
crawler.base_layer   = base_layer
crawler.wall_layer   = walls_layer
crawler.hazard_layer = hazard_layer
crawler.marker_layer = marker_layer
add_child(crawler)
```

**Do not add a fifth layer. Do not rename these. Do not look them up by path.**

---

## 6. Tile Metadata — How Custom Data Works

Tiles carry custom data defined in the TileSet editor. The data is accessed via `TileData`.

**Always use the safe helper methods in `crawler.gd`** — never call `get_custom_data()` raw:

```gdscript
func _get_tile_data(layer: TileMapLayer, coords: Vector2i) -> TileData:
    if layer.get_cell_source_id(coords) == -1:
        return null
    return layer.get_cell_tile_data(coords)

func _get_bool(td: TileData, key: String, default_val: bool = false) -> bool:
    var v: Variant = td.get_custom_data(key)
    return (v as bool) if (v is bool) else default_val

func _get_str(td: TileData, key: String, default_val: String = "") -> String:
    var v: Variant = td.get_custom_data(key)
    return (v as String) if (v is String) else default_val

func _get_int(td: TileData, key: String, default_val: int = 0) -> int:
    var v: Variant = td.get_custom_data(key)
    return (v as int) if (typeof(v) == TYPE_INT) else default_val
```

**Custom data keys in use:**

| Key | Type | Layer | Meaning |
|---|---|---|---|
| `walkable` | bool | Base, Walls | Whether the crawler can enter this tile |
| `digestible` | bool | Walls | Wall can be dissolved by Acid Sac upgrade |
| `wall_kind` | String | Walls | "DIGEST" or "DIGESTIBLE" (fallback for digestible check) |
| `hazard` | String | Hazards | "acid" or "sticky" |
| `damage_per_step` | int | Hazards | Acid damage applied per turn |
| `slow_ticks` | int | Hazards | Number of inputs skipped after entering a Sticky tile |
| `is_spawn` | bool | Markers | Crawler spawns here |
| `is_goal` | bool | Markers | Heartroot — winning condition |
| `cost` | int | Any | Biomass cost of this tile (used by Builder) |

---

## 7. The Coil Data Format (Level JSON)

A "coil" is a level stored as a JSON dictionary. This is the format passed between Builder,
CoilSession, and ExploreMode.

```json
{
  "meta": {
    "schema_version": 1,
    "coil_schema_version": 1,
    "id": "20250328_142301_123",
    "title": "My Level",
    "biomass_used": 47,
    "biomass_cap": 100,
    "validated": true,
    "game_version": "0.1.0",
    "creator_profile_id": "20250101_120000_000",
    "creator_profile_name": "Player 1",
    "tileset": "",
    "validation": {
      "ok": true,
      "messages": [],
      "spawn": {"x": 5, "y": 5},
      "heart": {"x": 18, "y": 18},
      "biomass_used": 47,
      "biomass_cap": 100,
      "validator_version": 1,
      "timestamp": "2025-03-28T14:23:01Z"
    }
  },
  "layers": {
    "base":   [{"x": 5, "y": 5, "source_id": 0, "atlas_x": 0, "atlas_y": 0}, ...],
    "walls":  [...],
    "hazard": [...],
    "marker": [...]
  }
}
```

**Serialisation is handled by `CoilIO` (static methods):**

```gdscript
# Serialize all four layers into the layers dict
CoilIO.serialize_layer(base_layer)   # returns Array of cell Dicts

# Apply a coil dict back onto the four layers
CoilIO.apply_coil(data, base_layer, walls_layer, hazard_layer, marker_layer)
```

---

## 8. How Scenes Transition (CoilSession)

`CoilSession` is the only correct way to move between scenes. Do not call
`get_tree().change_scene_to_file()` directly except as a fallback inside `CoilSession` itself.

**Builder → ExploreMode (playtest):**
```gdscript
# In builder_mode.gd
var coil: Dictionary = _capture_coil()
get_node("/root/CoilSession").call("start_coil", coil, "builder")
# CoilSession stores the snapshot, then calls change_scene_to_file(explore_scene_path)
```

**ExploreMode startup:**
```gdscript
# In explore_mode.gd _ready()
if has_node("/root/CoilSession"):
    var cs: Node = get_node("/root/CoilSession")
    var data: Dictionary = {}
    if cs.has_method("consume_pending_coil"):
        var v: Variant = cs.call("consume_pending_coil")
        if typeof(v) == TYPE_DICTIONARY:
            data = v as Dictionary
    if not data.is_empty():
        _load_from_coil(data)
```

**ExploreMode → Win (return to origin):**
```gdscript
# In crawler.gd
get_node("/root/CoilSession").call("end_coil", true)
# CoilSession checks _origin: if "builder" → return_to_builder(); else → return_to_heartroot()
# On success from "hub" origin, also awards Nutrient via ProfileManager
```

**Hub → ExploreMode (play from library):**
```gdscript
# In heartroot.gd
cs.call("start_coil", coil, "hub")
```

**The `_origin` field in CoilSession** determines where to return after a run ends:
- `"builder"` — came from Builder (playtest). No reward. Return to Builder, restore map.
- `"hub"` — came from Hub library. Award Nutrient on success. Return to Heartroot.

---

## 9. Autoload API Reference (Key Methods)

### HealthSystem

```gdscript
hs.call("reset", 3)                        # reset to 3 HP for a new run
hs.call("apply_damage", 1, "acid")         # deal 1 damage, source label "acid"
hs.call("heal", 1)                         # restore 1 HP
hs.call("get_current")   # → int
hs.call("get_max")       # → int
hs.call("is_dead")       # → bool
# Signals: health_changed(current: int, max: int), died()
```

### ProfileManager

```gdscript
pm.call("get_current_profile_id")          # → String id
pm.call("get_current_profile")             # → Dictionary {id, display_name, nutrient, ...}
pm.call("get_resources")                   # → Dictionary {nutrient: int, sporeprint: int}
pm.call("get_owned_upgrades")              # → Dictionary {key: bool, ...}
pm.call("get_desired_loadout")             # → Dictionary {key: bool, ...}
pm.call("add_nutrient", 1)                 # add 1 nutrient (persists to disk, emits signal)
pm.call("add_sporeprint", 1)               # add 1 sporeprint
pm.call("buy_upgrade", "ACID_SAC", 5)      # → bool (deducts nutrient, persists)
pm.call("set_desired_loadout", loadout)    # save which upgrades player wants active
# Signals: resources_changed(nutrient, sporeprint), upgrades_changed(), profile_list_changed
# Valid upgrade keys (const array): ["HARDENED_SKIN", "ACID_SAC", "GHOST_TRAIL"]
```

### UpgradeState

```gdscript
us.call("load_active_loadout")             # resets all upgrades to false (run start)
us.call("has_hardened_skin")               # → bool
us.call("has_acid_sac")                    # → bool
us.call("has_ghost_trail")                 # → bool
us.call("set_runtime_overrides", true, false, false)  # dev override
# Signal: loadout_changed()
```

### GameFlags

```gdscript
gf.dev_mode_enabled                        # bool property, read directly
gf.call("toggle_dev_mode")
# Signal: dev_mode_changed(enabled: bool)
```

### Grid (used via preload, not autoload-style calls)

```gdscript
const GridUtil := preload("res://System/grid.gd")
GridUtil.to_world(Vector2i(5, 3))          # → Vector2 (world centre of tile)
GridUtil.to_tile_coords(position)          # → Vector2i (tile from world pos)
GridUtil.snap_position(position)           # → Vector2 (snapped world pos)
# TILE_SIZE = 32 (pixels per tile)
```

---

## 10. The Crawler (Player Character)

- **Scene:** `res://Scenes/Actors/Crawler.tscn`
- **Root node type:** `Area2D`
- **Script:** `crawler.gd`
- **Child nodes:** `Sprite2D`, `CollisionShape2D`, `Camera2D`, `UpgradeController`

**Movement is turn-based:**
- One tile per key press (arrow keys / WASD via InputMap actions `move_up`, `move_down`, `move_left`, `move_right`).
- Movement is locked during tween (`_is_moving` guard).
- `_skip_inputs` counter handles Sticky slow effect (skips N inputs after entering Sticky tile).

**Movement validation order (in `_start_move()`):**
1. Check bounds against `base_layer.get_used_rect()`
2. Check Base tile exists and is `walkable = true`
3. Check Wall tile — blocks unless `walkable = true` OR (`digestible = true` AND Acid Sac is active)
4. If all pass → tween to new position → call `_on_arrived_at(tile)`

**On arrival (`_on_arrived_at` → `_apply_tile_effects`):**
1. Hazard effects (acid damage, sticky slow)
2. Dissolve digestible wall if Acid Sac active
3. Goal check — if `is_goal = true` → `_win_and_return()`

**UpgradeController** is a child Node of Crawler:
```gdscript
var uc: Node = crawler.get_node_or_null("UpgradeController")
uc.call("has_upgrade", uc.Upgrade.ACID_SAC)    # → bool
uc.call("toggle_upgrade", uc.Upgrade.ACID_SAC)
# Signal: upgrade_changed(upgrade: Upgrade, value: bool)
# Enum: Upgrade { HARDENED_SKIN = 0, ACID_SAC = 1, GHOST_TRAIL = 2 }
```

**Ability toggle input** (keys 1/2/3) is queued via `_request_toggle(index)` → deferred to
`_apply_pending_toggle()`. Never toggle synchronously inside an input callback — this caused
re-entrancy issues and was explicitly fixed.

---

## 11. Builder Mode Key Concepts

**Brush system:**
- `BrushRegistry` (Resource) holds an array of `BrushEntry` (Resource) items.
- Each `BrushEntry` defines: `display_name`, `rule_profile` (BASE/WALL/POOL/MARKER/ERASER),
  `target_layer` (0–3), `source_id`, `atlas_coords`, `hazard_kind`, `icon`.
- The palette buttons map 1:1 to `brush_registry.brushes[i]` by index order.
- `_q` is a locally instantiated `CoilQuery` used for tile placement validation queries.

**Validation rules (enforced by `CoilValidator`):**
- Exactly one Spawn tile (marker with `is_spawn = true`)
- Exactly one Heartroot tile (marker with `is_goal = true`)
- BFS path must exist from Spawn to Heartroot (walls block; digest walls treated as passable)
- Biomass used must not exceed cap (unless Dev Mode + IgnoreBiomassLimit is active)

**Biomass** is the "budget" for how many tiles a builder can place. Each tile has a `cost` custom
data int. `_recalc_biomass()` sums all tile costs across all layers.

**Undo/redo** stacks exist (`undo_stack`, `redo_stack` arrays) and are partially implemented.
Do not remove or restructure these.

**Publish flow:** Builder → strict validate → write JSON to `user://Published/` →
upsert `user://Published/manifest.json` → chip turns green.

---

## 12. UI Scripts and What They Listen To

These scripts are attached to HUD nodes inside ExploreMode and Heartroot. They are passive
listeners — they do not push state, they only react to signals.

| Script | Attached to | Listens to | Purpose |
|---|---|---|---|
| `hearts_row.gd` | `HBoxContainer` in ExploreMode HUD | `HealthSystem.health_changed` | Shows HP as heart icons |
| `upgrade_row.gd` | `HBoxContainer` in ExploreMode HUD | `UpgradeController.upgrade_changed` + `UpgradeState.loadout_changed` | Shows active upgrades |
| `resource_counters.gd` | `HBoxContainer` in ExploreMode HUD | `ProfileManager.resources_changed` + `current_profile_changed` | Shows Nutrient + Sporeprint |
| `lose_overlay.gd` | `Control` in ExploreMode HUD | `HealthSystem.died` | Shows death screen with Retry/Exit |
| `dev_controls_root.gd` | DevControls panel in BuilderMode | `GameFlags.dev_mode_changed` | Shows/hides dev tools |

**Node path exports:** UI scripts use `@export_node_path` for their child references, not hardcoded
strings. These are assigned in the Inspector. Example:

```gdscript
@export_node_path("Label") var nutrient_label_path: NodePath
@onready var _nutrient_label: Label = get_node_or_null(nutrient_label_path)
```

**Always disconnect signals in `_exit_tree()`** to prevent stale connections on scene reload:

```gdscript
func _exit_tree() -> void:
    if _health_system != null:
        if _health_system.is_connected("died", Callable(self, "_on_died")):
            _health_system.disconnect("died", Callable(self, "_on_died"))
```

---

## 13. Persistence — Where Data Lives on Disk

```
user://
├── Profiles/
│   ├── manifest.json          # { version, current_profile_id, items:[{id, display_name, ...}] }
│   └── profile_<id>.json      # { nutrient, sporeprint, owned_upgrades, desired_loadout, ... }
├── coils/
│   └── coil_<timestamp>.json  # saved builder levels (draft or validated)
└── Published/
    ├── manifest.json          # { version, items:[{path, title, published_at, biomass_used, ...}] }
    └── coil_<timestamp>.json  # published levels
```

**All persistence goes through `ProfileManager`.** Do not read/write profile JSON directly from
other scripts. Use the public API (`add_nutrient`, `buy_upgrade`, `set_desired_loadout`, etc.).

**Profile JSON fields:**

```json
{
  "id": "20250328_120000_000",
  "display_name": "Player 1",
  "nutrient": 12,
  "sporeprint": 3,
  "owned_upgrades": { "HARDENED_SKIN": true, "ACID_SAC": false, "GHOST_TRAIL": false },
  "desired_loadout": { "HARDENED_SKIN": true },
  "last_opened_coil": "user://coils/coil_20250328_141500.json",
  "last_used_at": "2025-03-28T14:15:00Z"
}
```

---

## 14. Known Architecture Gap (Phase 1.6 Loose End)

`UpgradeState.load_active_loadout()` **currently hard-resets all upgrades to `false`** on every
run start, regardless of what the player owns in `ProfileManager`.

The intended behaviour is: at run start, read `desired_loadout` from `ProfileManager`, cross-check
against `owned_upgrades`, and set the active booleans accordingly.

The bridge between these two systems is the **next thing to implement**. The scaffolding is in
place on both ends; the connection just needs to be made in `load_active_loadout()`.

---

## 15. Coding Standards & Style Rules

**Follow these in all new and modified code:**

1. **Rob Pike's Rules apply** — don't optimise early, don't get fancy, keep data structures simple.
   A flat Dictionary beats a clever recursive structure every time in this codebase.

2. **SOLID principles apply** — particularly Single Responsibility. Each script has one clear job.
   `CoilIO` does IO. `CoilValidator` does validation. `builder_mode.gd` does UI wiring and
   orchestration. Do not bleed responsibilities across files.

3. **Every script section must have inline comments** explaining what and why, at the block level.
   Not every single line, but every logical section.

4. **No magic strings for upgrade keys.** Use the `UPGRADE_KEYS` constant array in `ProfileManager`
   and the `Upgrade` enum in `UpgradeController`. If you add a new upgrade, add it to both.

5. **No direct `$NodeName` lookups** for nodes that might not exist. Always use
   `get_node_or_null("NodeName")` and null-check the result.

6. **No `position` math or manual layout** in code for UI nodes. Use Container nodes and anchor
   properties in the Inspector instead.

7. **`push_error()` not `assert()`** for missing required references. Asserts crash in debug;
   `push_error` logs and continues gracefully.

8. **Check for the feature before calling it:**
   ```gdscript
   if cs.has_method("consume_pending_coil"):
       cs.call("consume_pending_coil")
   ```
   This is the established pattern for cross-script calls into autoloads.

9. **Tile mutations must be deferred** when called from within a movement/input callback to avoid
   re-entrancy issues with the TileMap:
   ```gdscript
   wall_layer.call_deferred("erase_cell", tile)
   ```

10. **UK/Australian English** in all comments and strings (e.g., "colour", "initialise",
    "behaviour").

---

## 16. Things Claude Code Must NOT Do

- Do not call `get_tree().change_scene_to_file()` directly. Use `CoilSession`.
- Do not access Dictionary values without a `typeof()` guard first.
- Do not add new autoloads without confirming it is the right architectural choice.
- Do not modify the coil JSON schema without updating both `CoilIO` and `CoilValidator`.
- Do not hardcode tile layer indices (0–3). Use the named exported variables.
- Do not remove or bypass the `_is_moving` guard in `crawler.gd`.
- Do not replace `.call("method", args)` with direct typed calls into autoloads.
- Do not create new systems without confirming they align with the current phase plan.
- Do not use `@onready` for nodes that might not exist — use `get_node_or_null` instead.
- Do not forget to disconnect signals in `_exit_tree()` for any script that connects in `_ready()`.

---

## 17. Quick Reference — What Happens on Scene Load

### ExploreMode `_ready()`:
1. Consume coil from `CoilSession.consume_pending_coil()` → rebuild TileMapLayers
2. Call `UpgradeState.load_active_loadout()` to reset/set upgrades for this run
3. Call `HealthSystem.reset(3)` to set HP to 3
4. Instantiate `Crawler.tscn`, assign layer refs, set spawn position, `add_child`
5. Find `UpgradeRow` HUD node, call `set_controller(crawler.UpgradeController)`
6. Call `_apply_upgrade_state_to_crawler(crawler)` to sync UpgradeState → UpgradeController

### BuilderMode `_ready()`:
1. Sanity-check all layer refs
2. Clear undo/redo stacks
3. Wire all button signals
4. Build palette from `brush_registry.brushes`
5. Connect `GameFlags.dev_mode_changed`
6. Apply "Start With Flesh" if checkbox is on
7. Call `_restore_pending_coil_if_any()` — restores snapshot if returning from playtest
8. Call `_recalc_biomass()` and `_refresh_validation_state()`

### Heartroot `_ready()`:
1. Wire all button signals
2. Subscribe to `ProfileManager` signals
3. Call `_refresh_profiles()` and `_refresh_library()`
4. Call `_refresh_version_label()`
