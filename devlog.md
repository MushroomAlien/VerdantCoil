# Verdant Coil — Development Log

A running record of each work session: what was done, what was decided, and what comes next.
This file is append-only. Sections are never deleted.

---

## Session 1 — 2026-03-28

### What We Did
- Returned to the project after a break of several months.
- Reviewed the codebase and all design documentation to get back up to speed.
- Read the Claude Code brief (`Design docs/VERDANT_COIL_CLAUDE_CODE_BRIEF_1.md`) and identified stale information (some file paths in the brief point to old locations — the real folder tree is the source of truth).
- Created `CLAUDE.md` to give future Claude Code sessions a fast orientation to the project.

### Decisions Made
- **Scraped the old two-phase roadmap.** Replaced with a numbered phase plan where each phase targets one specific feature. Phases 2–9 cover single-player; Phase 10+ covers multiplayer.
- **Lighting: keep Method 2 (Godot engine lights) as-is for now.** The Inspector-configured GlowLight/WallLight on the Crawler was reportedly working. No code changes to lighting yet. Method 3 (grid flood-fill) is deferred until line-of-sight enemies exist in Phase 11+.
- **Single-player campaign first.** The async multiplayer vision is the endgame, but the solo loop has to be proven fun before building community infrastructure.
- **Ghost Trail stays wired but gets cleanly disabled** (greyed button, tooltip) until Phase 4 when lighting exists and Ghost Trail's behaviour (light spores on walked tiles) can be implemented properly.
- **Resolution shift (768×768 → 1024×576) goes in Phase 3**, before more UI is built on the wrong canvas size.

### Known Bugs Logged
1. Death awards win reward (nutrient given on death — should only award on success)
2. `UpgradeState.load_active_loadout()` resets all upgrades to `false` instead of reading `desired_loadout` from `ProfileManager`
3. Ghost Trail button is active in UI but the upgrade does nothing

### Active Phase
**Phase 2 — Bug Fixes** (not yet started; planning session only)

### Next Session Should
- Fix Bug 1: trace `end_coil` → nutrient award path, add success gate
- Fix Bug 2: implement `load_active_loadout()` correctly
- Fix Bug 3: disable Ghost Trail button cleanly
- Run a play-through to confirm all three fixes hold

---

## Session 2 — 2026-03-28

### What We Did
Phase 2 bug fixes. Read all relevant files before touching anything.

**Bug 1 (Death awards win):** Investigation showed this is already correctly implemented.
`coil_session.gd:end_coil()` guards `if success and (_origin == "hub")` before awarding nutrient.
`lose_overlay.gd` calls `end_coil(false)` on Exit and `retry_last_coil()` on Retry (no reward).
`crawler._on_global_death()` only blocks input; it does not call `end_coil`.
No code change needed. Marked as resolved in CLAUDE.md.

**Bug 2 (UpgradeState hard-reset):** Fixed in `System/autoload/upgrade_state.gd`.
`load_active_loadout()` now reads `get_owned_upgrades()` and `get_desired_loadout()` from
ProfileManager via the safe `.call()` pattern, type-guards both return values, and sets each
upgrade boolean to `owned AND desired`. Falls back to all-off with `push_error` if ProfileManager
is unavailable.

**Bug 3 (Ghost Trail does nothing):** Fixed in two files.
- `Scenes/Actors/crawler.gd`: `_request_toggle(index)` now returns early for index 2 (Ghost Trail)
  with a print message. The toggle is completely blocked — no turn consumed, no signal fired.
- `Scenes/UI/upgrade_row.gd`: Added `locked_modulate` export colour (dark, semi-transparent).
  Added `_set_icon_locked()` helper. All three refresh paths (`_refresh_from_state`,
  `_refresh_from_controller`, `_on_controller_upgrade_changed`) now call `_set_icon_locked`
  for the Ghost Trail icon instead of `_set_icon`, so it always appears visually unavailable.

### Files Changed
- `System/autoload/upgrade_state.gd`
- `Scenes/Actors/crawler.gd`
- `Scenes/UI/upgrade_row.gd`
- `CLAUDE.md` (phase status updated to Phase 3)

### Active Phase
**Phase 3 — Resolution Shift (768×768 → 1024×576) + Scrollable Builder Camera**

