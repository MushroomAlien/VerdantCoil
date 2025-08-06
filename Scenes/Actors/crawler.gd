## crawler.gd
# Movement logic for the crawler using centralized grid logic

extends Area2D

#const BASE_LAYER_INDEX: int = 0

# --- Movement Settings ---
@export var move_speed: float = 5.0  # Tiles per second
var tilemap: TileMap
@export_category("Layer Settings")
@export_range(0, 7, 1)
var base_layer_index: int = 0

# --- Internal State ---
var _is_moving: bool = false
var _move_direction := Vector2.ZERO

func _ready() -> void:
	print("Crawler ready at ", position)
	var camera := get_node("Camera2D")
	if camera:
		camera.make_current()

func _unhandled_input(event: InputEvent) -> void:
	# Toggle upgrades for testing
	var upgrade_controller = get_node("UpgradeController")
	if event.is_action_pressed("toggle_upgrade_1"):
		upgrade_controller.toggle_upgrade(upgrade_controller.Upgrade.HARDENED_SKIN)
	elif event.is_action_pressed("toggle_upgrade_2"):
		upgrade_controller.toggle_upgrade(upgrade_controller.Upgrade.ACID_SAC)
	elif event.is_action_pressed("toggle_upgrade_3"):
		upgrade_controller.toggle_upgrade(upgrade_controller.Upgrade.GHOST_TRAIL)
	
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
	
	# Convert current world position to grid tile coordinates
	var current_tile := Grid.to_tile_coords(position)
	var next_tile := current_tile + Vector2i(_move_direction)
	
		# Prevent movement outside painted area
	var map_bounds: Rect2i = tilemap.get_used_rect()
	if not map_bounds.has_point(next_tile):
		print("Blocked: outside map bounds")
		_is_moving = false
		return
	
	# Get tile source ID at next_tile (layer 0)
	var tile_id: int = tilemap.get_cell_source_id(base_layer_index, next_tile)
	if tile_id == -1:
		print("Blocked: no tile at target: ", next_tile)
		_is_moving = false
		return
	
	# Fetch TileData to check for custom metadata
	var tile_data := tilemap.get_cell_tile_data(base_layer_index, next_tile)
	if tile_data == null:
		print("Blocked: missing tile data at ", next_tile)
		_is_moving = false
		return
	
	# Check walkable metadata (defaults to false if missing)
	var is_walkable: bool = tile_data.get_custom_data("walkable")
	if is_walkable != true:
		print("Blocked: tile at ", next_tile, " is not walkable")
		_is_moving = false
		return
	
	# Move to next tile using a Tween
	var target_pos = Grid.to_world(next_tile)
	var tween = create_tween()
	tween.tween_property(self, "position", target_pos, 1.0 / move_speed)
	tween.connect("finished", _on_move_finished)

func _on_move_finished() -> void:
	_is_moving = false
## end crawler.gd
