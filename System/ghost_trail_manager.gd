## ghost_trail_manager.gd
## Manages the Ghost Trail upgrade. When the upgrade is active, the crawler
## leaves a bioluminescent spore tile on every cell it walks off.
## Each spore emits its own dim PointLight2D so the trail is a real light
## source in the scene — visible to future parasite AI via LightRegistry.
## Spores persist for the run and are fully cleared on reset.
extends RefCounted

## The TileMapLayer spore tiles are painted onto (GhostTrailLayer).
var _layer: TileMapLayer
## TileSet source ID for the spore tile.
var _source_id: int
## Atlas coordinates of the spore tile (yellow blob placeholder, atlas 35,9).
var _spore_atlas: Vector2i
## The Node spore PointLight2D instances are parented to (ExploreMode).
## Must be a Node2D in world space so light positions are correct.
var _parent: Node2D
## All active spore PointLight2D nodes, kept for cleanup on reset.
var _spore_lights: Array[PointLight2D] = []
## Additive bloom Sprite2D for each spore, one-to-one with _spore_lights.
## Gives each spore a coloured self-glow without tinting the surrounding floor.
var _spore_blooms: Array[Sprite2D] = []
## LightRegistry IDs for each spore light, kept for deregistration on reset.
var _spore_light_ids: Array[int] = []

## The glow texture used by the crawler's GlowLight.
## Spore lights reuse the same texture at lower energy and smaller scale.
const GLOW_TEXTURE := preload("res://Assets/Resources/glowlight.tres")
## Grid utility for tile-to-world conversion (tile centre, not corner).
const GridUtil := preload("res://System/grid.gd")
## Maximum number of simultaneously glowing spore lights.
## When a new spore is placed beyond this cap, the oldest light is disabled
## (the tile sprite remains; only the glow is removed). Placement itself is
## always allowed — there is no hard limit on spore count.
const MAX_SPORES: int = 5


## Initialise the manager. Must be called before place_spore().
## layer      — GhostTrailLayer TileMapLayer node
## parent     — ExploreMode Node2D (spore lights added as its children)
## source_id  — TileSet atlas source ID for the spore tile
## atlas      — atlas coordinates of the spore tile
func init(layer: TileMapLayer, parent: Node2D,
		source_id: int, atlas: Vector2i) -> void:
	_layer     = layer
	_parent    = parent
	_source_id = source_id
	_spore_atlas = atlas
	reset()  ## ensure clean state on (re)initialisation


## Place a bioluminescent spore at the given tile coordinates.
## Paints the spore tile, spawns a white PointLight2D for room illumination,
## and spawns a small additive bloom Sprite2D for coloured self-glow on the
## spore tile itself. The two-layer approach prevents the amber colour from
## tinting distant floor tiles (which reads as paint rather than emission).
func place_spore(tile: Vector2i) -> void:
	if _layer == null or _parent == null:
		push_error("GhostTrailManager.place_spore: not initialised")
		return

	## Paint the spore tile onto the ghost trail layer.
	_layer.set_cell(tile, _source_id, _spore_atlas)

	## GridUtil.to_world() returns the tile centre in world space.
	## map_to_local() returns the top-left corner, not the centre.
	var world_pos: Vector2 = GridUtil.to_world(tile)
	var local_pos: Vector2 = _parent.to_local(world_pos)

	## White PointLight2D — illuminates surrounding tiles neutrally.
	## Coloured lights in Godot 2D multiply against tile colours, so using
	## white here prevents amber tinting the floor around each spore.
	var light := PointLight2D.new()
	light.texture       = GLOW_TEXTURE
	light.color         = Color(1, 1, 1)
	light.energy        = 0.7
	light.texture_scale = 2.5
	light.position      = local_pos
	_parent.add_child(light)
	_spore_lights.append(light)

	## Additive bloom Sprite2D — amber coloured self-glow on the spore tile.
	## BLEND_MODE_ADD brightens only the pixels it covers, giving the spore
	## an amber halo without tinting distant floor tiles.
	var bloom_mat := CanvasItemMaterial.new()
	bloom_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var bloom := Sprite2D.new()
	bloom.texture  = GLOW_TEXTURE
	bloom.material = bloom_mat
	bloom.modulate = Color(0.65, 0.48, 0.25)  ## warm amber bloom, toned down
	bloom.scale    = Vector2(0.4, 0.4)       ## tight halo, ~1 tile
	bloom.position = local_pos
	_parent.add_child(bloom)
	_spore_blooms.append(bloom)

	## If we have exceeded the max active spores, disable the oldest still-lit
	## light. The index advances with each new spore so a different light is
	## darkened every time — not always index 0.
	## Formula: size-1 is the newest; size-1-MAX_SPORES is the first to darken.
	if _spore_lights.size() > MAX_SPORES:
		_spore_lights[_spore_lights.size() - 1 - MAX_SPORES].enabled = false

	print("[SPORE] placed at ", tile, " total_spores=", _spore_lights.size())

	## Register in LightRegistry so parasite AI can query it later.
	var id: int = LightRegistry.register_light(light.global_position, light.energy)
	_spore_light_ids.append(id)


## Remove all spore tiles, lights, and bloom sprites. Call on run reset.
func reset() -> void:
	## Clear all painted spore tiles from the ghost trail layer.
	if _layer != null:
		_layer.clear()

	## Remove all spore PointLight2D nodes from the scene tree.
	for light: PointLight2D in _spore_lights:
		if is_instance_valid(light):
			light.queue_free()
	_spore_lights.clear()

	## Remove all spore bloom Sprite2D nodes from the scene tree.
	for bloom: Sprite2D in _spore_blooms:
		if is_instance_valid(bloom):
			bloom.queue_free()
	_spore_blooms.clear()

	## Deregister all spore lights from LightRegistry.
	for id: int in _spore_light_ids:
		LightRegistry.deregister_light(id)
	_spore_light_ids.clear()
