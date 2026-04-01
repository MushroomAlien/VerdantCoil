## explore_mode.gd
extends Node2D

const GridUtil    := preload("res://System/grid.gd")
const FogManager  := preload("res://System/fog_manager.gd")

# Tiles revealed in each cardinal direction from the crawler each turn.
# Must exceed the DarknessOverlay's fully-dark radius (~13 tiles at default scale)
# so the fog tile boundary is always hidden behind the overlay's black edge.
const FOG_REVEAL_RADIUS := 15

const CRAWLER_SCENE: PackedScene = preload("res://Scenes/Actors/Crawler.tscn")
@export var base_layer: TileMapLayer
@export var walls_layer: TileMapLayer
@export var hazard_layer: TileMapLayer
@export var marker_layer: TileMapLayer
@export var fog_layer: TileMapLayer  # Phase 4: fog-of-war overlay; managed by FogManager

var _fog_manager: RefCounted  # FogManager instance; created in _ready() after map load

@onready var world_darkness: CanvasModulate = $WorldDarkness
@onready var coil_map: TileMap = $CoilMap

func _ready() -> void:
	# DarknessOverlay handles all scene darkening; CanvasModulate must be neutral
	# so it doesn't double-darken the world.
	world_darkness.color = Color.WHITE

	# TileSet on the TileMap (typical setup)
	var ts: TileSet = coil_map.tile_set
	if ts == null:
		print("Preflight: CoilMap has NO TileSet assigned.")
		return

	# Print identifying info
	print("Preflight: CoilMap TileSet =", ts)
	print("Preflight: CoilMap TileSet resource_path =", ts.resource_path)

	# Also confirm the Walls layer exists by name (debug sanity check)
	var walls_layer_debug := coil_map.get_node_or_null("Walls")
	print("Preflight: Walls layer node =", walls_layer_debug)


	# ...existing TileSet prints...

	# Check if LightMaskLayer exists as a node
	var light_mask_layer := $CoilMap.get_node_or_null("LightMaskLayer")
	print("Preflight: LightMaskLayer node =", light_mask_layer)

	# Check whether anything is toggling it (visibility can be a clue)
	if light_mask_layer != null:
		# Many node types have 'visible' or 'visible' equivalents; we just print what we can safely.
		if light_mask_layer.has_method("is_visible"):
			print("Preflight: LightMaskLayer visible =", light_mask_layer.is_visible())
		else:
			print("Preflight: LightMaskLayer has no is_visible() method (that can be normal).")

	# 1) If Builder handed us a coil via the Autoload, rebuild the map now.
	#    Use consume_pending_coil() so we TAKE the snapshot and CLEAR it in the session.
	if has_node("/root/CoilSession"):
		var cs: Node = get_node("/root/CoilSession")
		var data: Dictionary = {}

		# Preferred: explicit API that deep-dupes and clears the stored snapshot
		if cs.has_method("consume_pending_coil"):
			var v: Variant = cs.call("consume_pending_coil")
			if typeof(v) == TYPE_DICTIONARY:
				data = v as Dictionary
		else:
			# Fallback for older builds: read the raw property once, then clear it.
			var raw_v: Variant = cs.get("pending_coil")
			if typeof(raw_v) == TYPE_DICTIONARY:
				data = (raw_v as Dictionary).duplicate(true)  # defensive copy
				cs.set("pending_coil", {})                    # clear to avoid leaks
		if not data.is_empty():
			_load_from_coil(data)  # fills base/walls/hazard/marker

	# --- NEW: initialise global systems for this run ---
	if has_node("/root/UpgradeState"):
		var us: Node = get_node("/root/UpgradeState")
		if us.has_method("load_active_loadout"):
			us.call("load_active_loadout")

	if has_node("/root/HealthSystem"):
		var hs: Node = get_node("/root/HealthSystem")
		if hs.has_method("reset"):
			hs.call("reset", 3)  # Track-1 baseline: 3 HP

	# Phase 4: stamp fog over the coil footprint before the crawler appears.
	# Fog covers only base_layer cells so the parallax background shows through
	# beyond the map edges.  The parallax is atmosphere, not playable space.
	_fog_manager = FogManager.new()
	_fog_manager.init(fog_layer, base_layer)

	# 2) Spawn the crawler at the Spawn marker (or fallback)
	var crawler: Area2D = CRAWLER_SCENE.instantiate()
	crawler.base_layer   = base_layer
	crawler.wall_layer   = walls_layer
	crawler.hazard_layer = hazard_layer
	crawler.marker_layer = marker_layer

	var spawn_tile: Vector2i = get_spawn_position()
	crawler.position = GridUtil.to_world(spawn_tile)  # your util converts map→world
	add_child(crawler)

	# Disable the legacy PointLight2D nodes that shipped in Crawler.tscn.
	# The DarknessOverlay below replaces them entirely.
	_disable_legacy_lights(crawler)

	# Add a large radial darkness overlay as a child of the crawler.
	# It follows the crawler automatically and creates smooth circular light falloff.
	_setup_darkness_overlay(crawler)

	# Phase 4: connect fog reveal to crawler movement, then reveal the spawn tile immediately
	# so the player can see where they start.
	crawler.tile_changed.connect(func(tile: Vector2i) -> void:
		_fog_manager.reveal_around(tile, FOG_REVEAL_RADIUS)
	)
	_fog_manager.reveal_around(spawn_tile, FOG_REVEAL_RADIUS)

	var row_path: String = "HUD/SafeArea/BottomCenter/UpgradeRow"
	var row: Node = get_node_or_null(row_path)
	if row != null and row.has_method("set_controller"):
		var controller: Node = crawler.get_node_or_null("UpgradeController")
		row.call("set_controller", controller)

	# --- NEW: mirror global UpgradeState into the Crawler's UpgradeController once ---
	_apply_upgrade_state_to_crawler(crawler)

