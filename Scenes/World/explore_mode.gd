## explore_mode.gd
extends Node2D

const GridUtil           := preload("res://System/grid.gd")
const GhostTrailManager  := preload("res://System/ghost_trail_manager.gd")

const CRAWLER_SCENE: PackedScene = preload("res://Scenes/Actors/Crawler.tscn")
@export var base_layer: TileMapLayer
@export var walls_layer: TileMapLayer
@export var hazard_layer: TileMapLayer
@export var marker_layer: TileMapLayer
## Assigned in the Inspector after adding GhostTrailLayer to ExploreMode.tscn.
@export var ghost_trail_layer: TileMapLayer

## LightRegistry ID for the crawler's GlowLight.
## Used to update position each turn and deregister on scene exit.
var _crawler_light_id: int = -1
## Ghost Trail manager; created at run start, reset on run reset.
var _ghost_trail_manager: RefCounted
## The tile the crawler occupied on the previous step.
## Ghost Trail spores are placed here (the tile just walked OFF).
var _crawler_previous_tile: Vector2i

@onready var world_darkness: CanvasModulate = $WorldDarkness
@onready var coil_map: TileMap = $CoilMap

func _ready() -> void:
	# CanvasModulate sets the scene to near-darkness.
	# PointLight2D nodes (GlowLight on the crawler, spore lights from Ghost Trail)
	# punch holes in this darkness — Godot composites them automatically.
	world_darkness.color = Color(0, 0, 0, 1.0)

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

	# 2) Spawn the crawler at the Spawn marker (or fallback)
	var crawler: Area2D = CRAWLER_SCENE.instantiate()
	crawler.base_layer   = base_layer
	crawler.wall_layer   = walls_layer
	crawler.hazard_layer = hazard_layer
	crawler.marker_layer = marker_layer

	var spawn_tile: Vector2i = get_spawn_position()
	crawler.position = GridUtil.to_world(spawn_tile)  # your util converts map→world
	add_child(crawler)
	_apply_camera_limits(crawler)
	## Give the crawler a back-reference so it can call try_place_spore() when
	## the player activates Ghost Trail. Assigned here rather than via export
	## to avoid a scene-file dependency on ExploreMode.
	crawler._explore_mode = self

	## Initialise the Ghost Trail manager with the dedicated TileMapLayer.
	## Source ID 0, atlas (35,9) is the yellow blob placeholder spore tile.
	## ghost_trail_layer is assigned in the Inspector by the user.
	LightRegistry.clear()
	_ghost_trail_manager = GhostTrailManager.new()
	_ghost_trail_manager.init(ghost_trail_layer, self, 0, Vector2i(35, 9))
	_crawler_previous_tile = spawn_tile

	# Godot initialises the PointLight2D shadow depth buffer as fully dark on frame 0,
	# causing a black flash at spawn that corrects itself only as the player moves.
	# Disabling shadow for one frame then re-enabling it lets Godot rasterise the
	# initial shadow map from a lit baseline, so frame 1 onward looks correct.
	var glow: PointLight2D = crawler.get_node_or_null("GlowLight")
	if glow != null:
		_enable_glow_shadow_next_frame(glow)

	## Register the crawler's GlowLight with LightRegistry so future systems
	## (e.g. parasite AI) can query active light positions without scene-tree lookups.
	## glow_energy is captured by the tile_changed closure below.
	var glow_energy: float = 0.8  ## matches GlowLight.energy in Crawler.tscn
	if glow != null:
		glow_energy = glow.energy
		## Override texture_scale at runtime to tighten the light radius.
		## Crawler.tscn bakes texture_scale = 6.0 (24-tile radius, covers full map).
		## 2.0 gives an 8-tile radius — well-lit within ~6 tiles, dark beyond.
		glow.texture_scale = 3.0
	_crawler_light_id = LightRegistry.register_light(crawler.position, glow_energy)

	## Update the crawler's registry entry each time it moves to a new tile.
	## Ghost Trail spores are placed explicitly by the player (key 3), not here.
	crawler.tile_changed.connect(func(tile: Vector2i) -> void:
		LightRegistry.update_light(_crawler_light_id, GridUtil.to_world(tile), glow_energy)
		_crawler_previous_tile = tile
	)

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


## Disables GlowLight shadow for one frame then re-enables it.
## Godot initialises the shadow depth buffer as fully dark on frame 0,
## causing a near-black startup flash. Toggling shadow_enabled off for one
## process_frame lets Godot rasterise from a fully-lit baseline instead.
func _enable_glow_shadow_next_frame(light: PointLight2D) -> void:
	light.shadow_enabled = false
	await get_tree().process_frame
	light.shadow_enabled = true

## Sets the Camera2D limits to the playable map bounds so the camera
## never scrolls beyond the edge of the coil. Only applies a limit on
## a given axis if the map is larger than the viewport on that axis.
## For smaller maps the Camera2D default limits (-10,000,000 / 10,000,000)
## are left in place so the camera follows the crawler freely.
func _apply_camera_limits(crawler: Area2D) -> void:
	var camera: Camera2D = crawler.get_node_or_null("Camera2D")
	if camera == null:
		push_error("_apply_camera_limits: Camera2D not found on crawler")
		return
	## get_used_rect() returns tile coordinates; multiply by TILE_SIZE
	## to get world pixel coordinates for the camera limits.
	var map_rect: Rect2i = base_layer.get_used_rect()
	var ts: int = Grid.TILE_SIZE
	var map_px_w: int = map_rect.size.x * ts
	var map_px_h: int = map_rect.size.y * ts
	var vp_size: Vector2 = get_viewport_rect().size
	print("[CAMERA] map=", map_px_w, "x", map_px_h, "px  viewport=",
		int(vp_size.x), "x", int(vp_size.y), "px")
	## X axis: only lock if the map is wider than the viewport.
	## If narrower, leave defaults so the camera can freely follow the crawler.
	if map_px_w > int(vp_size.x):
		camera.limit_left  = map_rect.position.x * ts
		camera.limit_right = (map_rect.position.x + map_rect.size.x) * ts
		print("[CAMERA] x limits applied — left=", camera.limit_left,
			" right=", camera.limit_right)
	else:
		print("[CAMERA] x limits skipped (map narrower than viewport)")
	## Y axis: only lock if the map is taller than the viewport.
	if map_px_h > int(vp_size.y):
		camera.limit_top    = map_rect.position.y * ts
		camera.limit_bottom = (map_rect.position.y + map_rect.size.y) * ts
		print("[CAMERA] y limits applied — top=", camera.limit_top,
			" bottom=", camera.limit_bottom)
	else:
		print("[CAMERA] y limits skipped (map shorter than viewport)")

## Called by the crawler when the player presses the Ghost Trail key.
## Delegates to GhostTrailManager.place_spore(); safe to call if the manager
## is not yet initialised (e.g. during scene setup).
func try_place_spore(tile: Vector2i) -> void:
	if _ghost_trail_manager == null:
		push_error("try_place_spore: GhostTrailManager not initialised")
		return
	_ghost_trail_manager.place_spore(tile)

## end explore_mode.gd
