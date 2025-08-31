# res://System/coil_query.gd
# Read-only tile queries shared by Builder/Explore/etc. (instance-based)
extends RefCounted
class_name CoilQuery

func _get_tile_data(layer: TileMapLayer, coords: Vector2i) -> TileData:
	if layer == null:
		return null
	if layer.get_cell_source_id(coords) == -1:
		return null
	return layer.get_cell_tile_data(coords)

func has_tile(layer: TileMapLayer, coords: Vector2i) -> bool:
	if layer == null:
		return false
	return layer.get_cell_source_id(coords) != -1

func has_base(base_layer: TileMapLayer, coords: Vector2i) -> bool:
	return has_tile(base_layer, coords)

func has_wall(walls_layer: TileMapLayer, coords: Vector2i) -> bool:
	return has_tile(walls_layer, coords)

func get_hazard_kind(hazard_layer: TileMapLayer, coords: Vector2i) -> String:
	var td: TileData = _get_tile_data(hazard_layer, coords)
	if td == null:
		return ""
	var v = td.get_custom_data("hazard")
	if v is String:
		return String(v)
	return ""

func is_solid_wall(walls_layer: TileMapLayer, coords: Vector2i) -> bool:
	var td: TileData = _get_tile_data(walls_layer, coords)
	if td == null:
		# No wall tile at all -> not solid.
		return false
	# Preferred: explicit boolean
	var v = td.get_custom_data("is_solid")
	if v is bool:
		return v
	# Fallback: string kind ("SOLID" / "DIGEST")
	var k = td.get_custom_data("wall_kind")
	if k is String:
		return String(k) == "SOLID"
	# Unknown metadata -> be conservative.
	return true
