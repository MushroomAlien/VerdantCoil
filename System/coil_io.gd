# res://System/coil_io.gd
# Pure save/load helpers for TileMapLayers.
extends RefCounted

static func serialize_layer(layer: TileMapLayer) -> Array:
	var out: Array = []
	if layer == null:
		return out
	for coords in layer.get_used_cells():
		var source_id: int = layer.get_cell_source_id(coords)
		if source_id == -1:
			continue
		var atlas: Vector2i = layer.get_cell_atlas_coords(coords)
		var cell: Dictionary = {}
		cell["x"] = coords.x
		cell["y"] = coords.y
		cell["source_id"] = source_id
		cell["atlas_x"] = atlas.x
		cell["atlas_y"] = atlas.y
		out.append(cell)
	return out


static func rebuild_layer_from_json(arr_v: Variant, layer: TileMapLayer) -> void:
	if layer == null:
		return
	if typeof(arr_v) != TYPE_ARRAY:
		return
	var arr: Array = arr_v
	for cell_v in arr:
		if typeof(cell_v) != TYPE_DICTIONARY:
			continue
		var cell: Dictionary = cell_v
		if not (cell.has("x") and cell.has("y") and cell.has("source_id")):
			continue
		var coords: Vector2i = Vector2i(int(cell["x"]), int(cell["y"]))
		var source_id: int = int(cell["source_id"])
		var ac: Vector2i = Vector2i.ZERO
		if cell.has("atlas_x") and cell.has("atlas_y"):
			ac = Vector2i(int(cell["atlas_x"]), int(cell["atlas_y"]))
		layer.set_cell(coords, source_id, ac)


static func apply_coil(
	data: Dictionary,
	base_layer: TileMapLayer,
	walls_layer: TileMapLayer,
	hazard_layer: TileMapLayer,
	marker_layer: TileMapLayer
) -> void:
	# Clear targets first
	if base_layer != null:
		base_layer.clear()
	if walls_layer != null:
		walls_layer.clear()
	if hazard_layer != null:
		hazard_layer.clear()
	if marker_layer != null:
		marker_layer.clear()

	# Build from JSON
	var layers_any: Variant = data.get("layers", {})
	if typeof(layers_any) != TYPE_DICTIONARY:
		return
	var layers: Dictionary = layers_any

	if layers.has("base"):
		rebuild_layer_from_json(layers["base"], base_layer)
	if layers.has("walls"):
		rebuild_layer_from_json(layers["walls"], walls_layer)
	if layers.has("hazard"):
		rebuild_layer_from_json(layers["hazard"], hazard_layer)
	if layers.has("marker"):
		rebuild_layer_from_json(layers["marker"], marker_layer)
