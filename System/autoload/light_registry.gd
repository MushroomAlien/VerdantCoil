## light_registry.gd
## Autoload singleton. Tracks all active light sources in the scene by world
## position and energy so future systems (e.g. parasite AI) can query them
## without coupling to the scene tree.
extends Node

## Internal list of registered light entries.
## Each entry: { "id": int, "position": Vector2, "energy": float }
var _lights: Array[Dictionary] = []

## Counter for generating unique IDs.
var _next_id: int = 0


## Register a new light source. Returns an integer ID used for updates
## and removal. Call when a PointLight2D becomes active (crawler spawn,
## spore placed, etc.)
func register_light(world_pos: Vector2, energy: float) -> int:
	var id: int = _next_id
	_next_id += 1
	_lights.append({ "id": id, "position": world_pos, "energy": energy })
	return id


## Update the position and energy of a registered light.
## Call when a light source moves (e.g. the crawler steps to a new tile).
func update_light(id: int, world_pos: Vector2, energy: float) -> void:
	for i: int in range(_lights.size()):
		var entry: Dictionary = _lights[i]
		if entry["id"] == id:
			_lights[i] = { "id": id, "position": world_pos, "energy": energy }
			return
	push_error("LightRegistry.update_light: ID not found: " + str(id))


## Remove a single light source by ID.
## Call when a light is destroyed (e.g. individual spore cleared).
func deregister_light(id: int) -> void:
	for i: int in range(_lights.size()):
		if _lights[i]["id"] == id:
			_lights.remove_at(i)
			return
	push_error("LightRegistry.deregister_light: ID not found: " + str(id))


## Remove all registered lights. Call on run reset.
func clear() -> void:
	_lights.clear()


## Returns a snapshot of all active lights for read-only querying.
## Future parasite AI calls this to find the nearest or brightest source.
func get_all_lights() -> Array[Dictionary]:
	return _lights.duplicate()
