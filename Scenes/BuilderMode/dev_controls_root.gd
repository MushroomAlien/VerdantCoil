## res://UI/dev_controls.gd
## Role: Self-contained dev panel; anchors below TopBar and handles visibility & persistence
extends MarginContainer

@export_node_path("Control") var top_bar_path: NodePath
@export var left_padding: int = 8
@export var top_padding: int = 8
@export var mirror_ignore_biomass: bool = true

@onready var _top_bar: Control = get_node_or_null(top_bar_path)
@onready var _ignore_biomass_cb: CheckBox = $DevControls/IgnoreBiomassLimit

## Set anchors and subscribe to TopBar/GameFlags; optionally mirror ignore_biomass_limit
func _ready() -> void:
	# Full-width at top; height grows to content. Use offsets for padding.
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = left_padding
	offset_right = 0
	_update_top_offset()

	if _top_bar:
		_top_bar.resized.connect(_update_top_offset)

	# Show/hide the whole panel when dev mode toggles
	if has_node("/root/GameFlags"):
		var gf: Node = get_node("/root/GameFlags")
		gf.dev_mode_changed.connect(_on_dev_mode_changed)
		_on_dev_mode_changed(gf.dev_mode_enabled)

		# Optional: persist Ignore Biomass in GameFlags
		if mirror_ignore_biomass and is_instance_valid(_ignore_biomass_cb):
			var persisted: Variant = gf.get("ignore_biomass_limit")
			if typeof(persisted) == TYPE_BOOL:
				_ignore_biomass_cb.button_pressed = bool(persisted)
			_ignore_biomass_cb.toggled.connect(func(pressed: bool) -> void:
				gf.set("ignore_biomass_limit", pressed))

## Place this panel below the TopBar using offsets, no manual position math
func _update_top_offset() -> void:
	var bar_height: int = 0
	if _top_bar:
		bar_height = int(_top_bar.size.y)
	offset_top = bar_height + top_padding
	offset_bottom = 0  # content defines height

## React to dev mode changes by showing or hiding the panel
func _on_dev_mode_changed(enabled: bool) -> void:
	visible = enabled

## end res://UI/dev_controls.gd
