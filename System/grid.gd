## grid.gd
# Centralized grid positioning utilities for Verdant Coil
# Handles consistent conversion between grid coordinates (Vector2i) and world positions (Vector2)
# Use this for all crawler, hazard, tile, and object placement logic across the project

extends Node

## TILE_SIZE: Defines the size of each grid cell in pixels.
## Changing this updates all snapping and positioning globally.
const TILE_SIZE: int = 32

## Converts a tile coordinate (Vector2i) to a world-space position (Vector2).
## By default, this returns the *center* of the tile.
## If `align_to_center = false`, it returns the *top-left corner* of the tile.
static func to_world(tile_coords: Vector2i, align_to_center := true) -> Vector2:
	# Convert to float Vector2 first to allow addition with subpixel offset
	var pos := Vector2(tile_coords) * TILE_SIZE
	if align_to_center:
		pos += Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)
	return pos

## Converts a world-space position (Vector2) to the corresponding tile coordinate (Vector2i).
## Assumes tiles are centered when snapped (default project convention).
static func to_tile_coords(world_pos: Vector2) -> Vector2i:
	var offset := Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)  # Correct for center alignment
	return ((world_pos - offset) / TILE_SIZE).floor()

## Snaps any world-space position to the nearest grid tile, returning a world-space Vector2.
## This is useful for ensuring alignment even from rough input or procedural placement.
## Use `align_to_center = false` if placing art that expects top-left anchoring (e.g. tiles).
static func snap_position(world_pos: Vector2, align_to_center := true) -> Vector2:
	var tile_coords := to_tile_coords(world_pos)
	return to_world(tile_coords, align_to_center)
