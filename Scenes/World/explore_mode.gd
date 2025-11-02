## explore_mode.gd
extends Node2D

const GridUtil := preload("res://System/grid.gd")

const CRAWLER_SCENE: PackedScene = preload("res://Scenes/Actors/Crawler.tscn")
@export var base_layer: TileMapLayer
@export var walls_layer: TileMapLayer
@export var hazard_layer: TileMapLayer
@export var marker_layer: TileMapLayer

func _ready() -> void:
	## 1) If Builder handed us a coil via the Autoload, rebuild the map now.
	#if has_node("/root/CoilSession"):
		#var cs: Node = get_node("/root/CoilSession")
		#var data_v: Variant = cs.get("pending_coil")
		#if typeof(data_v) == TYPE_DICTIONARY:
			#var data: Dictionary = data_v as Dictionary
			#_load_from_coil(data)  # fills base/walls/hazard/marker
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

	# If running in dev mode and you want to force a test loadout, you can do this:
	if has_node("/root/GameFlags") and has_node("/root/UpgradeState"):
		var gf: Node = get_node("/root/GameFlags")
		var us2: Node = get_node("/root/UpgradeState")
		# Example: force Hardened Skin ON for quick testing (set back to false when done)
		# Only run this inside dev mode.
		if bool(gf.get("dev_mode_enabled")):
			if us2.has_method("set_runtime_overrides"):
				us2.call("set_runtime_overrides", true, false, false)

	# 2) Spawn the crawler at the Spawn marker (or fallback)
	var crawler: Area2D = CRAWLER_SCENE.instantiate()
	crawler.base_layer   = base_layer
	crawler.wall_layer   = walls_layer
	crawler.hazard_layer = hazard_layer
	crawler.marker_layer = marker_layer

	var spawn_tile: Vector2i = get_spawn_position()
	crawler.position = GridUtil.to_world(spawn_tile)  # your util converts map→world
	add_child(crawler)

	var row_path: String = "HUD/SafeArea/BottomCenter/UpgradeRow"
	var row: Node = get_node_or_null(row_path)
	if row != null and row.has_method("set_controller"):
		var controller: Node = crawler.get_node_or_null("UpgradeController")
		row.call("set_controller", controller)

	# --- NEW: mirror global UpgradeState into the Crawler's UpgradeController once ---
	_apply_upgrade_state_to_crawler(crawler)

# NEW: copies global upgrade booleans into the crawler's UpgradeController node.
func _apply_upgrade_state_to_crawler(crawler: Area2D) -> void:
	if crawler == null:
		return
	# Find child node by name (scene uses "UpgradeController" as a child of Crawler)
	var uc: Node = crawler.get_node_or_null("UpgradeController")
	if uc == null:
		return

	# Read from UpgradeState singleton
	var hardened: bool = false
	var acid: bool = false
	var ghost: bool = false

	if has_node("/root/UpgradeState"):
		var us: Node = get_node("/root/UpgradeState")
		if us.has_method("has_hardened_skin"):
			hardened = bool(us.call("has_hardened_skin"))
		if us.has_method("has_acid_sac"):
			acid = bool(us.call("has_acid_sac"))
		if us.has_method("has_ghost_trail"):
			ghost = bool(us.call("has_ghost_trail"))

	# Set values explicitly using your controller's API:
	# (We do not have direct setters, so we sync by toggling only when needed.)
	if uc.has_method("has_upgrade") and uc.has_method("toggle_upgrade"):
		# Hardened
		var need_hardened: bool = hardened
		var has_hardened_now: bool = bool(uc.call("has_upgrade", uc.Upgrade.HARDENED_SKIN))
		if need_hardened and (not has_hardened_now):
			uc.call("toggle_upgrade", uc.Upgrade.HARDENED_SKIN)
		if (not need_hardened) and has_hardened_now:
			uc.call("toggle_upgrade", uc.Upgrade.HARDENED_SKIN)

		# Acid
		var need_acid: bool = acid
		var has_acid_now: bool = bool(uc.call("has_upgrade", uc.Upgrade.ACID_SAC))
		if need_acid and (not has_acid_now):
			uc.call("toggle_upgrade", uc.Upgrade.ACID_SAC)
		if (not need_acid) and has_acid_now:
			uc.call("toggle_upgrade", uc.Upgrade.ACID_SAC)

		# Ghost
		var need_ghost: bool = ghost
		var has_ghost_now: bool = bool(uc.call("has_upgrade", uc.Upgrade.GHOST_TRAIL))
		if need_ghost and (not has_ghost_now):
			uc.call("toggle_upgrade", uc.Upgrade.GHOST_TRAIL)
		if (not need_ghost) and has_ghost_now:
			uc.call("toggle_upgrade", uc.Upgrade.GHOST_TRAIL)
	print("UpgradeState → Crawler sync done (H:", hardened, ", A:", acid, ", G:", ghost, ")")

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
