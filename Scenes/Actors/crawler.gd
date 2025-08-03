## crawler.gd
# Movement logic for the crawler using centralized grid logic

extends Area2D

# --- Movement Settings ---
@export var move_speed: float = 5.0  # Tiles per second
@export var spawn_pos: Vector2 = Vector2(384.0, 736.0)  # World-space spawn point

# --- Internal State ---
var _is_moving: bool = false
var _move_direction := Vector2.ZERO

func _ready() -> void:
	# Snap to grid using centralized grid logic
	position = Grid.snap_position(spawn_pos)
	print("Crawler ready at ", position)
	var camera := get_node("Camera2D")
	if camera:
		camera.make_current()

func _unhandled_input(event: InputEvent) -> void:
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
	
	# Get current tile
	var current_tile := Grid.to_tile_coords(position)
	var next_tile := current_tile + Vector2i(_move_direction)
	
	var tilemap := get_parent().get_node("TileMapBase")
	
	# Prevent movement outside painted area
	var map_bounds: Rect2i = tilemap.get_used_rect()
	if not map_bounds.has_point(next_tile):
		print("Blocked: outside map bounds")
		_is_moving = false
		return
	
	# Get tile source ID at next_tile (layer 0)
	var tile_id: int = tilemap.get_cell_source_id(0, next_tile)
	if tile_id == -1:
		print("Blocked: no tile at target")
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
