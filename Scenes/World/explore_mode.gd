## explore_mode.gd
extends Node2D

@onready var crawler_scene := preload("res://Scenes/Actors/Crawler.tscn")

func _ready() -> void:
	var crawler = crawler_scene.instantiate()
	
	# Find the tilemap layer from the scene tree
	var tilemap_node = $CoilMap
	crawler.tilemap = tilemap_node
	
	#var tilemap_layer = $CoilMap/BaseTileMap  # Adjust name to match your actual node
	#crawler.tilemap = tilemap_layer  # Set exported variable
	
	# Now spawn the crawler
	var spawn_tile := get_spawn_position()
	crawler.position = Grid.to_world(spawn_tile)
	add_child(crawler)
	
## Returns the tile coordinates of the spawn tile marked with `is_spawn = true`.
## Falls back to (12, 23) if none is found.

## Returns the tile coordinates of the tile marked with is_spawn = true in the "Overlay" layer.
## If none is found, falls back to (12, 23) with a warning.
## Returns the tile coordinates of the spawn tile marked with `is_spawn = true`.
## This uses TileMap layer index 1 (Overlay). Falls back to (12, 23) if none is found.
func get_spawn_position() -> Vector2i:
	# Reference to the TileMap node that contains layers
	var tilemap: TileMap = $CoilMap

	# Use explicit integer for layer index (Overlay should be at index 1)
	var layer_index: int = 1

	# Print how many layers we have for debugging
	print("🧱 CoilMap layer count = ", tilemap.get_layers_count())

	# Confirm the layer index is valid
	if layer_index >= tilemap.get_layers_count():
		push_error("🚫 Overlay layer index out of bounds!")
		return Vector2i(12, 23)

	# Get all painted tile coordinates in the overlay layer
	var spawn_cells: Array[Vector2i] = tilemap.get_used_cells(layer_index)
	print("📋 Potential spawn cells: ", spawn_cells.size(), spawn_cells)

	# Check each cell for the is_spawn metadata
	for coords: Vector2i in spawn_cells:
		print("🔎 Checking tile at ", coords)
		
		# Fetch tile data at this layer and position
		var tile_data: TileData = tilemap.get_cell_tile_data(layer_index, coords)
		
		if tile_data == null:
			print("🚫 No tile data at ", coords)
			continue

		# Look for the custom metadata key 'is_spawn'
		var is_spawn: bool = tile_data.get_custom_data("is_spawn")
		print("🔍 Tile custom data 'is_spawn' = ", is_spawn)

		if is_spawn == true:
			print("✅ Spawn tile FOUND at ", coords)
			return coords

	# If no tile marked as spawn was found, fall back
	push_error("❌ No spawn tile found in overlay layer! Using fallback.")
	return Vector2i(12, 23)

## end explore_mode.gd
