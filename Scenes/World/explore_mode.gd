## explore_mode.gd
extends Node2D

const GridUtil := preload("res://System/grid.gd")

const CRAWLER_SCENE: PackedScene = preload("res://Scenes/Actors/Crawler.tscn")
@export var base_layer: TileMapLayer
@export var walls_layer: TileMapLayer
@export var hazard_layer: TileMapLayer
@export var marker_layer: TileMapLayer

# --- Lighting baseline (Step 1) ---
# This is your single "ambient darkness" tuning value.
# Lighter = less dark. Darker = more dark.
#@export var ambient_darkness: Color = Color(0.1, 0.1, 0.2, 1.0)

@onready var world_darkness: CanvasModulate = $WorldDarkness
@onready var coil_map: TileMap = $CoilMap
# --- Step 4: Readability tuning (Phase 1) ---
@export var ambient_darkness: Color = Color(0.08, 0.08, 0.12, 1.0)

# World (shadowed) light: affects mask 1
@export var glow_world_energy: float = 1.0
@export var glow_world_texture_scale: float = 8.0
@export var glow_world_colour: Color = Color(1.0, 0.9, 0.85, 1.0) # warm

# Wall reveal (unshadowed) light: affects mask 2
@export var wall_light_energy: float = 1.0
@export var wall_light_texture_scale: float = 3.5
@export var wall_light_colour: Color = Color(1.0, 0.95, 0.90, 1.0) # near-neutral

#@onready var world_darkness: CanvasModulate = $WorldDarkness

func _ready() -> void:
	# --- Step 1: Apply global darkness baseline to the world canvas ---
	# This will dim CoilMap + crawler sprite, but NOT HUD (CanvasLayer),
	# and NOT the ParallaxBackground because we moved it under BackgroundLayer (CanvasLayer).
	world_darkness.color = ambient_darkness

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

	# --- NEW: initialize global systems for this run ---
	if has_node("/root/UpgradeState"):
		var us: Node = get_node("/root/UpgradeState")
		if us.has_method("load_active_loadout"):
			us.call("load_active_loadout")

	if has_node("/root/HealthSystem"):
		var hs: Node = get_node("/root/HealthSystem")
		if hs.has_method("reset"):
			hs.call("reset", 3)  # Track-1 baseline: 3 HP

	# 2) Spawn the crawler at the Spawn marker (or fallback)
	var crawler: Area2D = CRAWLER_SCENE.instantiate()
	crawler.base_layer   = base_layer
	crawler.wall_layer   = walls_layer
	crawler.hazard_layer = hazard_layer
	crawler.marker_layer = marker_layer

	var spawn_tile: Vector2i = get_spawn_position()
	crawler.position = GridUtil.to_world(spawn_tile)  # your util converts map→world
	add_child(crawler)
	_apply_crawler_lights(crawler)

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

# Configures crawler lights for Phase 1 readability.
# Requires in Crawler.tscn:
# - GlowLight (PointLight2D): shadowed world light, mask 1
# - WallLight (PointLight2D): unshadowed wall reveal, mask 2
func _apply_crawler_lights(crawler: Area2D) -> void:
	if crawler == null:
		return

	var glow: PointLight2D = crawler.get_node_or_null("GlowLight")
	if glow != null:
		glow.energy = glow_world_energy
		glow.texture_scale = glow_world_texture_scale
		glow.color = glow_world_colour
		# Safety: ensure it only affects world mask 1
		#glow.item_cull_mask = 1

	var wall: PointLight2D = crawler.get_node_or_null("WallLight")
	if wall != null:
		wall.energy = wall_light_energy
		wall.texture_scale = wall_light_texture_scale
		wall.color = wall_light_colour
		# Safety: walls only (mask 2)
		#wall.item_cull_mask = 2
		# Ensure wall reveal doesn't cast shadows
		#wall.shadow_enabled = false

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
