## guard_nodule.gd
## A Guard Nodule: a stationary bioluminescent threat in ExploreMode.
## Phase 5.1: placement and dim light only. Movement added in 5.2.
## Spawned at runtime by explore_mode._spawn_guard_nodules() — not placed
## as a scene file. The visual sprite comes from the tile painted on the
## Markers layer; this node contributes a PointLight2D (room illumination)
## and a small additive bloom Sprite2D (coloured self-glow on the emitter).
extends Node2D

const GLOW_TEXTURE := preload("res://Assets/Resources/glowlight.tres")

## White PointLight2D — illuminates surrounding tiles neutrally.
## Keeping the light white prevents the floor from being tinted green
## (coloured lights in Godot 2D multiply against tile colours, which reads
## as paint rather than emission). The bloom sprite below handles the colour.
const LIGHT_ENERGY  : float = 0.4
const LIGHT_SCALE   : float = 1.5
const LIGHT_COLOUR  : Color = Color(1, 1, 1)

## Additive bloom sprite — makes the nodule sprite appear to glow green.
## BLEND_MODE_ADD adds the sprite's pixel values on top of whatever is below,
## brightening only the pixels it covers without tinting distant floor tiles.
const BLOOM_COLOUR  : Color = Color(0.2, 0.65, 0.28)  ## green emission, toned down
const BLOOM_SCALE   : float = 0.5                    ## tight halo, ~1 tile radius

## LightRegistry ID for this nodule's light.
## Stored so we can deregister cleanly when the node leaves the tree.
var _light_id: int = -1


func _ready() -> void:
	## White PointLight2D for neutral room illumination.
	var light := PointLight2D.new()
	light.texture       = GLOW_TEXTURE
	light.color         = LIGHT_COLOUR
	light.energy        = LIGHT_ENERGY
	light.texture_scale = LIGHT_SCALE
	add_child(light)

	## Small additive Sprite2D centred on the nodule for coloured self-glow.
	## This separates "what colour does the emitter appear to be" from
	## "what colour does the light cast on the floor."
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var bloom := Sprite2D.new()
	bloom.texture  = GLOW_TEXTURE
	bloom.material = mat
	bloom.modulate = BLOOM_COLOUR
	bloom.scale    = Vector2(BLOOM_SCALE, BLOOM_SCALE)
	add_child(bloom)

	## Register with LightRegistry so future parasite AI can locate this light.
	_light_id = LightRegistry.register_light(global_position, LIGHT_ENERGY)
	print("[NODULE] spawned at world pos ", global_position, "  light_id=", _light_id)


func _exit_tree() -> void:
	## Deregister from LightRegistry to avoid stale entries on run reset.
	if _light_id >= 0:
		LightRegistry.deregister_light(_light_id)
		_light_id = -1