# Tells the crawler's UpgradeController which upgrades are SLOTTED for this run.
# All upgrades start INACTIVE — the player activates them mid-run by pressing 1/2/3.
# This deliberately does NOT toggle anything ON; it only sets the equipped set.
func _apply_upgrade_state_to_crawler(crawler: Area2D) -> void:
	if crawler == null:
		return

	var uc: Node = crawler.get_node_or_null("UpgradeController")
	if uc == null:
		return

	# Read the equipped set from UpgradeState (populated from ProfileManager).
	var h_equipped: bool = false
	var a_equipped: bool = false
	var g_equipped: bool = false

	if has_node("/root/UpgradeState"):
		var us: Node = get_node("/root/UpgradeState")
		if us.has_method("is_equipped"):
			h_equipped = bool(us.call("is_equipped", "HARDENED_SKIN"))
			a_equipped = bool(us.call("is_equipped", "ACID_SAC"))
			g_equipped = bool(us.call("is_equipped", "GHOST_TRAIL"))

	# Push the equipped set to the controller so it knows which keys are live.
	if uc.has_method("set_equipped"):
		uc.call("set_equipped", uc.Upgrade.HARDENED_SKIN, h_equipped)
		uc.call("set_equipped", uc.Upgrade.ACID_SAC,      a_equipped)
		uc.call("set_equipped", uc.Upgrade.GHOST_TRAIL,   g_equipped)

	print("UpgradeState → Crawler equipped (H:", h_equipped, ", A:", a_equipped, ", G:", g_equipped, ")")


## Zero out legacy PointLight2D nodes that live in Crawler.tscn.
## They are superseded by DarknessOverlay and must not interfere.
func _disable_legacy_lights(crawler: Area2D) -> void:
	var glow: PointLight2D = crawler.get_node_or_null("GlowLight")
	if glow != null:
		glow.energy = 0.0

	var wall: PointLight2D = crawler.get_node_or_null("WallLight")
	if wall != null:
		wall.energy = 0.0


