## crawler.gd
# Movement logic for the crawler using centralized grid logic
# Godot 4.4.1

extends Area2D

#const BASE_LAYER_INDEX: int = 0   # (legacy) Not used anymore; we now use fixed layer constants below.

# --- Movement Settings ---
@export var move_speed: float = 5.0  # Tiles per second
var tilemap: TileMap
@export_category("Layer Settings")
@export_range(0, 7, 1)
var base_layer_index: int = 0  # (legacy) Safe to remove later; replaced by LAYER_* constants.

# --- Internal State ---
var _is_moving: bool = false
var _move_direction := Vector2.ZERO

# --- Layer indices (Phase 1.3 layout) ---
const LAYER_BASE := 0      # Flesh (walkable floor) lives here
const LAYER_WALLS := 1     # Solid & digestible walls, rendered above Flesh
const LAYER_HAZARDS := 2   # Acid / Sticky overlays, rendered above Flesh
const LAYER_MARKERS := 3   # Spawn / Heartroot markers

# Simple input-skip slow (Sticky uses this to "eat" N inputs after entry)
var _skip_inputs := 0

func _ready() -> void:
	print("Crawler ready at ", position)
	var camera := get_node("Camera2D")
	if camera:
		camera.make_current()

func _get_tile_data(layer: int, coords: Vector2i) -> TileData:
	# Returns TileData or null if nothing is painted on that layer at coords
	if tilemap.get_cell_source_id(layer, coords) == -1:
		return null
	return tilemap.get_cell_tile_data(layer, coords)

# --- Safe metadata readers (string/int/bool) ---
func _get_str(td: TileData, key: String, default_val: String = "") -> String:
	# Returns key as String if present & typed; otherwise default_val
	var v = td.get_custom_data(key)
	return (v as String) if (v is String) else default_val

func _get_int(td: TileData, key: String, default_val: int = 0) -> int:
	# Returns key as int if present & typed; otherwise default_val
	var v = td.get_custom_data(key)
	return (v as int) if (typeof(v) == TYPE_INT) else default_val

func _get_bool(td: TileData, key: String, default_val: bool = false) -> bool:
	# Returns key as bool if present & typed; otherwise default_val
	var v = td.get_custom_data(key)
	return (v as bool) if (v is bool) else default_val

func _unhandled_input(event: InputEvent) -> void:
	# Toggle upgrades for testing
	var upgrade_controller = get_node("UpgradeController")
	if event.is_action_pressed("toggle_upgrade_1"):
		upgrade_controller.toggle_upgrade(upgrade_controller.Upgrade.HARDENED_SKIN)
	elif event.is_action_pressed("toggle_upgrade_2"):
		upgrade_controller.toggle_upgrade(upgrade_controller.Upgrade.ACID_SAC)
	elif event.is_action_pressed("toggle_upgrade_3"):
		upgrade_controller.toggle_upgrade(upgrade_controller.Upgrade.GHOST_TRAIL)
		
	# --- SLOW/SKIP GUARD (must run BEFORE any movement handling) ---
	# If Sticky applied N slow "ticks", we ignore the next N movement inputs.
	# We run this check here so the keypress is consumed BEFORE we even read directions.
	if _skip_inputs > 0:
		_skip_inputs -= 1
		return
		
	# Block new input while the tween is running
	if _is_moving:
		return
		
	# Directional input via InputMap
	if event.is_action_pressed("move_up"):
		_move_direction = Vector2.UP
	elif event.is_action_pressed("move_down"):
		_move_direction = Vector2.DOWN
	elif event.is_action_pressed("move_left"):
		_move_direction = Vector2.LEFT
	elif event.is_action_pressed("move_right"):
		_move_direction = Vector2.RIGHT
	else:
		return
	_start_move()

func _start_move() -> void:
	_is_moving = true

	# 1) Where are we trying to go?
	var current_tile := Grid.to_tile_coords(position)
	var next_tile := current_tile + Vector2i(_move_direction)

	# 2) Bounds check (use Base as the canonical footprint)
	var base_used: Rect2i = tilemap.get_used_rect()
	if not base_used.has_point(next_tile):
		print("Blocked: outside map bounds")
		_is_moving = false
		return

	# 3) Must have Flesh (walkable) on Base
	var base_td := _get_tile_data(LAYER_BASE, next_tile)
	if base_td == null:
		print("Blocked: no base tile at ", next_tile)
		_is_moving = false
		return

	#var base_walkable: bool = base_td.get_custom_data("walkable")
	var base_walkable: bool = _get_bool(base_td, "walkable", false)

	if base_walkable != true:
		print("Blocked: base not walkable at ", next_tile)
		_is_moving = false
		return

	# 4) Walls over Flesh can block (digestible is gated by Acid Sac)
	var wall_td := _get_tile_data(LAYER_WALLS, next_tile)
	if wall_td != null:
		#var wall_walkable: bool = wall_td.get_custom_data("walkable") # usually false
		#var wall_digestible: bool = wall_td.get_custom_data("digestible")
		var wall_walkable: bool = _get_bool(wall_td, "walkable", false) # usually false
		var wall_digestible: bool = _get_bool(wall_td, "digestible", false)
		var upgrades := get_node_or_null("UpgradeController")
		var acid_on: bool = false
		if upgrades != null:
			acid_on = upgrades.has_upgrade(upgrades.Upgrade.ACID_SAC)

		var can_pass_wall: bool = wall_walkable or (wall_digestible and acid_on)
		if not can_pass_wall:
			print("Blocked: wall at ", next_tile, " (need Acid Sac if digestible)")
			_is_moving = false
			return

	# 5) All checks passed → move
	var target_pos = Grid.to_world(next_tile)
	var tween = create_tween()
	tween.tween_property(self, "position", target_pos, 1.0 / move_speed)

	# Apply effects after we arrive (hazards, goal check, then release input lock)
	tween.connect("finished", func ():
		_on_arrived_at(next_tile)
	)

func _on_move_finished() -> void:
	# (Legacy callback) Currently unused because we inline a lambda above.
	# Kept for reference; safe to remove later once you're comfortable.
	_is_moving = false

func _on_arrived_at(tile: Vector2i) -> void:
	# Hazards layer effects
	# Hazards layer effects
	var hazard_td := _get_tile_data(LAYER_HAZARDS, tile)
	if hazard_td != null:
		var hazard := _get_str(hazard_td, "hazard", "")
		if hazard == "acid":
			var dmg := _get_int(hazard_td, "damage_per_step", 0)
			var upgrades = get_node_or_null("UpgradeController")
			# Simple mitigation: Hardened Skin reduces 1 (never below 0)
			if upgrades != null and upgrades.has_upgrade(upgrades.Upgrade.HARDENED_SKIN):
				dmg = max(0, dmg - 1)
			if dmg > 0:
				print("Acid damage: ", dmg)
				# TODO: hook into health system when added
		elif hazard == "sticky":
			var slow_ticks := _get_int(hazard_td, "slow_ticks", 0)
			if slow_ticks > 0:
				# Easiest MVP: eat N inputs after this move
				_consume_future_inputs(slow_ticks)	
	# Goal check (Markers)
	var marker_td := _get_tile_data(LAYER_MARKERS, tile)
	if marker_td != null and bool(marker_td.get_custom_data("is_goal") or false):
		print("🏆 Reached Heartroot — WIN!")
	# Release input lock after all on-enter effects resolve
	_is_moving = false

# Increments the number of movement inputs to ignore (used by Sticky slow)
func _consume_future_inputs(n: int) -> void:
	_skip_inputs += n

## end crawler.gd
