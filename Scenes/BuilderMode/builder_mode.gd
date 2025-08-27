## builder_mode.gd
# Data-driven Builder: picks a brush from a registry, validates, then paints.

extends Node2D

# --- External registry (set this in the Inspector) ---
@export var brush_registry: BrushRegistry

# --- Coil map layer nodes ---
@export var base_layer: TileMapLayer
@export var walls_layer: TileMapLayer
@export var hazard_layer: TileMapLayer
@export var marker_layer: TileMapLayer

# --- Scene references ---
@onready var coil_map: TileMap = $CoilMap
@onready var palette_row: HBoxContainer = $UI/PaletteBar/PaletteRow
@onready var status_label: Label = $UI/PaletteBar/StatusLabel
@onready var start_with_flesh_cb: CheckBox = $UI/PaletteBar/PaletteRow/StartWithFlesh
@onready var clear_base_confirm: ConfirmationDialog = $UI/PaletteBar/ClearBaseConfirm
@onready var dev_badge: Label = $UI/PaletteBar/DevBadge

# Size of the prefill area for Flesh (adjust to your map size)
@export var start_flesh_rect: Rect2i = Rect2i(Vector2i(0, 0), Vector2i(24, 24))

# --- Current brush selection ---
var _current_index: int = 0

# --- UX: how long to keep a status message on screen ---
@export var status_timeout: float = 1.5
var _status_timer: float = 0.0

func _ready() -> void:
	# Basic sanity checks
	if brush_registry == null: push_error("❌ BrushRegistry not assigned on BuilderMode.")
	if coil_map == null: push_error("❌ CoilMap TileMap not found.")
	if base_layer == null: push_error("❌ base_layer not assigned on BuilderMode.")
	if walls_layer == null: push_error("❌ walls_layer not assigned on BuilderMode.")
	if hazard_layer == null: push_error("❌ hazard_layer not assigned on BuilderMode.")
	if marker_layer == null: push_error("❌ marker_layer not assigned on BuilderMode.")

	# Wire each palette button (by order) to a brush (by order).
	# Left to right buttons map to registry.brushes[0..N]

	var _palette_group := ButtonGroup.new()  # keep one group
	var i := 0
	for child in palette_row.get_children():
		print("child :", child)
		if child is TextureButton:
			child.toggle_mode = true
			child.button_group = _palette_group
			child.focus_mode = Control.FOCUS_NONE
			# Use size flags instead of the nonexistent `expand` property
			child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			child.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			child.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			
			var idx := i
			child.pressed.connect(func(): _select_brush(idx))
			# Set icon
			if brush_registry != null and idx < brush_registry.brushes.size():
				var be := brush_registry.brushes[idx]
				if be.icon:
					child.texture_normal = be.icon
				child.tooltip_text = be.display_name
			# Inactive look by default
			child.self_modulate = Color(0.7, 0.7, 0.7, 1.0)
			child.scale = Vector2.ONE
			i += 1
	
	# Default select the first brush, if any
	if brush_registry != null and brush_registry.brushes.size() > 0:
		_select_brush(0)
	
	# -- Start-with-Flesh: connect and apply once on load if ON
	if start_with_flesh_cb:
		start_with_flesh_cb.toggled.connect(_on_start_with_flesh_toggled)
		_apply_start_with_flesh(start_with_flesh_cb.button_pressed)
	# Confirmation dialog for smart clear
	if clear_base_confirm:
		clear_base_confirm.confirmed.connect(_on_clear_base_confirmed)
	# -- DEV MODE: react to global flag and initialize UI state
	if has_node("/root/GameFlags"):
		var gf = get_node("/root/GameFlags")
		gf.dev_mode_changed.connect(_on_dev_mode_changed)
		_on_dev_mode_changed(gf.dev_mode_enabled)

func _process(delta: float) -> void:
	# Clear transient status text after a delay
	if _status_timer > 0.0:
		_status_timer -= delta
		if _status_timer <= 0.0:
			status_label.text = ""