## Creates a large Sprite2D carrying a radial gradient texture and attaches it
## to the crawler as a child.  It follows the crawler automatically.
##
## The texture is transparent at the centre (bright around the crawler) and
## fades to fully opaque black at the edges (darkness beyond the light radius).
## z_as_relative = false places the overlay at an absolute z of 10, above the
## FogLayer (z=6) and all world tiles, but below the HUD CanvasLayer (layer=99).
func _setup_darkness_overlay(crawler: Area2D) -> void:
	# Build the radial gradient: transparent core → opaque black edges.
	# Offsets are fractions of the texture radius (0 = centre, 1 = edge).
	# With scale=8 on a 512×512 texture the radius is 256*8 = 2048 world px = 64 tiles.
	#   offset 0.00 → 0 tiles   (fully transparent, bright core)
	#   offset 0.06 → ~3.8 tiles (still fully transparent)
	#   offset 0.20 → ~12.8 tiles (fully opaque, transition complete)
	#   offset 1.00 → 64 tiles  (fully opaque, padded to cover entire screen)
	var gradient := Gradient.new()
	# Default Gradient has two points: black at 0 and white at 1.
	# Reuse them rather than removing and re-adding.
	gradient.set_color(0, Color(0.0, 0.0, 0.0, 0.0))   # transparent centre
	gradient.set_offset(0, 0.0)
	gradient.set_color(1, Color(0.0, 0.0, 0.0, 1.0))   # opaque black edge
	gradient.set_offset(1, 1.0)
	gradient.add_point(0.06, Color(0.0, 0.0, 0.0, 0.0)) # hold transparent to ~4 tiles
	gradient.add_point(0.20, Color(0.0, 0.0, 0.0, 1.0)) # fully dark by ~13 tiles

	var tex := GradientTexture2D.new()
	tex.gradient  = gradient
	tex.fill      = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)   # centre of texture
	tex.fill_to   = Vector2(1.0, 0.5)   # right edge (sets the radius)
	tex.width     = 512
	tex.height    = 512

	var overlay := Sprite2D.new()
	overlay.texture        = tex
	overlay.z_as_relative  = false   # absolute z-index, not relative to crawler parent
	overlay.z_index        = 10      # above FogLayer (z=6) and world tiles; below HUD CanvasLayer
	overlay.scale          = Vector2(8.0, 8.0) # 512*8=4096 px per axis = 128 tiles radius

	# Add to crawler so it moves with it automatically.
	crawler.add_child(overlay)


## Returns the tile coordinates of the spawn tile marked with `is_spawn = true` in the Marker layer.
## Falls back to (12, 23) with a warning if none is found.
func get_spawn_position() -> Vector2i:
	if marker_layer == null:
		push_error("Marker layer not assigned")
		return Vector2i(12, 23)

	var spawn_cells: Array[Vector2i] = marker_layer.get_used_cells()
	for coords in spawn_cells:
		var td: TileData = marker_layer.get_cell_tile_data(coords)
		if td == null:
			continue
		var is_spawn := td.get_custom_data("is_spawn") as bool
		if is_spawn:
			return coords
	push_error("❌ No spawn tile found in Markers layer! Using fallback.")
	return Vector2i(12, 23)

# Load a full coil Dictionary into the four TileMapLayers.
func _load_from_coil(data: Dictionary) -> void:
	# Clear first so we don't mix scenes.
	if base_layer: base_layer.clear()
	if walls_layer: walls_layer.clear()
	if hazard_layer: hazard_layer.clear()
	if marker_layer: marker_layer.clear()

	# Pull "layers" safely from Variant
	var layers_v: Variant = data.get("layers", {})
	if typeof(layers_v) != TYPE_DICTIONARY:
		return

	var layers: Dictionary = layers_v as Dictionary
	_rebuild_layer_from_json(layers.get("base", []),   base_layer)
	_rebuild_layer_from_json(layers.get("walls", []),  walls_layer)
	_rebuild_layer_from_json(layers.get("hazard", []), hazard_layer)
	_rebuild_layer_from_json(layers.get("marker", []), marker_layer)

	print("ExploreMode: loaded coil from CoilSession (layers applied).")

## Rebuild one TileMapLayer from JSON array entries:
## [{x,y,source_id,atlas_x,atlas_y}, ...]
func _rebuild_layer_from_json(arr_v: Variant, layer: TileMapLayer) -> void:
	if layer == null:
		return
	if typeof(arr_v) != TYPE_ARRAY:
		return
	var arr: Array = arr_v
	for cell_v in arr:
		if typeof(cell_v) != TYPE_DICTIONARY:
			continue
		var cell: Dictionary = cell_v as Dictionary
		if not (cell.has("x") and cell.has("y") and cell.has("source_id")):
			continue
		var coords: Vector2i = Vector2i(int(cell["x"]), int(cell["y"]))
		var sid: int = int(cell["source_id"])
		var ac: Vector2i = Vector2i.ZERO
		if cell.has("atlas_x") and cell.has("atlas_y"):
			ac = Vector2i(int(cell["atlas_x"]), int(cell["atlas_y"]))
		layer.set_cell(coords, sid, ac)


## end explore_mode.gd
