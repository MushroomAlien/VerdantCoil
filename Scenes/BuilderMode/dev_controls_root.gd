## res://UI/dev_controls.gd
## Role: Self-contained dev panel; anchors below TopBar and handles visibility & persistence
extends MarginContainer

@export_node_path("Control") var top_bar_path: NodePath
@export var left_padding: int = 8
@export var top_padding: int = 8
@export var right_padding: int = 8
@export var mirror_ignore_biomass: bool = true

@onready var _top_bar: Control = get_node_or_null(top_bar_path)
@onready var _ignore_biomass_cb: CheckBox = $DevControls/IgnoreBiomassLimit

### Set anchors and subscribe to TopBar/GameFlags; optionally mirror ignore_biomass_limit
#func _ready() -> void:
	## Full-width at top; height grows to content. Use offsets for padding.
	#anchor_left = 0.0
	#anchor_right = 1.0
	#anchor_top = 0.0
	#anchor_bottom = 0.0
	#offset_left = left_padding
	#offset_right = 0
	#_update_top_offset()
#
	#if _top_bar:
		#_top_bar.resized.connect(_update_top_offset)
#
	## Show/hide the whole panel when dev mode toggles
	#if has_node("/root/GameFlags"):
		#var gf: Node = get_node("/root/GameFlags")
		#gf.dev_mode_changed.connect(_on_dev_mode_changed)
		#_on_dev_mode_changed(gf.dev_mode_enabled)
#
		## Optional: persist Ignore Biomass in GameFlags
		#if mirror_ignore_biomass and is_instance_valid(_ignore_biomass_cb):
			#var persisted: Variant = gf.get("ignore_biomass_limit")
			#if typeof(persisted) == TYPE_BOOL:
				#_ignore_biomass_cb.button_pressed = bool(persisted)
			#_ignore_biomass_cb.toggled.connect(func(pressed: bool) -> void:
				#gf.set("ignore_biomass_limit", pressed))
## Anchor full width; height is content; place below TopBar in parent space
func _ready() -> void:
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = left_padding
	offset_right = right_padding
	_update_top_offset()

	if _top_bar:
		_top_bar.resized.connect(_update_top_offset)

	var parent_ctrl: Control = get_parent() as Control
	if parent_ctrl:
		parent_ctrl.resized.connect(_update_top_offset)

	if get_viewport():
		get_viewport().size_changed.connect(_update_top_offset)

	# Show/hide the whole panel when dev mode toggles
	if has_node("/root/GameFlags"):
		var gf: Node = get_node("/root/GameFlags")
		gf.dev_mode_changed.connect(_on_dev_mode_changed)
		_on_dev_mode_changed(gf.dev_mode_enabled)

		## Optional: persist Ignore Biomass in GameFlags
		#if mirror_ignore_biomass and is_instance_valid(_ignore_biomass_cb):
			#var persisted: Variant = gf.get("ignore_biomass_limit")
			#if typeof(persisted) == TYPE_BOOL:
				#_ignore_biomass_cb.button_pressed = bool(persisted)
			#_ignore_biomass_cb.toggled.connect(func(pressed: bool) -> void:
				#gf.set("ignore_biomass_limit", pressed))
		## Initialize and mirror Ignore Biomass Limit into GameFlags
		if mirror_ignore_biomass and is_instance_valid(_ignore_biomass_cb):
			var persisted_prop: Variant = gf.get("ignore_biomass_limit")
			var initial_value: bool = false
			if typeof(persisted_prop) == TYPE_BOOL:
				initial_value = bool(persisted_prop)
			elif gf.has_meta("ignore_biomass_limit"):
				initial_value = bool(gf.get_meta("ignore_biomass_limit"))
			_ignore_biomass_cb.button_pressed = initial_value

			_ignore_biomass_cb.toggled.connect(func(pressed: bool) -> void:
				## Write to property if present; also store as meta for safety
				if "ignore_biomass_limit" in gf:
					gf.set("ignore_biomass_limit", pressed)
				gf.set_meta("ignore_biomass_limit", pressed))

### Place this panel below the TopBar using offsets, no manual position math
#func _update_top_offset() -> void:
	#var bar_height: int = 0
	#if _top_bar:
		#bar_height = int(_top_bar.size.y)
	#offset_top = bar_height + top_padding
	#offset_bottom = 0  # content defines height
## Compute top offset from TopBar global rect converted to this node's parent space
func _update_top_offset() -> void:
	var parent_ctrl: Control = get_parent() as Control
	if parent_ctrl == null:
		offset_top = top_padding
		offset_bottom = 0
		return

	var bar_bottom_y: int = 0
	if _top_bar:
		var bar_rect: Rect2 = _top_bar.get_global_rect()
		bar_bottom_y = int(bar_rect.position.y + bar_rect.size.y)

	var parent_rect: Rect2 = parent_ctrl.get_global_rect()
	var local_y_under_bar: int = bar_bottom_y - int(parent_rect.position.y)

	offset_top = local_y_under_bar + top_padding
	offset_bottom = 0

## React to dev mode changes by showing or hiding the panel
func _on_dev_mode_changed(enabled: bool) -> void:
	visible = enabled

## end res://UI/dev_controls.gd