func _layer_for(index: int) -> TileMapLayer:
	match index:
		0: return base_layer
		1: return walls_layer
		2: return hazard_layer
		3: return marker_layer
		_: return null

func _unhandled_input(event: InputEvent) -> void:
	# We use _unhandled_input so UI button clicks don't also paint
	if event is InputEventMouseButton and event.pressed:
		var mouse_world: Vector2 = get_viewport().get_mouse_position()
		var mouse_local: Vector2 = base_layer.to_local(mouse_world)
		var coords: Vector2i = base_layer.local_to_map(mouse_local)
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			_paint_at(coords)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_erase_at(coords)

# --- Selection / Status -------------------------------------------------------
func _select_brush(index: int) -> void:
	if brush_registry == null or index < 0 or index >= brush_registry.brushes.size():
		_show_status("⚠️ No brush at index " + str(index))
		return
	_current_index = index
	
	var j := 0
	for child in palette_row.get_children():
		if child is TextureButton:
			var selected := (j == _current_index)
			child.button_pressed = selected
			# Visual feedback only (no new signals or groups)
			if selected:
				child.self_modulate = Color(1, 1, 1, 1)
				child.scale = Vector2(1.1, 1.1)
			else:
				child.self_modulate = Color(0.7, 0.7, 0.7, 1)
				child.scale = Vector2.ONE
			# Keep tooltip in sync (optional)
			if brush_registry and j < brush_registry.brushes.size():
				child.tooltip_text = brush_registry.brushes[j].display_name
		j += 1
	
	var b: BrushEntry = brush_registry.brushes[index]
	_show_status("Brush: " + (b.display_name if b.display_name != "" else "Unnamed"))

func _show_status(msg: String) -> void:
	status_label.text = msg
	_status_timer = status_timeout
	print(msg)

# --- Painting / Erasing -------------------------------------------------------
func _paint_at(coords: Vector2i) -> void:
	var b: BrushEntry = _current_brush()
	if b == null:
		_show_status("⚠️ No brush selected.")
		return
		
	# ERASER: just erase and return
	if b.rule_profile == "ERASER":
		_erase_at(coords)
		return
	
	# Validate according to rule profile (see functions below)
	if not _validate_placement(b, coords):
		return
	
	# Place the tile (BASE/WALL/POOL/MARKER)
	if b.source_id < 0:
		_show_status("⚠️ Source ID not set for brush: " + b.display_name)
		return
	
	var layer := _layer_for(b.target_layer)
	if layer == null:
		_show_status("⚠️ Unknown target layer: " + str(b.target_layer))
		return
	
	# Place the tile
	layer.set_cell(coords, b.source_id, b.atlas_coords)
	
	# If we just placed a marker, enforce singletons (Spawn and Heartroot)
	if layer == marker_layer:
		_enforce_single_spawn_at(coords)
		_enforce_single_heartroot_at(coords)

func _erase_at(coords: Vector2i) -> void:
	# Simple MVP: remove from all known layers at this cell
	for layer_node in [marker_layer, hazard_layer, walls_layer]:
		if layer_node:
			layer_node.erase_cell(coords)

# --- Validation helpers -------------------------------------------------------
func _current_brush() -> BrushEntry:
	if brush_registry == null:
		return null
	if _current_index < 0 or _current_index >= brush_registry.brushes.size():
		return null
	return brush_registry.brushes[_current_index]

func _has_base(coords: Vector2i) -> bool:
	return base_layer.get_cell_source_id(coords) != -1

func _has_wall(coords: Vector2i) -> bool:
	return walls_layer.get_cell_source_id(coords) != -1

func _hazard_kind_at(coords: Vector2i) -> String:
	var td: TileData = hazard_layer.get_cell_tile_data(coords)
	if td == null:
		return ""
	var v = td.get_custom_data("hazard")
	return String(v) if (v is String) else ""