### Next Session Should
- Shift project viewport to 1024×576 in `project.godot`
- Update all UI scenes for new aspect ratio (Heartroot, ExploreMode HUD, BuilderMode)
- Add scrollable/pannable camera to BuilderMode
- Update default coil grid dimensions to match new viewport (32×18 tiles)

---

## Session 3 — 2026-03-28 (continued)

### What We Did

**Upgrade shop (Heartroot):**
- Identified that `upgrades_btn` was declared but never connected in `_ready()`.
- Built a minimal programmatic upgrade shop `Window` entirely in GDScript (no .tscn).
  - `UPGRADE_DEFS` constant defines each upgrade (key, display, description, cost, locked flag).
  - Window is single-instance guarded via `_upgrades_window` ref.
  - Shows Nutrient balance, Buy button (disabled if insufficient funds), Slot/Remove toggle.
  - Ghost Trail always shows as "Locked".
  - Costs: Hardened Skin 3N, Acid Sac 5N.

**Equipped vs Active upgrade split (design decision + implementation):**
- User identified that "equip in shop" and "activate mid-run" are two separate concepts
  that were conflated. Resolved with a clear two-phase system:
  - **Slotted** (shop): bring up to 3 upgrades into a run. Set via "Slot"/"Remove" buttons.
  - **Active** (mid-run): press 1/2/3 to switch ON. Costs one turn. Starts inactive.
- `upgrade_controller.gd`: added `_equipped` dict + `set_equipped()` + `is_equipped()`.
  `toggle_upgrade()` now silently returns if not equipped (no signal, no turn consumed).
- `upgrade_state.gd`: added `_equipped` dict. `load_active_loadout()` populates equipped
  from ProfileManager (owned ∩ desired_loadout). All `_active` booleans always start false.
  Added `is_equipped(key)` public method.
- `explore_mode.gd`: `_apply_upgrade_state_to_crawler()` now pushes equipped state to
  UpgradeController instead of syncing active booleans.
- `crawler.gd`: `_apply_pending_toggle()` checks `is_equipped()` before consuming a turn;
  pressing an unslotted key does nothing and costs nothing.
- `upgrade_row.gd`: three visual states — active (bright), equipped-inactive (medium grey),
  not-slotted (dim). Added `equipped_modulate` export. All refresh paths updated.
- `heartroot.gd`: button text changed from "Equip"/"Unequip" to "Slot"/"Remove".

### Files Changed
- `Scenes/Heartroot/heartroot.gd`
- `System/upgrade_controller.gd`
- `System/autoload/upgrade_state.gd`
- `Scenes/World/explore_mode.gd`
- `Scenes/Actors/crawler.gd`
- `Scenes/UI/upgrade_row.gd`

### Decisions Made
- Upgrade slot limit is implicitly 3 (one per hotkey). Explicit limit enforcement deferred
  until there are enough upgrades to make the choice interesting (Phase 7+).
- Ghost Trail hard-excluded from the equipped set in code until Phase 4.
- Pressing an unslotted upgrade key costs no turn — dead keys are silent.

### Active Phase
**Phase 3 — Resolution Shift (768×768 → 1024×576) + Scrollable Builder Camera**

### Next Session Should
- Change viewport in `project.godot` (768×768 → 1024×576)
- Check whether existing UI anchor setups survive the new aspect ratio automatically
- User will need to fix any UI scenes that break in the Godot editor
- Add pan/scroll camera to BuilderMode (pure GDScript)
- Update default new-coil grid size to 32×18 tiles

---

## Session 4 — 2026-03-28 (continued)

### What We Did

**Phase 3: Resolution Shift + Scrollable Builder Camera** — completed.

**Viewport change (`project.godot`):** `viewport_width=1024`, `viewport_height=576`. Done in previous session context.

**Builder camera (pure GDScript, no .tscn edit):**
- Added four pan-state vars to `builder_mode.gd`: `_camera`, `_is_panning`, `_pan_mouse_origin`, `_pan_cam_origin`.
- End of `_ready()` now creates a `Camera2D`, positions it at the centre of the default canvas
  (`start_flesh_rect.size × Grid.TILE_SIZE × 0.5`), and calls `make_current()`.
