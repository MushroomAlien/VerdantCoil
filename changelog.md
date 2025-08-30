[Unreleased]

Planned

Phase 1.4: Additional tile interactions and polish.

Phase 2.0: Future features (to be scoped).

[1.3.0] - 2025-08-17

Added

Grid-based tilemap implementation.

Multi-layer system (LAYER_BASE, LAYER_WALLS, LAYER_HAZARDS, LAYER_MARKERS).

Metadata-driven movement checks (walkable, digestible).

Hazard handling: acid (damage), sticky (input skip).

Goal marker detection (Heartroot win condition).

Changed

Refactored crawler.gd to use helper functions for safe metadata access (_get_str, _get_int, _get_bool).

Input handling now consumes inputs when slowed by sticky tiles.

Wall traversal logic integrates Acid Sac upgrade properly.

[1.2.0] - 2025-08-05

Added

Upgrade system (UpgradeController).

Upgrades: Hardened Skin, Acid Sac, Ghost Trail.

Upgrade bar UI with toggle buttons for testing.

Signals for upgrade_changed to update UI dynamically.

[1.1.0] - 2025-08-03

Added

Crawler movement on grid with tweened tile-to-tile motion.

Camera follow (Crawler-centered).

Grid snapping logic for consistent starting position.

[1.0.0] - 2025-08-02

Added

Initial project setup.

Base scene tree and folder structure.

Basic Grid utility.