func _validate_placement(b: BrushEntry, coords: Vector2i) -> bool:
	match b.rule_profile:
		"BASE":
			# Flesh is always allowed. (If you want to forbid overpainting, add checks here.)
			return true
		
		"WALL":
			# Rule A: Walls must sit on Flesh
			if not _has_base(coords):
				return _reject("Walls require Flesh beneath.")
			# Rule B: Walls cannot overlap an existing hazard
			if _hazard_kind_at(coords) != "":
				return _reject("Walls cannot overlap pools.")
			return true
		
		"POOL":
			# Rule A: Pools must sit on Flesh
			if not _has_base(coords):
				return _reject("Pools require Flesh beneath.")
			# Rule B: Pools cannot overlap walls (same cell)
			if _has_wall(coords):
				return _reject("Pools cannot overlap walls.")
			# Adjacency now allowed:
			# - Pools may be next to walls.
			# - Different pool kinds may touch.
			return true
		
		"MARKER":
			# Rule A: Markers require Flesh
			if not _has_base(coords):
				return _reject("Markers require Flesh beneath.")
			# Rule B: Must not be blocked or hazardous
			if _has_wall(coords) or _hazard_kind_at(coords) != "":
				return _reject("Markers can’t sit under walls or pools.")
			return true
		
		"ERASER":
			# Handled earlier; never reaches here.
			return true
		
		_:
			return _reject("Unknown rule profile: " + b.rule_profile)

# Ensures only one spawn marker exists on the Markers layer.
# If the tile we just placed at `coords` has custom_data is_spawn = true,
# erase all other cells in the Markers layer that also have is_spawn = true.
func _enforce_single_spawn_at(coords: Vector2i) -> void:
	# Read back the tile we just placed
	var td := marker_layer.get_cell_tile_data(coords)
	if td == null:
		return
	
	var is_spawn := bool(td.get_custom_data("is_spawn") or false)
	if not is_spawn:
		return  # We placed a non-spawn marker (e.g., Heartroot) — do nothing
		
	# Erase any other spawn markers elsewhere on the map
	for c in marker_layer.get_used_cells():
		if c == coords:
			continue
		var other_td := marker_layer.get_cell_tile_data(c)
		if other_td != null and bool(other_td.get_custom_data("is_spawn") or false):
			marker_layer.erase_cell(c)

# Ensures only one Heartroot exists on the Markers layer.
# If the tile at `coords` has custom_data is_goal = true,
# erase any other cells in the Markers layer that also have is_goal = true.
func _enforce_single_heartroot_at(coords: Vector2i) -> void:
	var td := marker_layer.get_cell_tile_data(coords)
	if td == null:
		return
	var is_goal := bool(td.get_custom_data("is_goal") or false)
	if not is_goal:
		return
	
	for c in marker_layer.get_used_cells():
		if c == coords:
			continue
		var other_td := marker_layer.get_cell_tile_data(c)
		if other_td != null and bool(other_td.get_custom_data("is_goal") or false):
			marker_layer.erase_cell(c)

# --- Start-with-Flesh ---------------------------------------------------------

# Called when the checkbox is toggled. We only *add* flesh; never auto-erase.
func _on_start_with_flesh_toggled(pressed: bool) -> void:
	if pressed:
		_apply_start_with_flesh(true)
	else:
		_prompt_clear_base()

# One-shot prefill of the base layer. Skips cells that already have something.
func _apply_start_with_flesh(enabled: bool) -> void:
	if not enabled:
		return
	if base_layer == null:
		push_error("Start-with-Flesh: base_layer not assigned.")
		return
	var flesh_brush := _find_default_flesh_brush()
	if flesh_brush == null:
		_show_status("⚠️ No BASE brush found in BrushRegistry.")
		return

	# Optional early-out: if base already has any tiles, don't blanket fill.
	if base_layer.get_used_cells().size() > 0:
		return

	var x0 := start_flesh_rect.position.x
	var y0 := start_flesh_rect.position.y
	var x1 := x0 + start_flesh_rect.size.x
	var y1 := y0 + start_flesh_rect.size.y

	for x in range(x0, x1):
		for y in range(y0, y1):
			var c := Vector2i(x, y)
			if base_layer.get_cell_source_id(c) == -1:
				base_layer.set_cell(c, flesh_brush.source_id, flesh_brush.atlas_coords)
	_show_status("Filled base with Flesh: %dx%d" % [start_flesh_rect.size.x, start_flesh_rect.size.y])

