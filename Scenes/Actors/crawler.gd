## crawler.gd
# Movement logic for the crawler using centralized grid logic
# Godot 4.4.1

extends Area2D

const GridUtil := preload("res://System/grid.gd")

@export var base_layer:   TileMapLayer
@export var wall_layer:   TileMapLayer
@export var hazard_layer: TileMapLayer
@export var marker_layer: TileMapLayer

# --- Movement Settings ---
@export var move_speed: float = 5.0  # Tiles per second

# --- Internal State ---
var _is_moving: bool = false
var _move_direction: Vector2 = Vector2.ZERO

# Simple input-skip slow (Sticky uses this to "eat" N inputs after entry)
var _skip_inputs: int = 0

func _ready() -> void:
	if base_layer == null: push_error("Crawler.base_layer not set")
	if wall_layer == null: push_error("Crawler.wall_layer not set")
	if hazard_layer == null: push_error("Crawler.hazard_layer not set")
	if marker_layer == null: push_error("Crawler.marker_layer not set")
	print("Crawler ready at ", position)
	
	var camera: Camera2D = get_node("Camera2D")
	if camera:
		camera.make_current()

func _get_tile_data(layer: TileMapLayer, coords: Vector2i) -> TileData:
	if layer.get_cell_source_id(coords) == -1:
		return null
	return layer.get_cell_tile_data(coords)

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
	
	# Safety guard – helpful during wiring
	if base_layer == null or wall_layer == null or hazard_layer == null or marker_layer == null:
		push_error("Crawler layers not assigned. Check ExploreMode exports & assignment.")
		_is_moving = false
		return
	
	# 1) Where are we trying to go?
	var current_tile := GridUtil.to_tile_coords(position)
	var next_tile := current_tile + Vector2i(_move_direction)
	
	# 2) Bounds check (use Base as the canonical footprint)
	var base_used: Rect2i = base_layer.get_used_rect()
	if not base_used.has_point(next_tile):
		print("Blocked: outside map bounds")
		_is_moving = false
		return
	
	# 3) Must have Flesh (walkable) on Base
	var base_td := _get_tile_data(base_layer, next_tile)
	if base_td == null:
		print("Blocked: no base tile at ", next_tile)
		_is_moving = false
		return
	
	var base_walkable: bool = _get_bool(base_td, "walkable", false)
	if base_walkable != true:
		print("Blocked: base not walkable at ", next_tile)
		_is_moving = false
		return
	
	# 4) Walls over Flesh can block (digestible is gated by Acid Sac)
	var wall_td := _get_tile_data(wall_layer, next_tile)
	if wall_td != null:
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
	var target_pos := GridUtil.to_world(next_tile)
	var tween := create_tween()
	tween.tween_property(self, "position", target_pos, 1.0 / move_speed)
	# When we arrive, resolve tile effects, then re-enable input
	tween.finished.connect(func():
		_on_arrived_at(next_tile)
	)

func _on_arrived_at(tile: Vector2i) -> void:
	# Hazards layer effects
	var hazard_td := _get_tile_data(hazard_layer, tile)
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
	
	# Dissolve digestible wall on entry if Acid Sac is active
	var wall_td := _get_tile_data(wall_layer, tile)
	if wall_td != null and _is_digest_wall(wall_td):
		var upgrades = get_node_or_null("UpgradeController")
		var acid_on := false
		if upgrades != null:
			acid_on = upgrades.has_upgrade(upgrades.Upgrade.ACID_SAC)
		if acid_on:
			wall_layer.erase_cell(tile)
			# (Optional) TODO: spawn particles/SFX here
	
	# Goal check (Marker layer)
	var marker_td := _get_tile_data(marker_layer, tile)
	if marker_td != null:
		var reached_goal: bool = _get_bool(marker_td, "is_goal", false)
		if reached_goal:
			_win_and_return()
			return
	
	# If we didn’t early-return due to winning, re-enable input now.
	_is_moving = false

func _win_and_return() -> void:
	# Lock input so we don't queue more moves during the scene swap
	_is_moving = true
	print("🏆 Reached Heartroot — WIN!")
	if has_node("/root/CoilSession"):
		get_node("/root/CoilSession").call("return_to_builder")
	else:
		# Fallback if the autoload isn't present (update path if needed)
		get_tree().change_scene_to_file("res://Scenes/BuilderMode/BuilderMode.tscn")

# Increments the number of movement inputs to ignore (used by Sticky slow)
func _consume_future_inputs(n: int) -> void:
	_skip_inputs += n

func _is_digest_wall(td: TileData) -> bool:
	if td == null:
		return false
	# Primary: explicit boolean
	if _get_bool(td, "digestible", false):
		return true
	# Fallback: string kind
	var kind := _get_str(td, "wall_kind", "")
	return kind == "DIGEST" or kind == "DIGESTIBLE"

## end crawler.gd
