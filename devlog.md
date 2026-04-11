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

## Session 7 — 2026-04-03

### What We Did

**Phase 4 completion (most of it): Lighting Rebuild + Ghost Trail implementation.**

The DarknessOverlay Sprite2D approach (previous session) could not support multiple independent
light emitters, so the entire lighting system was rebuilt from the correct primitives.

**Stage 1 — DarknessOverlay demolished:**
- Removed `_setup_darkness_overlay()`, `_disable_legacy_lights()`, and all references from
  `explore_mode.gd`.
- Removed the GlowLight/WallLight disable calls — those nodes are back to their authored
  energy values in `Crawler.tscn`.
- `world_darkness.color` changed from `Color.WHITE` back to `Color(0.08, 0.06, 0.05, 1.0)`.
- `FOG_REVEAL_RADIUS` wound down from 15 → 3 (matching GlowLight visual range).

**Stage 2 — Shadow startup flash fixed:**
- New `_enable_glow_shadow_next_frame(light)` coroutine in `explore_mode.gd`.
  Sets `shadow_enabled = false` for one frame then restores it, so Godot rasterises the
  initial shadow buffer from a lit baseline instead of a cold/black one.

**FogManager retired:**
- Opaque fog tiles cannot be made transparent to PointLight2D (light composites additive,
  cannot punch through opaque pixels). Square reveal boundary was visible at radius 4.
  Decision: retire FogManager entirely; CanvasModulate + GlowLight is the sole darkness source.
- `System/fog_manager.gd` reduced to a stub comment.
- FogLayer node deleted from ExploreMode scene tree (editor, not in code).

**Stage 3 — LightRegistry autoload:**
- New `System/autoload/light_registry.gd` — tracks all active light sources (world position,
  energy) by integer ID. API: `register_light`, `update_light`, `deregister_light`, `clear`,
  `get_all_lights`. Registered in project.godot autoloads.
- Crawler's GlowLight registered on spawn; registry entry updated every `tile_changed`.

**Stage 4 — Ghost Trail:**
- New `System/ghost_trail_manager.gd` — RefCounted. `place_spore(tile)` paints a spore tile
  onto GhostTrailLayer and spawns a dim `PointLight2D` (GLOW_TEXTURE, energy=0.7, scale=1.5)
  at the tile's world position. `reset()` clears all tiles and queue_frees all lights.
- `explore_mode.gd` wires it up: GhostTrailManager initialised on run start, `tile_changed`
  lambda checks `has_upgrade(GHOST_TRAIL)` and calls `place_spore(_crawler_previous_tile)`.
- Ghost Trail unlock unblocked in `heartroot.gd` (removed `"locked": true` flag).
- `upgrade_row.gd` Ghost Trail icon updated to use `_set_icon_state` (was hard-coded to locked).
- `upgrade_state.gd` Ghost Trail equipped flag unblocked.
- `crawler.gd` Ghost Trail toggle guard removed from `_request_toggle()`.

**project.godot fixes:**
- `window/stretch/mode` changed from `"viewport"` to `"canvas_items"` — viewport mode was
  causing PointLight2D world positions to not align with display coordinates.
- `window_width_override=1024` and `window_height_override=576` added.
- `limits/opengl/max_renderable_lights=2` line removed — this hidden setting was capping the
  entire scene to 2 simultaneous PointLight2D nodes, causing spore lights to drop out.