# Remove all cells from the Base/Flesh layer.
# Note: This only clears the base layer; walls/pools/markers remain as-is.
# --- Smart Clear (with confirmation) ------------------------------------------

# Show the confirmation dialog with live counts for the rect
func _prompt_clear_base() -> void:
	if clear_base_confirm == null:
		# Fallback: clear immediately if no dialog node
		_smart_clear_base_rect(start_flesh_rect)
		return

	var rect := start_flesh_rect
	var w := rect.size.x
	var h := rect.size.y

	var walls := _count_used_in_rect(walls_layer, rect)
	var pools := _count_used_in_rect(hazard_layer, rect)
	var marks := _count_used_in_rect(marker_layer, rect)
	var flesh := _count_used_in_rect(base_layer, rect)

	clear_base_confirm.title = "Clear Base (and dependent tiles)?"
	clear_base_confirm.dialog_text = "This will erase Flesh in a %dx%d area (%d cells) and remove:\n• %d wall tiles\n• %d pool tiles\n• %d markers\nProceed?" % [w, h, w*h, walls, pools, marks]
	clear_base_confirm.popup_centered()

# Called when the user clicks "OK" in the dialog
func _on_clear_base_confirmed() -> void:
	_smart_clear_base_rect(start_flesh_rect)
	_show_status("Cleared base and dependent tiles in %dx%d area." % [start_flesh_rect.size.x, start_flesh_rect.size.y])
	# Keep the checkbox unticked (it already is). No refill.

# Counts used cells for a given layer within rect
func _count_used_in_rect(layer: TileMapLayer, rect: Rect2i) -> int:
	if layer == null:
		return 0
	var count := 0
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := x0 + rect.size.x
	var y1 := y0 + rect.size.y
	for x in range(x0, x1):
		for y in range(y0, y1):
			if layer.get_cell_source_id(Vector2i(x, y)) != -1:
				count += 1
	return count

# Remove Flesh in the rect, and also remove any walls/pools/markers in that rect.
# "Smart" = only within the seeded rectangle; everything outside remains untouched.
func _smart_clear_base_rect(rect: Rect2i) -> void:
	if base_layer == null:
		return
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := x0 + rect.size.x
	var y1 := y0 + rect.size.y
	
	# First, remove dependent layers in the rect
	for x in range(x0, x1):
		for y in range(y0, y1):
			var c := Vector2i(x, y)
			if walls_layer and walls_layer.get_cell_source_id(c) != -1:
				walls_layer.erase_cell(c)
			if hazard_layer and hazard_layer.get_cell_source_id(c) != -1:
				hazard_layer.erase_cell(c)
			if marker_layer and marker_layer.get_cell_source_id(c) != -1:
				marker_layer.erase_cell(c)
	
	# Then remove base flesh in the rect
	for x in range(x0, x1):
		for y in range(y0, y1):
			var c := Vector2i(x, y)
			if base_layer.get_cell_source_id(c) != -1:
				base_layer.erase_cell(c)

# Helper: find a brush whose rule_profile is "BASE"
func _find_default_flesh_brush() -> BrushEntry:
	if brush_registry == null:
		return null
	for be in brush_registry.brushes:
		if be is BrushEntry and be.rule_profile == "BASE" and be.source_id >= 0:
			return be
	return null

# DEV MODE gate: show/hide dev-only UI and ping status
func _on_dev_mode_changed(enabled: bool) -> void:
	if start_with_flesh_cb:
		start_with_flesh_cb.visible = enabled
	if dev_badge:
		dev_badge.visible = enabled
	# Friendly ping so you always know the state
	_show_status("Dev Mode: " + ("ON" if enabled else "OFF"))

func _reject(msg: String) -> bool:
	_show_status("🚫 " + msg)
	return false

## end builder_mode.gd
