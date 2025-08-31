## coil_validator.gd
## Central map validation: spawn/heartroot counts, reachability, biomass.
extends RefCounted
class_name CoilValidator

const CoilQueryScript: GDScript = preload("res://System/coil_query.gd")

static func validate(
	base_layer: TileMapLayer,
	walls_layer: TileMapLayer,
	hazard_layer: TileMapLayer,
	marker_layer: TileMapLayer,
	biomass_used: int,
	biomass_cap: int,
	ignore_biomass: bool
) -> Dictionary:
	var messages: Array[String] = []
	var spawn: Vector2i = Vector2i(-999999, -999999)
	var heart: Vector2i = Vector2i(-999999, -999999)

	# 1) Exactly one Spawn and one Heartroot.
	var spawn_cells: Array[Vector2i] = _find_marker_cells(marker_layer, "is_spawn")
	var heart_cells: Array[Vector2i] = _find_marker_cells(marker_layer, "is_goal")

	if spawn_cells.size() != 1:
		messages.append("❌ Place exactly one Spawn (found %d)." % spawn_cells.size())
	else:
		spawn = spawn_cells[0]

	if heart_cells.size() != 1:
		messages.append("❌ Place exactly one Heartroot (found %d)." % heart_cells.size())
	else:
		heart = heart_cells[0]

	# 2) Path exists from Spawn -> Heartroot.
	if spawn.x > -900000 and heart.x > -900000:
		var q: CoilQuery = CoilQueryScript.new()
		var reachable := _is_reachable(q, base_layer, walls_layer, hazard_layer, spawn, heart)
		if not reachable:
			messages.append("❌ Heartroot unreachable from Spawn.")

	# 3) Biomass cap (unless dev bypass is enabled).
	if not ignore_biomass and biomass_used > biomass_cap:
		var over: int = biomass_used - biomass_cap
		messages.append("❌ Biomass over cap by %d (used %d / %d)." % [over, biomass_used, biomass_cap])

	var ok_flag: bool = messages.is_empty()

	return {
		"ok": ok_flag,
		"messages": messages,
		"spawn": spawn,
		"heart": heart
	}


static func _find_marker_cells(marker_layer: TileMapLayer, flag_key: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if marker_layer == null:
		return out

	for c in marker_layer.get_used_cells():
		var td: TileData = marker_layer.get_cell_tile_data(c)
		if td != null:
			var raw_flag = td.get_custom_data(flag_key)
			var has_flag := false
			if raw_flag is bool:
				has_flag = bool(raw_flag)
			if has_flag:
				out.append(c)

	return out


static func _is_reachable(
	q: CoilQuery,
	base_layer: TileMapLayer,
	walls_layer: TileMapLayer,
	_hazard_layer: TileMapLayer,
	start: Vector2i,
	goal: Vector2i
) -> bool:
	if start == goal:
		return true

	var visited: Dictionary = {}
	var queue: Array[Vector2i] = []
	queue.append(start)
	visited[start] = true

	# 4-way BFS.
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1)
	]

	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		if cur == goal:
			return true

		for d in dirs:
			var nxt: Vector2i = cur + d

			# Must be on Flesh.
			if not q.has_base(base_layer, nxt):
				continue

			# Solid walls block (digest walls do not).
			if q.is_solid_wall(walls_layer, nxt):
				continue

			if not visited.has(nxt):
				visited[nxt] = true
				queue.append(nxt)

	return false
