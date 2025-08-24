## explore_mode.gd
extends Node2D

const GridUtil := preload("res://System/grid.gd")

@onready var crawler_scene := preload("res://Scenes/Actors/Crawler.tscn")
@export var base_layer: TileMapLayer
@export var walls_layer: TileMapLayer
@export var hazard_layer: TileMapLayer
@export var marker_layer: TileMapLayer

func _ready() -> void:
	var crawler = crawler_scene.instantiate()
	
	# Find the tilemap layer from the scene tree
	crawler.base_layer    = base_layer
	crawler.wall_layer    = walls_layer
	crawler.hazard_layer  = hazard_layer
	crawler.marker_layer  = marker_layer
	
	# Now spawn the crawler
	var spawn_tile := get_spawn_position()
	crawler.position = GridUtil.to_world(spawn_tile)
	add_child(crawler)
	
## Returns the tile coordinates of the spawn tile marked with `is_spawn = true`.
## Falls back to (12, 23) if none is found.
func _process(_delta: float) -> void:
	pass
		
	## upgrade debugging tools:
	#var crawler = $Crawler
	#var uc = crawler.get_node("UpgradeController")
		#var debug_text := ""
	#debug_text += "Hardened Skin: %s\n" % uc.has_upgrade(uc.Upgrade.HARDENED_SKIN)
	#debug_text += "Acid Sac: %s\n" % uc.has_upgrade(uc.Upgrade.ACID_SAC)
	#debug_text += "Ghost Trail: %s\n" % uc.has_upgrade(uc.Upgrade.GHOST_TRAIL)
	#$CanvasLayer/UpgradeDebugLabel.text = debug_text

## Returns the tile coordinates of the tile marked with is_spawn = true in the "marker" layer.
## If none is found, falls back to (12, 23) with a warning.
## Returns the tile coordinates of the spawn tile marked with `is_spawn = true`.
## This uses TileMap layer index 3 (marker). Falls back to (12, 23) if none is found.
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

## end explore_mode.gd
