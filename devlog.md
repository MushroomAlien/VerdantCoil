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
