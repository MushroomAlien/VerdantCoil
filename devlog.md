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
