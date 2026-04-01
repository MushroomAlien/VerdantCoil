## fog_manager.gd
## Manages the fog-of-war tile overlay on the FogLayer TileMapLayer.
##
## Uses lightmask.tres (source 0), tile (0,0) — fully opaque dark — to cover
## unexplored coil cells.  "Visible" means no fog tile at all; the game tiles
## render through unobstructed.  The parallax background outside the coil
## footprint is never fogged.
##
## NOTE: A "seen but dim" third state is deferred until semi-transparent fog
## tile art is available.  For now there are only two states:
##   FOGGED  – TILE_UNSEEN stamped on cell (never revealed)
##   CLEAR   – cell erased from fog layer (revealed; stays clear)
##
## Lifecycle:
##   1. Call init(fog_layer, base_layer) once after coil tiles are loaded.
##      Stamps FOGGED over every base-layer cell.
##   2. Call reveal_around(origin, radius) each turn after the crawler moves,
##      and once immediately at spawn.  Erases fog from the reveal zone.
extends RefCounted

const SOURCE_ID   := 0               # TileSet source index for lightmask.tres
const TILE_UNSEEN := Vector2i(0, 0)  # dark, opaque – unexplored cell

var _fog_layer: TileMapLayer
# Cells erased in the current reveal zone.  Kept so we can restore them when
# the "seen but dim" state is added later.
var _visible_cells: Array[Vector2i]
# Every cell ever revealed; used for future SEEN-state logic.
var _seen_cells: Dictionary          # Vector2i -> bool


## Initialise the manager and stamp fog over every base-layer cell.
## fog_layer  : the FogLayer TileMapLayer node from ExploreMode.
## base_layer : provides the coil footprint (only these cells get fogged).
func init(fog_layer: TileMapLayer, base_layer: TileMapLayer) -> void:
	_fog_layer     = fog_layer
	_visible_cells = []
	_seen_cells    = {}
	_fill_unseen(base_layer)


## Stamp TILE_UNSEEN onto every cell that has a base-floor tile.
## Cells outside the coil footprint are left untouched, so the parallax
## background shows through beyond the map edges.
## Private – called automatically by init().
func _fill_unseen(base_layer: TileMapLayer) -> void:
	if _fog_layer == null:
		push_error("FogManager._fill_unseen: fog_layer is null")
		return
	if base_layer == null:
		push_error("FogManager._fill_unseen: base_layer is null")
		return
	_fog_layer.clear()
	for cell: Vector2i in base_layer.get_used_cells():
		_fog_layer.set_cell(cell, SOURCE_ID, TILE_UNSEEN)


## Reveal tiles within a square (Chebyshev) radius around origin.
## Erases the fog tile from each cell in the zone; previously revealed cells
## stay clear (no dim state until semi-transparent art is available).
## Call once per turn after the crawler moves, and once at spawn.
func reveal_around(origin: Vector2i, radius: int) -> void:
	if _fog_layer == null:
		return

	# Erase fog from every cell in the reveal square.
	# We only erase cells that actually have a fog tile — cells already clear
	# (or outside the coil footprint) are skipped via the source-id check.
	for dx: int in range(-radius, radius + 1):
		for dy: int in range(-radius, radius + 1):
			var cell := origin + Vector2i(dx, dy)
			if _fog_layer.get_cell_source_id(cell) == -1:
				continue  # already clear or outside coil footprint
			_seen_cells[cell] = true
			_visible_cells.append(cell)
			_fog_layer.erase_cell(cell)