**Camera limits fix:**
- `_apply_camera_limits(crawler)` call was misplaced inside the coil-loading block (where
  `crawler` doesn't exist). Removed the misplaced call; the correct call after
  `add_child(crawler)` was already present and now correctly applies.

### Files Changed
- `Scenes/World/explore_mode.gd` — complete rewrite of lighting/fog section
- `System/fog_manager.gd` — retired to stub
- `System/autoload/light_registry.gd` — new file
- `System/ghost_trail_manager.gd` — new file
- `Scenes/Heartroot/heartroot.gd` — Ghost Trail unlock
- `Scenes/UI/upgrade_row.gd` — Ghost Trail icon state
- `System/autoload/upgrade_state.gd` — Ghost Trail equipped flag
- `Scenes/Actors/crawler.gd` — Ghost Trail toggle guard removed
- `project.godot` — stretch mode, window overrides, max_renderable_lights removed

### Known Outstanding
- **Ghost Trail spore lights drop out after ~20 steps.** Root cause unconfirmed.
  `max_renderable_lights` cap was the leading suspect and was removed, but dropout persists.
  Next session must add a `print()` counter in `place_spore()` to confirm how many
  PointLight2D nodes are actually being created vs how many render.
- Spore light values (energy=0.7, texture_scale=1.5) are diagnostic-level overbright;
  tune down once the dropout bug is fixed.
- Win condition with Ghost Trail active not yet verified.

### Active Phase
**Phase 4 — Fog of War + Ghost Trail**

### Next Session Should
1. Add a print counter to `GhostTrailManager.place_spore()` to count created lights vs
   visible ones. Determine whether nodes are being created but not rendering, or not
   created at all.
2. Check whether `GhostTrailManager.init()` is being called more than once per run
   (init calls `reset()` which queue_frees all existing lights — a double-init would
   explain periodic dropout).
3. Fix the dropout, then tune spore light energy/scale for production values.

---

## Session 11 — 2026-04-03

### What We Did

**Ghost Trail redesign — consumable spore action.**

Ghost Trail was changed from a passive toggle (trails every step, automatic) to a
deliberate single-use action. Pressing key 3 now places one spore on the tile the
crawler currently occupies, costs one turn, and can be used unlimited times. When more
than MAX_SPORES (5) lights are active, the oldest light is disabled on each new placement
so exactly 5 spores glow at any time. The tile sprite remains on all placed spores; only
the PointLight2D emission is capped.

**System/ghost_trail_manager.gd:**
- Removed `MAX_ACTIVE_SPORE_LIGHTS` (nearest-N cull — no longer needed).
- Removed charge system (`STARTING_CHARGES`, `_charges`, `get_charges()`) — placement
  is always allowed; no hard per-run limit.
- Added `MAX_SPORES = 5` — controls the rolling glow window.
- Rolling cull: when `_spore_lights.size() > MAX_SPORES`, disables the element at
  index `size - 1 - MAX_SPORES` so the correct oldest light darkens on every placement
  (not always index 0, which was a bug fixed mid-session).
- `place_spore()` now prints `[SPORE] placed at tile total_spores=N`.

**Scenes/World/explore_mode.gd:**
- Removed Ghost Trail block from `tile_changed` lambda (spores no longer placed on movement).
- Assigned `crawler._explore_mode = self` after spawning so the crawler can call back.
- Added `try_place_spore(tile)` method — delegates to GhostTrailManager, safe to call
  if manager is uninitialised.

**Scenes/Actors/crawler.gd:**
- Added `var _explore_mode: Node = null` (assigned by ExploreMode after spawn).
- In `_apply_pending_toggle()`, added a Ghost Trail special case before the generic
  toggle path: checks equipped, calls `_explore_mode.try_place_spore(current_tile)`,
  consumes one turn. HARDENED_SKIN and ACID_SAC paths unchanged.

**System/upgrade_controller.gd:**
- Removed `var _ghost_trail: bool = false` (no active boolean; GT is an action).
- `has_upgrade(GHOST_TRAIL)` now returns `false` explicitly.
- Removed GHOST_TRAIL case from `toggle_upgrade()` (dead code).

**Also in this session (Session 10):**
Camera tracking was fixed — `_apply_camera_limits()` now only applies limits on axes
where the map exceeds the viewport size; smaller maps leave the defaults so the camera
follows the crawler freely. Debugging principle added to CLAUDE.md.

### Files Changed
- `System/ghost_trail_manager.gd`
- `Scenes/World/explore_mode.gd`
- `Scenes/Actors/crawler.gd`
- `System/upgrade_controller.gd`
- `CLAUDE.md` (session 10 — debug principle)

### Known Outstanding
- Spore light energy (0.7) and texture_scale (1.5) are diagnostic-overbright; tune for production.
- No HUD counter for active spores — deferred.
- No charge replenishment or shop integration — deferred.

### Active Phase
**Phase 4 — Fog of War + Ghost Trail**

### Next Session Should
- Tune spore light energy/scale to production values.
- Consider whether Ghost Trail is now feature-complete for Phase 4, or if any further
  behaviour (e.g. spore interaction with future enemies) is needed before closing the phase.
- Begin Phase 5 planning: Guard Nodule (static cyclic enemy).

---

## Session 10 — 2026-04-03

### What We Did

Fixed camera not tracking the crawler in ExploreMode.

**Root cause:** `_apply_camera_limits()` set Camera2D limits based on the map's pixel
extent unconditionally. Godot 4 Camera2D limits constrain the valid range for the camera
centre to `[limit_left + vp_w/2, limit_right - vp_w/2]`. For any map smaller than or
equal to the viewport (all current coils fit within 1024×576), this range collapses to
min > max — the camera locks at an indeterminate position and stops following the crawler.

The test coil was 384×384 px (12×12 tiles). With `limit_right = 384` and viewport width
1024, the x constraint `[512, −128]` is invalid and the camera locked near the map's
right edge, explaining the map appearing in the upper-right portion of the screen across
all previous sessions.

**Fix (`Scenes/World/explore_mode.gd`):**
`_apply_camera_limits()` now reads the viewport size via `get_viewport_rect().size`.
Limits are only applied on an axis if the map pixel size **exceeds** the viewport size
on that axis. For smaller maps both axes are skipped, leaving Camera2D at its defaults
(±10,000,000) so the camera follows the crawler freely and void is visible at the edges.

Diagnostic prints added:
- `[CAMERA] map=WxH  viewport=WxH` on every call
- `[CAMERA] x/y limits applied — left= right=` when limits are set
- `[CAMERA] x/y limits skipped (map narrower/shorter than viewport)` when not

Debug output confirmed: `map=384x384px  viewport=1024x576px` → both axes skipped →
camera tracks crawler. Player completed a full coil run and won cleanly.

**Also:** Added debugging principle to `CLAUDE.md` — add `print()` statements liberally
during diagnosis and read output via `get_debug_output` rather than relying on screenshots.

### Files Changed
- `Scenes/World/explore_mode.gd` — `_apply_camera_limits()` conditional limit logic + prints
- `CLAUDE.md` — debugging principle added to MCP section

### Known Outstanding
- Diagnostic `[CAMERA]` prints can be removed once camera behaviour is confirmed stable
  across multiple coil sizes (including future 32×18 default coils).
- All previous sessions' screenshots showed the broken camera — worth re-testing with
  a larger coil once 32×18 default coils exist, to verify the x/y limit logic triggers
  correctly when the map does exceed the viewport.
- Pre-existing UI anchor warning in debug output — unrelated.

### Active Phase
**Phase 4 — Fog of War + Ghost Trail**

### Next Session Should
- Test with a coil larger than 1024×576 to confirm limits apply correctly for big maps.
- Tune spore light energy/texture_scale from diagnostic values (0.7/1.5) to production.
- Decide on rolling-window vs distance-based cull for Ghost Trail lights.
- Verify Ghost Trail win condition end-to-end (this session showed a win with GT active
  and no errors, so this may already be confirmed).

---

## Session 9 — 2026-04-03

### What We Did

Fixed Ghost Trail spore lights dropping out after ~15–16 steps.

**Root cause confirmed (Stage 1):**
Diagnostic prints from Session 8 showed the count climbing past 16 with all nodes
`is_inside_tree()=true` and correct world positions. This confirmed Godot 4 Forward+'s
per-canvas-item PointLight2D limit (~16 lights per draw call). There is no project.godot
setting to raise this limit for 2D canvas items — it is hardcoded in the GLSL shader.

**Fix — Nearest-N light cull (`System/ghost_trail_manager.gd`):**
Added `MAX_ACTIVE_SPORE_LIGHTS = 12` constant. After each `place_spore()` call, the
entire `_spore_lights` array is iterated and `enabled` is set to `false` for all lights
outside the most recent 12. Tile paint still happens for every step, so the spore sprite
is always visible; only the light emission is capped. Older lights go dark predictably
as the player walks rather than silently failing past an invisible threshold.

**Spore position fix (`System/ghost_trail_manager.gd`):**
Replaced `_layer.to_global(_layer.map_to_local(tile))` with `GridUtil.to_world(tile)`.
`map_to_local()` returns the tile's top-left corner; `GridUtil.to_world()` returns the
tile centre, matching the crawler's own positioning convention.
Added `const GridUtil := preload("res://System/grid.gd")` to the consts block.

**LightRegistry cleanup (`Scenes/World/explore_mode.gd`):**
Added `LightRegistry.clear()` immediately before `GhostTrailManager.new()` in `_ready()`.
Prevents stale registry entries accumulating if the run is restarted.

**Diagnostic print removed** from `place_spore()`.

### Observed Behaviour After Fix
- Spore lights no longer drop out silently at step ~16.
- The 12 most recent tiles glow; older tiles show spore sprite only (no halo).
- The lit window rolls forward with the player continuously across 70+ steps with no errors.

### Files Changed
- `System/ghost_trail_manager.gd` — `GridUtil` const, `MAX_ACTIVE_SPORE_LIGHTS` const,
  nearest-N cull loop, `GridUtil.to_world()` position fix, diagnostic print removed
- `Scenes/World/explore_mode.gd` — `LightRegistry.clear()` before run init

### Known Outstanding
- The "rolling window" of 12 lit tiles is functional but may not be the ideal design.
  An alternative (keep all spores lit, rotate out the dimmest/farthest) can be explored
  once the art pass makes the spore energy/scale production-ready.
- Spore light values (energy=0.7, texture_scale=1.5) remain at diagnostic-overbright levels.
  Tune down once the light design is settled.
- Pre-existing UI anchor warning in debug output — unrelated to this work.

### Active Phase
**Phase 4 — Fog of War + Ghost Trail**

### Next Session Should
- Tune spore light energy and texture_scale to production values.
- Decide whether the rolling-window cull is the final design or whether a distance-based
  cull (disable farthest light instead of oldest) would feel better to play.
- Verify Ghost Trail + win condition works end-to-end (complete a coil with GT active).

---

## Session 8 — 2026-04-03

### What We Did

Diagnostic session only. Added a `print()` counter inside `GhostTrailManager.place_spore()`
that logs the current spore count, tile, `is_inside_tree()`, and `global_position` every
time a spore light is spawned.  No fix applied yet — diagnosis first.

### Leading Hypothesis — Per-canvas-item PointLight2D limit

Root cause is likely Godot 4's 2D canvas shader compile-time limit on how many
`PointLight2D` nodes can illuminate a single canvas item per draw call.

In Forward+, this limit is believed to be **16 lights per canvas item**.  With 1 GlowLight
on the crawler plus spore lights accumulating as the player walks, the budget fills at
roughly step 15 (1 + 15 = 16).  Any new `PointLight2D` past that point is successfully
created and added to the scene tree (`is_inside_tree()` = true), but it silently fails to
illuminate floor tiles because the per-item light budget is exhausted.

This explains:
- Why removing `max_renderable_lights = 2` (a global cap) improved the scene but did not
  fix the dropout — the per-canvas-item limit is a separate shader-level constraint.
- Why existing lights do not disappear — old lights remain; it's only *new* ones that have
  no effect.
- Why the threshold is ~20 steps (close to 16, with some map-layout variance from tile
  culling radii).

### Files Changed
- `System/ghost_trail_manager.gd` — diagnostic print added to `place_spore()`
  (to be removed once root cause confirmed)

### Known Outstanding
- Diagnostic prints need to be verified by running the game and inspecting the output past
  step 20.  If `place_spore()` is still being called (count climbs past 15) but no new
  halos appear, the per-item limit hypothesis is confirmed.
- If `place_spore()` stops being called, the bug is upstream — probably in the
  `tile_changed` lambda in `explore_mode.gd`.
- Fix not yet applied.

### Active Phase
**Phase 4 — Fog of War + Ghost Trail**

### Next Session Should
1. Run the game, activate Ghost Trail, walk 25+ steps, copy the debug output.
2. Check the SPORE print lines: does count keep climbing past 16?  Is `in_tree` always true?
3. If confirmed per-item limit: add `rendering/2d/lights/max_renderable_lights` or the
   per-item equivalent to `project.godot`, or redesign to cull distant spore lights
   (only keep the N nearest spores active at any time).
4. Remove diagnostic prints after fix is confirmed.
5. Tune spore light energy/scale from diagnostic values (0.7/1.5) to production values.

---

## Session — 2026-04-11

### What We Did

**Phase 4 polish: darkness tuning + spore light brightness.**

**Issue 1 — GlowLight radius too wide / ambient visibility at range**

Root cause: two compounding problems.
- `GlowLight.texture_scale = 6.0` in `Crawler.tscn` gives a 24-tile illumination radius,
  enough to softly illuminate every tile on current maps from spawn.
- `world_darkness.color = Color(0.08, 0.06, 0.05, 1.0)` in `explore_mode.gd` provides 8%
  ambient brightness so even tiles receiving zero light contribution are faintly visible.

Fix (`Scenes/World/explore_mode.gd`):
- `world_darkness.color` changed to `Color(0, 0, 0, 1.0)` — fully black, zero ambient.
- `glow.texture_scale` overridden to `2.0` at runtime (after reading `glow.energy`).
  128 px × 2.0 = 8-tile radius; well-lit 0–6 tiles, cubic fade 6–8 tiles, fully dark beyond.
  Runtime override used (cannot edit `.tscn` per CLAUDE.md).

**Issue 2 — Spore lights overbright**

Fix (`System/ghost_trail_manager.gd`):
- `light.energy` reduced from `0.7` → `0.4` (modest ~43% reduction).
- `light.texture_scale` reduced from `1.5` → `1.2` (slightly tighter halo).
  Values were flagged as diagnostic-overbright in Sessions 7–11; now at production level.

### Files Changed
- `Scenes/World/explore_mode.gd` — `world_darkness.color` fully black; `glow.texture_scale = 2.0` at runtime
- `System/ghost_trail_manager.gd` — spore light `energy = 0.4`, `texture_scale = 1.2`

### Active Phase
**Phase 4 — Fog of War + Ghost Trail**

### Next Session Should
- Visual QA: play through a coil, confirm darkness feels correct at range and the spore
  glow is visible but not blinding. Adjust `glow.texture_scale` and/or spore values further
  if needed (single-line changes in the two files above).
- If darkness tuning is satisfactory, close Phase 4 and begin Phase 5 planning:
  Guard Nodule (static cyclic enemy).

---

## Session — 2026-04-11 (close)

### What We Did

**Phase 4 closed. Visual QA and final tuning pass.**

User played through the lighting after the earlier darkness/spore fixes and dialled in
final production values. Changes from the tuning pass:

**`Crawler.tscn` (user-edited directly in Godot editor):**
- `GlowLight.energy` raised from `0.8` → `1.2` (brighter immediate surroundings)
- `GlowLight.color` changed to `Color(1, 0.8, 0.667, 1)` (~#ffccaa warm amber)
- `WallLight.energy` reduced from `0.9` → `0.8`

**`Scenes/World/explore_mode.gd`:**
- `glow.texture_scale` runtime override settled at `3.0` (was proposed 2.0; user preferred
  slightly wider reveal — ~12-tile radius, full dark beyond)

**`System/ghost_trail_manager.gd`:**
- Spore light `energy` settled at `0.7`, `texture_scale` at `2.5`
- Spore light `color = Color("#ffccaa")` added — warm peach/amber hue matching GlowLight

**`world_darkness.color = Color(0, 0, 0, 1.0)`** — remains fully black (zero ambient).

### Files Changed
- `Scenes/Actors/crawler.tscn` — GlowLight energy/colour, WallLight energy (user edit)
- `Scenes/World/explore_mode.gd` — `glow.texture_scale = 3.0` runtime override
- `System/ghost_trail_manager.gd` — spore `color`, final `energy`/`texture_scale` values
- `CLAUDE.md` — phase updated to Phase 5

### Active Phase
**Phase 5 — Guard Nodule** ← NEXT

### Next Session Should
- Design Guard Nodule: static enemy on a fixed patrol cycle (e.g. rotates between 2–3
  tiles, damages crawler on contact or adjacency). Determine detection pattern and
  whether it interacts with Ghost Trail spores.
- Read devlog and CLAUDE.md before any code.

---

## Session — 2026-04-11 (Phase 5.1)

### What We Did

**Phase 5 sub-phase split confirmed.** Phase 5 broken into four focused sessions:
- 5.1 Placement + dim light (this session)
- 5.2 3-tile patrol loop
- 5.3 Contact damage + adjacency warning
- 5.4 Builder palette (first-class entry)

**Guard Nodule placement (Phase 5.1).**

User added `is_nodule` boolean custom data layer to `flesh_tile.tres` in the Godot editor
and marked 8 nodule variant tiles (`is_nodule = true`). The coil JSON schema is unchanged —
the flag lives in the tileset, not the JSON.

**`Scenes/Actors/guard_nodule.gd` (new file):**
- Node2D spawned at runtime by `explore_mode._spawn_guard_nodules()`
- White `PointLight2D` (energy 0.4, scale 1.5) for neutral room illumination
- Small additive bloom `Sprite2D` (`BLEND_MODE_ADD`, green `Color(0.2, 0.65, 0.28)`,
  scale 0.5) for coloured self-glow on the emitter without tinting floor tiles
- Registers/deregisters with `LightRegistry` in `_ready()` / `_exit_tree()`
- No movement, no damage — Phase 5.1 scope only

**`Scenes/World/explore_mode.gd`:**
- Added `const GuardNodule` preload
- Added `var _guard_nodules: Array[Node2D]`
- Added `_spawn_guard_nodules()` — scans marker layer for `is_nodule == true` tiles,
  spawns one `GuardNodule` Node2D per match at the tile's world centre
- Call inserted after `LightRegistry.clear()`, before `GhostTrailManager.new()`

**`Scenes/BuilderMode/builder_mode.gd`:**
- Added `_add_nodule_brush()` — injects a Guard Nodule palette button at runtime
  (appends `BrushEntry` to registry, creates `TextureButton` in `PaletteRow`,
  wires into existing `ButtonGroup`)
- Called at end of `_ready()`. Provisional Phase 5.1 workaround — full palette
  integration deferred to Phase 5.4.

**Lighting polish — additive bloom technique (both nodule and spores).**

Root issue: coloured `PointLight2D` multiplies its colour against tile pixel values,
tinting the floor (reads as paint). Fix: separate illumination from emission.

- `PointLight2D` → white `Color(1, 1, 1)` on both nodule and spores — neutral illumination
- Additive `Sprite2D` (`CanvasItemMaterial.BLEND_MODE_ADD`) centred on the emitter —
  coloured self-glow that only brightens the emitter itself

**`System/ghost_trail_manager.gd`:**
- `light.color` changed `Color("#ffccaa")` → `Color(1, 1, 1)` (white PointLight2D)
- Added `_spore_blooms: Array[Sprite2D]` instance variable
- `place_spore()` creates a bloom Sprite2D per spore (amber `Color(0.65, 0.48, 0.25)`,
  scale 0.4), added as `_parent` child alongside the PointLight2D
- `reset()` also queue_frees `_spore_blooms` and clears the array

Observed behaviour: multiple light sources near each other produce additive bloom
overlap (brighter together) — expected behaviour the user liked; no action needed.

### Files Changed
- `Scenes/Actors/guard_nodule.gd` — **new file**
- `Scenes/World/explore_mode.gd` — nodule preload, var, `_spawn_guard_nodules()`, call site
- `Scenes/BuilderMode/builder_mode.gd` — `_add_nodule_brush()`, call at end of `_ready()`
- `System/ghost_trail_manager.gd` — white PointLight2D, `_spore_blooms` tracking, bloom per spore

### Active Phase
**Phase 5 — Guard Nodule (5.1 complete)**

### Next Session Should
- Begin Phase 5.2: 3-tile patrol loop.
- GuardNodule receives patrol waypoints (3 × Vector2i), advances one tile per
  `tile_changed` signal from the crawler.
- Phase 5.2 will also need to: add a `Sprite2D` to `GuardNodule` and erase the marker
  tile from the layer so the nodule can move independently of the tilemap.
- Read devlog and CLAUDE.md before any code.

---