- `_unhandled_input()` gains a middle-mouse block at the top:
  - `MOUSE_BUTTON_MIDDLE` press → records origins, sets `_is_panning = true`.
  - `MOUSE_BUTTON_MIDDLE` release → clears `_is_panning`.
  - `InputEventMouseMotion` while panning → `camera.position = _pan_cam_origin - (mouse - _pan_mouse_origin)`, consumed with `set_input_as_handled()`.
  - Pan events return early before paint/erase logic, so no accidental tile changes while panning.

**Default canvas size:** `start_flesh_rect` default updated from `Vector2i(24, 24)` to `Vector2i(32, 18)` to match the new 1024×576 viewport at 32 px tiles.

**Heartroot hub layout (editor — `heartroot.tscn`):** Fixed UI breakage from the aspect ratio shift.
SafeArea margins corrected, ItemList minimum sizes set, all buttons now visible and functional at 1024×576.
Three-panel layout (Profiles / Actions / Published Levels) renders correctly in-game.

### Files Changed
- `project.godot` (viewport dimensions — prior session)
- `Scenes/BuilderMode/builder_mode.gd` (camera creation, pan state, `start_flesh_rect` default)
- `Scenes/Heartroot/heartroot.tscn` (SafeArea margins, ItemList min sizes — editor fix)
- `CLAUDE.md` (phase status updated to Phase 4)

### Known Outstanding
- User should open the project in Godot editor and check all UI scenes (Heartroot, ExploreMode HUD, BuilderMode toolbar) for anchor/layout breakage caused by the aspect ratio change. Any pixel-locked anchors may need manual correction in the editor.
- ~~Heartroot hub~~ — fixed in editor this session (SafeArea margins, ItemList min sizes).
- ExploreMode HUD and BuilderMode toolbar not yet verified at new resolution — check on next entry into those scenes.

### Active Phase
**Phase 4 — Fog of War (LightMaskLayer) + Ghost Trail**

### Next Session Should
- Implement fog-of-war: LightMaskLayer management, three tile visibility states (unseen/seen/visible)
- Crawler emits a light radius; BFS flood-fill from crawler position blocked by walls
- Persist `seen_ever` set per run (dim previously-visited tiles)
- Implement Ghost Trail upgrade behaviour: leave bioluminescent spores on walked tiles

---

## Session 6 — 2026-04-01

### What We Did

Fixed two lighting bugs that made the game look broken at spawn and near wall tiles.

**Bug 1 — Dark area follows player at startup (shadow init lag)**

Root cause: Godot 4's shadow depth buffer for `PointLight2D` with `shadow_enabled=true` starts
as "fully dark" for any tile the light hasn't swept through on frame 0.  This caused the entire
map to appear near-black at spawn, only "burning in" to correct lighting as the player moved.

Fix: In `_apply_crawler_lights()`, set `glow.shadow_enabled = false` immediately, then
re-enable it after one `process_frame` via the new `_enable_glow_shadow_next_frame()` coroutine.
This lets Godot rasterise the initial shadow map from a "fully lit" baseline, so frame 1 onward
has a warm shadow buffer rather than a cold/black one.

**Bug 2 — Oversized V-shaped shadow wedges from wall tiles**

Root cause: Wall tiles `(8,10)` and `(8,22)` in `flesh_tile.tres` had full `32×32` square
occluder polygons (`(-16,-16)…(16,16)`), producing enormous shadow wedges visible behind
adjacent walls.

Fix: Cannot edit `.tres` files (CLAUDE.md rule), so patched at runtime via the new
`_patch_wall_occluders()` function.  Replaces both polygons with an `8×8` centre square
using `TileData.set_occluder(layer, polygon)`.  Called once in `_ready()` after fog init.

**Pre-existing fix (previous session)**

`FogManager.init()` already sets `_fog_layer.light_mask = 0` to prevent GlowLight
illuminating the dark-navy fog tiles — this fix remains in place and is working correctly.

### Files Changed
- `Scenes/World/explore_mode.gd`
  - `_apply_crawler_lights()`: disable `shadow_enabled` on first frame, call deferred re-enable
  - New `_enable_glow_shadow_next_frame(glow)` coroutine helper
  - New `_patch_wall_occluders()` runtime TileData patch
  - `_ready()`: call `_patch_wall_occluders()` after fog init

