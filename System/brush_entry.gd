## brush_entry.gd
# One "brush" definition the Builder can paint with.

extends Resource
class_name BrushEntry

# Human-readable name shown in status messages
@export var display_name: String = ""

# Which legality rule profile to apply when placing this brush.
# Keep these strings exactly as written to match the painter.
@export_enum("BASE", "WALL", "POOL", "MARKER", "ERASER")
var rule_profile: String = "BASE"

# Which TileMap layer this brush paints to. (ERASER ignores this.)
@export_range(0, 7, 1)
var target_layer: int = 0

# TileSet placement info (ERASER ignores these).
@export var source_id: int = -1
@export var atlas_coords: Vector2i = Vector2i.ZERO

# Optional: only used by POOL brushes so we can keep acid vs sticky separate.
# Example: "acid" or "sticky".
@export var hazard_kind: String = ""

# Optional icon for your UI buttons (not required by the painter).
@export var icon: Texture2D

## end brush_entry.gd