### Known Outstanding
- Wall shadow behaviour with the new 8×8 occluder may feel too subtle.  If the art direction
  wants more directional shadows, increase the polygon size or switch to a thin edge strip
  (e.g. top-edge only) — one-line change in `_patch_wall_occluders()`.
- `seen-but-dim` third FOW state still deferred until semi-transparent fog tile art is available.
- Ghost Trail upgrade behaviour (bioluminescent spores on walked tiles) not yet implemented.

### Active Phase
**Phase 4 — Fog of War (LightMaskLayer) + Ghost Trail**

### Next Session Should
- Test the lighting fixes in-game and tune occluder size / shadow energy if needed.
- Implement Ghost Trail: leave bioluminescent spore tiles on every cell the crawler walks.
- Add the `seen-but-dim` FOW state once semi-transparent fog art is available.

---

## Session — 2026-04-01

### What We Did

Completely replaced the dynamic lighting system.  The previous design (PointLight2D +
CanvasModulate + TileMapLayer square fog erase) was producing a hard-edged rectangular
cutout around the crawler rather than smooth radial falloff.  Root cause: the two
sub-systems (fog tile erase in Chebyshev square, and PointLight2D radial gradient)
were fighting each other and could never produce a smooth result.

**New approach — DarknessOverlay Sprite2D:**

A large `Sprite2D` is created at runtime in `explore_mode.gd` and attached as a child
of the crawler, so it follows the player automatically.  Its texture is a
`GradientTexture2D` built entirely in code:

- Radial fill, 512×512, scaled ×8 (= 4096 px = 128 tiles per axis)
- Transparent centre (0–~4 tiles from crawler)
- Smooth transition to fully opaque black (~4–13 tiles)
- Fully opaque black beyond ~13 tiles

The overlay sits at `z_index = 10` (absolute), above the FogLayer (z=6) and all world
tiles, but below the HUD CanvasLayer (layer=99).  Because it is in the world canvas it
also composites over the parallax BackgroundLayer, darkening the background beyond the
light radius.

`FOG_REVEAL_RADIUS` was increased from 3 to 15 so the fog tile boundary (permanent
reveal memory) is always hidden behind the overlay's fully-dark region.  The seen-but-
dark effect — previously deferred — now emerges naturally: revealed-but-distant tiles
render under the dark portion of the gradient, brightening as the crawler approaches.

### Decisions Made

- **PointLight2D retired**: GlowLight and WallLight nodes in Crawler.tscn are zeroed
  (`energy = 0.0`) at runtime.  They are not removed from the scene to avoid modifying
  `.tscn` files (CLAUDE.md rule).
- **CanvasModulate neutralised**: `WorldDarkness.color` set to `Color.WHITE`.  The
  overlay is the sole source of scene darkness.
- **Shadow / occluder code removed**: `_patch_wall_occluders()`, `_enable_glow_shadow_next_frame()`,
  and all related export vars removed from `explore_mode.gd` — they were only needed
  for GlowLight shadow casting.
- **`fog_manager.gd` light_mask line removed**: `_fog_layer.light_mask = 0` was only
  needed to prevent GlowLight illuminating fog tiles; with no active PointLight2D it
  is no longer necessary.

### Files Changed
- `Scenes/World/explore_mode.gd` — full rewrite of lighting section; new `_setup_darkness_overlay()` and `_disable_legacy_lights()`; `FOG_REVEAL_RADIUS` raised to 15; CanvasModulate set to white
- `System/fog_manager.gd` — removed `_fog_layer.light_mask = 0` from `init()`

### Known Outstanding
- Light radius and gradient falloff curve (`0.06` / `0.20` offsets) are first-pass
  values; tune in-engine by adjusting the constants in `_setup_darkness_overlay()`.
- Ghost Trail upgrade behaviour (bioluminescent spore tiles) still not implemented.
- `seen-but-dim` third FOW state no longer needed as a separate art asset — the
  gradient provides it naturally — but the `_seen_cells` dict in fog_manager is
  still tracked for future use (e.g. line-of-sight enemies).

### Active Phase
**Phase 4 — Fog of War + Ghost Trail**

### Next Session Should
- Test in-game and tune the gradient offsets / scale for best feel.
- Implement Ghost Trail: leave bioluminescent spore tiles on every cell the crawler walks.

---
