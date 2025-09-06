## builder_mode.gd
## Role: UI wiring + brush selection + painting/erasing + preview + biomass label + playtest handoff.
## IO (save/load) is in CoilIO. Read-only tile queries are in CoilQuery. Validation + pathfinding are in CoilValidator.
## Validate button = strict (no bypass). Playtest = strict unless Dev Mode is ON and ignore_biomass_limit is set (GameFlags or the checkbox).
extends Node2D

## --- Constants / Modules --------------------------------------------------------

const CoilIO := preload("res://System/coil_io.gd")
const CoilQueryScript := preload("res://System/coil_query.gd")
@onready var _q: CoilQuery = CoilQueryScript.new()
const CoilValidatorScript: GDScript = preload("res://System/coil_validator.gd")

## --- Data classes --------------------------------------------------------

## Simple data class used by the UI to display validation results
class ValidationResult:
	var ok: bool = false
	var messages: Array[String] = []
	var spawn: Vector2i = Vector2i(-999999, -999999)
	var heart: Vector2i = Vector2i(-999999, -999999)

## --- Exports --------------------------------------------------------

@export var brush_registry: BrushRegistry
@export var preview_layer: TileMapLayer
@export var base_layer: TileMapLayer
@export var walls_layer: TileMapLayer
@export var hazard_layer: TileMapLayer
@export var marker_layer: TileMapLayer
@export_group("Save/Export")
@export var save_dir: String = "user://coils"
@export var start_flesh_rect: Rect2i = Rect2i(Vector2i(0, 0), Vector2i(24, 24)) # auto-fill area when Start With Flesh is ON
@export var biomass_cap: int = 100  # hard cap unless dev bypass is enabled

## --- Scene references --------------------------------------------------------

@onready var coil_map: TileMap = $CoilMap
@onready var palette_row: HBoxContainer = $UI/TopBar/PaletteRow
@onready var status_label: Label = $UI/TopBar/InfoRow/StatusLabel
@onready var biomass_label: Label = $UI/TopBar/InfoRow/BiomassLabel
@onready var start_with_flesh_cb: CheckBox = $UI/DevOverlay/DevControlsRoot/DevControls/StartWithFlesh
@onready var ignore_biomass_limit: CheckBox = $UI/DevOverlay/DevControlsRoot/DevControls/IgnoreBiomassLimit
@onready var clear_base_confirm: ConfirmationDialog = $UI/TopBar/ClearBaseConfirm
@onready var dev_badge: Label = $UI/DevOverlay/DevBadge
@onready var validate_dialog: AcceptDialog = $UI/TopBar/ValidateDialog
@onready var validate_body: RichTextLabel = $UI/TopBar/ValidateDialog/Body
@onready var validate_btn: Button = $UI/TopBar/PaletteRow/ValidateBtn
@onready var save_btn: Button = $UI/TopBar/PaletteRow/SaveBtn
@onready var playtest_btn: Button = $UI/TopBar/PaletteRow/PlaytestBtn
@onready var load_btn: Button = $UI/TopBar/PaletteRow/LoadBtn
@onready var load_dialog: FileDialog = $UI/TopBar/LoadDialog
@onready var publish_btn: Button = $UI/TopBar/PaletteRow/PublishBtn
@onready var validation_chip: Label = $UI/TopBar/InfoRow/ValidationChip

## --- State --------------------------------------------------------

var _current_index: int = 0
var _is_painting_left := false
var _is_erasing_right := false
var _last_preview_cell: Vector2i = Vector2i(999999, 999999)
var _palette_buttons: Array[TextureButton] = []
var _biomass_used: int = 0
var _last_validation_ok: bool = false

## --- UI wiring & Lifecycle --------------------------------------------------------

## Set up signals, palette buttons, dev overlay, and initial state
func _ready() -> void:
	# Basic sanity checks
	if brush_registry == null: push_error("❌ BrushRegistry not assigned on BuilderMode.")
	if coil_map == null: push_error("❌ CoilMap TileMap not found.")
	if base_layer == null: push_error("❌ base_layer not assigned on BuilderMode.")
	if walls_layer == null: push_error("❌ walls_layer not assigned on BuilderMode.")
	if hazard_layer == null: push_error("❌ hazard_layer not assigned on BuilderMode.")
	if marker_layer == null: push_error("❌ marker_layer not assigned on BuilderMode.")
	if validate_btn:
		validate_btn.pressed.connect(_on_validate_pressed)
	if save_btn:
		save_btn.pressed.connect(_on_save_pressed)
	if playtest_btn:
		playtest_btn.pressed.connect(_on_playtest_pressed)
	if load_btn:
		load_btn.pressed.connect(_on_load_pressed)
	if publish_btn:
		publish_btn.pressed.connect(_on_publish_pressed)
	if load_dialog:
		load_dialog.file_selected.connect(_on_load_file_selected)
	
	# Wire each palette button (by order) to a brush (by order).
	# Left to right buttons map to registry.brushes[0..N]
	var _palette_group := ButtonGroup.new()
	_palette_buttons.clear()
	for child in palette_row.get_children():
		if child is TextureButton:
			_palette_buttons.append(child)
			var idx := _palette_buttons.size() - 1  # index among buttons only
			
			child.toggle_mode = true
			child.button_group = _palette_group
			child.focus_mode = Control.FOCUS_NONE
			child.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			child.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
			child.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			
			child.pressed.connect(func(): _select_brush(idx))
			
			# Set icon + tooltip from the registry
			if brush_registry != null and idx < brush_registry.brushes.size():
				var be := brush_registry.brushes[idx]
				if be.icon:
					child.texture_normal = be.icon
				child.tooltip_text = be.display_name
			
			# Default inactive look
			child.self_modulate = Color(0.7, 0.7, 0.7, 1.0)
			child.scale = Vector2.ONE
	
	# --- Default select the first brush, if any ---
	if brush_registry != null and brush_registry.brushes.size() > 0:
		_select_brush(0)
	
	# --- Start-with-Flesh: connect and apply once on load if ON ---
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
	
	# --- Ignore Biomass Limit: connect and apply once on load if ON ---
	if ignore_biomass_limit:
		ignore_biomass_limit.tooltip_text = "Dev only: bypass biomass cap when Playtesting."
	
	# ---- restore coil if returning from Playtest ----
	_restore_pending_coil_if_any()
	
	# keep numbers fresh after applying
	_recalc_biomass()
	
	# --- Initial strict validation -> set Draft/Valid chip & Publish enable ---
	_refresh_validation_state()


## Refresh the preview each frame
func _process(_delta: float) -> void:
	_update_preview()

## Handle mouse input for painting and erasing
func _unhandled_input(event: InputEvent) -> void:
	# Mouse BUTTONS ------------------------------------------------------------
	if event is InputEventMouseButton:
		# Toggle state flags on press/release (no coords needed for releases).
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_is_painting_left = event.pressed
				if event.pressed:
					_paint_at(_cell_under_mouse())  # compute coords only when used
			MOUSE_BUTTON_RIGHT:
				_is_erasing_right = event.pressed
				if event.pressed:
					_erase_at(_cell_under_mouse())  # compute coords only when used
		return  # done
	
	# Mouse MOTION -------------------------------------------------------------
	if event is InputEventMouseMotion:
		# Only do the (relatively) expensive cell lookup if we’re actually drawing.
		if _is_painting_left or _is_erasing_right:
			var coords := _cell_under_mouse()
			if _is_painting_left:
				_paint_at(coords)
			elif _is_erasing_right:
				_erase_at(coords)

## Toggle visibility for dev-only badge
func _on_dev_mode_changed(enabled: bool) -> void:
	if dev_badge:
		dev_badge.visible = enabled
	_show_status("Dev Mode: " + ("ON" if enabled else "OFF"))

## --- Selection --------------------------------------------------------

## Update the current brush and palette button visuals
func _select_brush(index: int) -> void:
	if brush_registry == null or index < 0 or index >= brush_registry.brushes.size():
		_show_status("⚠️ No brush at index " + str(index))
		return
	_current_index = index
	
	for i in range(_palette_buttons.size()):
		var btn := _palette_buttons[i]
		var selected := (i == _current_index)
		btn.button_pressed = selected
		if selected:
			btn.self_modulate = Color(1, 1, 1, 1)
			btn.scale = Vector2(1.1, 1.1)
		else:
			btn.self_modulate = Color(0.7, 0.7, 0.7, 1)
			btn.scale = Vector2.ONE
	
		if brush_registry and i < brush_registry.brushes.size():
			btn.tooltip_text = brush_registry.brushes[i].display_name
	
	var b: BrushEntry = brush_registry.brushes[index]
	_show_status("Brush: " + (b.display_name if b.display_name != "" else "Unnamed"))

## Return the current BrushEntry or null
func _current_brush() -> BrushEntry:
	if brush_registry == null:
		return null
	if _current_index < 0 or _current_index >= brush_registry.brushes.size():
		return null
	return brush_registry.brushes[_current_index]

## --- Painting / Erasing --------------------------------------------------------

## Place a tile using the selected brush after validation
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
	
	# Recalc biomass after successful placement
	_recalc_biomass()

## Remove tiles at the cell across relevant layers
func _erase_at(coords: Vector2i) -> void:
	# Simple MVP: remove from all known layers at this cell
	for layer_node in [marker_layer, hazard_layer, walls_layer]:
		if layer_node:
			layer_node.erase_cell(coords)
			
	# Recalc biomass after successful placement
	_recalc_biomass()

## Report an invalid action when requested and return false
func _reject_or_false(msg: String, report: bool) -> bool:
	if report:
		_show_status("🚫 " + msg)
		#return _reject(msg)  # prints + shakes/beeps (if you wired SFX)
	return false

## Ensure only one spawn marker exists in the markers layer
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

## Ensure only one Heartroot marker exists in the markers layer
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

## --- Preview --------------------------------------------------------

## Draw a ghost tile at the mouse cell and tint by validity
func _update_preview() -> void:
	# Clear the previous preview cell
	if preview_layer and _last_preview_cell.x < 900000:
		preview_layer.erase_cell(_last_preview_cell)
	
	# Compute current mouse cell
	var coords := _cell_under_mouse()
	_last_preview_cell = coords
	
	var b := _current_brush()
	if b == null or b.rule_profile == "ERASER":
		return
	
	# Always place the ghost tile
	if preview_layer and b.source_id >= 0:
		preview_layer.set_cell(coords, b.source_id, b.atlas_coords)
		# Now tint based on validity
		var ok := _validate_placement(b, coords, false)
		var col := Color(1, 1, 1, 0.5)
		if not ok:
			col = Color(1, 0.2, 0.2, 0.5)
		preview_layer.modulate = col

## Convert the global mouse position to a base-layer cell
func _cell_under_mouse() -> Vector2i:
	# Convert current global mouse position to a TileMap cell once.
	var mouse_world: Vector2 = get_global_mouse_position()
	var mouse_local: Vector2 = base_layer.to_local(mouse_world)
	return base_layer.local_to_map(mouse_local)

## Map a brush target index to its TileMapLayer
func _layer_for(index: int) -> TileMapLayer:
	match index:
		0: return base_layer
		1: return walls_layer
		2: return hazard_layer
		3: return marker_layer
		_: return null

## Apply placement rules using CoilQuery lookups
func _validate_placement(b: BrushEntry, coords: Vector2i, report := true) -> bool:
	match b.rule_profile:
		"BASE":
			# Flesh is always allowed. (If you want to forbid overpainting, add checks here.)
			return true
		
		"WALL":
			# Rule A: Walls must sit on Flesh
			if not _q.has_base(base_layer, coords):
				return _reject_or_false("Walls require Flesh beneath.", report)
			# Rule B: Walls cannot overlap an existing hazard
			if _q.get_hazard_kind(hazard_layer, coords) != "":
				return _reject_or_false("Walls cannot overlap pools.", report)
			return true
		
		"POOL":
			# Rule A: Pools must sit on Flesh
			if not _q.has_base(base_layer, coords):
				return _reject_or_false("Pools require Flesh beneath.", report)
			# Rule B: Pools cannot overlap walls (same cell)
			if _q.has_wall(walls_layer, coords):
				return _reject_or_false("Pools cannot overlap walls.", report)
			return true
		
		"MARKER":
			# Rule A: Markers require Flesh
			if not _q.has_base(base_layer, coords):
				return _reject_or_false("Markers require Flesh beneath.", report)
			# Rule B: Must not be blocked or hazardous
			if _q.has_wall(walls_layer, coords) or _q.get_hazard_kind(hazard_layer, coords) != "":
				return _reject_or_false("Markers can’t sit under walls or pools.", report)
			return true
		
		"ERASER":
			# Handled earlier; never reaches here.
			return true
		_:
			#return _reject("Unknown rule profile: " + b.rule_profile)
			return _reject_or_false("Unknown rule profile: " + b.rule_profile, report)

## --- Biomass label --------------------------------------------------------

## Read the 'cost' custom data for a cell, or zero when missing
func _tile_cost(layer: TileMapLayer, coords: Vector2i) -> int:
	if layer == null:
		return 0
	var td: TileData = layer.get_cell_tile_data(coords)
	if td == null:
		return 0
	var v = td.get_custom_data("cost")
	return int(v) if (v is int) else 0

## Recompute the biomass total across all layers
func _recalc_biomass() -> void:
	var total := 0
	for layer_node in [base_layer, walls_layer, hazard_layer, marker_layer]:
		if layer_node:
			for c in layer_node.get_used_cells():
				total += _tile_cost(layer_node, c)
	_biomass_used = total
	_update_biomass_label()

## Update the biomass label and its warning color
func _update_biomass_label() -> void:
	if biomass_label == null:
		return
	
	biomass_label.text = "Biomass: %d / %d" % [_biomass_used, biomass_cap]
	var col := Color(1, 1, 1)
	if _biomass_used > biomass_cap:
		col = Color(1, 0.25, 0.25)
	biomass_label.modulate = col

## --- Start-with-Flesh and Smart Clear --------------------------------------------------------

## Toggle prefill mode and prompt clear when turning off
func _on_start_with_flesh_toggled(pressed: bool) -> void:
	if pressed:
		_apply_start_with_flesh(true)
	else:
		_prompt_clear_base()

## Prefill the base layer with Flesh within the configured rectangle
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

## Show a confirmation dialog for clearing Flesh and dependents
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
	#var flesh := _count_used_in_rect(base_layer, rect)
	clear_base_confirm.title = "Clear Base (and dependent tiles)?"
	clear_base_confirm.dialog_text = "This will erase Flesh in a %dx%d area (%d cells) and remove:\n• %d wall tiles\n• %d pool tiles\n• %d markers\nProceed?" % [w, h, w*h, walls, pools, marks]
	clear_base_confirm.popup_centered()

## Clear Flesh and dependent tiles after confirmation
func _on_clear_base_confirmed() -> void:
	_smart_clear_base_rect(start_flesh_rect)
	_show_status("Cleared base and dependent tiles in %dx%d area." % [start_flesh_rect.size.x, start_flesh_rect.size.y])
	# Keep the checkbox unticked (it already is). No refill.

## Count used cells in a layer within a rectangle
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

## Clear Flesh and dependent layers within a rectangle
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

## --- Save / Load UI Handlers --------------------------------------------------------

### Save the current coil to a JSON file in the user directory
#func _on_save_pressed() -> void:
	## Keep numbers fresh in the save
	#_recalc_biomass()
	## Ensure directory exists
	#if DirAccess.open(save_dir) == null:
		#var ok := DirAccess.make_dir_recursive_absolute(save_dir)
		#if ok != OK:
			#_show_status("Save failed: couldn't create " + save_dir)
			#return
	## Build a timestamped filename
	#var ts := Time.get_datetime_string_from_system(false, true).replace(":", "-")
	#var path := "%s/coil_%s.json" % [save_dir, ts]
	## Write JSON
	#var data := _capture_coil()
	#var f := FileAccess.open(path, FileAccess.WRITE)
	#if f == null:
		#_show_status("Save failed (" + str(FileAccess.get_open_error()) + ").")
		#return
	#f.store_string(JSON.stringify(data, "\t"))
	#f.close()
	#_show_status("Saved: " + path)

## Save the current coil to a JSON file in the user directory
func _on_save_pressed() -> void:
	# Keep numbers fresh in the save
	_recalc_biomass()
	
	# Ensure directory exists
	if DirAccess.open(save_dir) == null:
		#var ok := DirAccess.make_dir_recursive_absolute(save_dir)
		#if ok != OK:
			#_show_status("Save failed: couldn't create " + save_dir)
			#return
		var err: int = DirAccess.make_dir_recursive_absolute(save_dir)
		if err != OK:
			_show_status("Save failed: couldn't create " + save_dir)
			return
	
	# Build a timestamped filename
	var ts := Time.get_datetime_string_from_system(false, true).replace(":", "-")
	var path := "%s/coil_%s.json" % [save_dir, ts]
	# Write JSON
	var data := _capture_coil()  # CHANGED: _capture_coil now includes validation snapshot
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_show_status("Save failed (" + str(FileAccess.get_open_error()) + ").")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	_show_status("Saved: " + path)

	# NEW: Update the chip & Publish button from the just-saved validation result
	if data.has("meta") and (data["meta"] as Dictionary).has("validated"):
		var ok_now := bool((data["meta"] as Dictionary)["validated"])
		_update_validation_chip(ok_now)

## Open a file dialog to choose a coil to load
func _on_load_pressed() -> void:
	# Ensure save_dir exists (e.g., "user://coils")
	if DirAccess.open(save_dir) == null:
		DirAccess.make_dir_recursive_absolute(save_dir)
	if load_dialog:
		load_dialog.access = FileDialog.ACCESS_USERDATA
		load_dialog.current_dir = save_dir        # e.g., "user://coils"
		# Optional: enforce filter programmatically too
		# load_dialog.filters = PackedStringArray(["*.json"])
		load_dialog.popup_centered()

### Load a selected coil JSON and apply it to layers
#func _on_load_file_selected(path: String) -> void:
	#var f := FileAccess.open(path, FileAccess.READ)
	#if f == null:
		#_show_status("Load failed (" + str(FileAccess.get_open_error()) + ").")
		#return
	#var txt: String = f.get_as_text()
	#f.close()
	#var parsed_v: Variant = JSON.parse_string(txt)
	#if typeof(parsed_v) != TYPE_DICTIONARY:
		#_show_status("Load failed: JSON malformed.")
		#return
	#var data: Dictionary = parsed_v as Dictionary
	#CoilIO.apply_coil(data, base_layer, walls_layer, hazard_layer, marker_layer)
	#_recalc_biomass()
	#_show_status("Loaded: " + path)
## Load a selected coil JSON and apply it to layers
func _on_load_file_selected(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_show_status("Load failed (" + str(FileAccess.get_open_error()) + ").")
		return
	var txt: String = f.get_as_text()
	f.close()
	var parsed_v: Variant = JSON.parse_string(txt)
	if typeof(parsed_v) != TYPE_DICTIONARY:
		_show_status("Load failed: JSON malformed.")
		return
	var data: Dictionary = parsed_v as Dictionary
	CoilIO.apply_coil(data, base_layer, walls_layer, hazard_layer, marker_layer)
	_recalc_biomass()
	_show_status("Loaded: " + path)

	# NEW: Immediately run strict validation in memory and refresh the chip
	_refresh_validation_state()  # don't touch disk; just reflect truth in UI

## Autosave a snapshot before starting playtest
func _autosave_playtest() -> void:
	if DirAccess.open(save_dir) == null:
		DirAccess.make_dir_recursive_absolute(save_dir)
	var path := "%s/_autosave_playtest.json" % [save_dir]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_capture_coil(), "\t"))
		f.close()
		_show_status("Autosaved: " + path)

### Build a Dictionary snapshot of the current coil
#func _capture_coil() -> Dictionary:
	#var tileset_path: String = ""
	#if coil_map.tile_set:
		#tileset_path = coil_map.tile_set.resource_path
	#return {
		#"meta": {
			#"biomass_cap": biomass_cap,
			#"biomass_used": _biomass_used,
			#"tileset": tileset_path
		#},
		#"layers": {
			#"base": CoilIO.serialize_layer(base_layer),
			#"walls": CoilIO.serialize_layer(walls_layer),
			#"hazard": CoilIO.serialize_layer(hazard_layer),
			#"marker": CoilIO.serialize_layer(marker_layer)
		#}
	#}
### --- Save current coil as Dictionary snapshot (with validation flag) ---
#func _capture_coil() -> Dictionary:
	#var tileset_path: String = ""
	#if coil_map.tile_set:
		#tileset_path = coil_map.tile_set.resource_path
	#
	## --- NEW: run a strict validation here just to tag the save ---
	#var validation_result: ValidationResult = _run_validation(false)  # false = no biomass bypass
	#var is_valid: bool = validation_result.ok
	#
	#return {
		#"meta": {
			#"biomass_cap": biomass_cap,
			#"biomass_used": _biomass_used,
			#"tileset": tileset_path,
			#"validated": is_valid   # <-- NEW FIELD
		#},
		#"layers": {
			#"base":   CoilIO.serialize_layer(base_layer),
			#"walls":  CoilIO.serialize_layer(walls_layer),
			#"hazard": CoilIO.serialize_layer(hazard_layer),
			#"marker": CoilIO.serialize_layer(marker_layer)
		#}
	#}
## --- Save current coil as Dictionary snapshot (with validation flag & details) ---
func _capture_coil() -> Dictionary:
	var tileset_path: String = ""
	if coil_map.tile_set:
		tileset_path = coil_map.tile_set.resource_path
	
	# Strict validation snapshot (no biomass bypass)
	var validation_result: ValidationResult = _run_validation(false)
	_last_validation_ok = validation_result.ok  # cache for UI
	
	# Convert optional coords to small dicts only if set
	var spawn_dict := {}
	if validation_result.spawn.x > -900000:
		spawn_dict = {"x": validation_result.spawn.x, "y": validation_result.spawn.y}
	var heart_dict := {}
	if validation_result.heart.x > -900000:
		heart_dict = {"x": validation_result.heart.x, "y": validation_result.heart.y}
	
	var validation_payload := {
		"ok": validation_result.ok,
		"messages": validation_result.messages,
		"spawn": spawn_dict,
		"heart": heart_dict,
		"biomass_used": _biomass_used,
		"biomass_cap": biomass_cap,
		"validator_version": "1",
		"timestamp": _iso_timestamp()
	}
	
	return {
		"meta": {
			"biomass_cap": biomass_cap,
			"biomass_used": _biomass_used,
			"tileset": tileset_path,
			"validated": validation_result.ok,   # NEW
			"validation": validation_payload     # NEW
		},
		"layers": {
			"base":   CoilIO.serialize_layer(base_layer),
			"walls":  CoilIO.serialize_layer(walls_layer),
			"hazard": CoilIO.serialize_layer(hazard_layer),
			"marker": CoilIO.serialize_layer(marker_layer)
		}
	}

## Restore and clear any pending coil handed back from Playtest
func _restore_pending_coil_if_any() -> void:
	if not has_node("/root/CoilSession"):
		return
	
	var cs: Node = get_node("/root/CoilSession")
	var data: Dictionary = {}
	
	# Preferred: use consume_pending_coil() if present
	if cs.has_method("consume_pending_coil"):
		var data_v: Variant = cs.call("consume_pending_coil")
		if typeof(data_v) == TYPE_DICTIONARY:
			data = data_v as Dictionary
	else:
		# Fallback to the raw property once, then clear it
		var pc_v: Variant = cs.get("pending_coil")
		if typeof(pc_v) == TYPE_DICTIONARY:
			data = pc_v as Dictionary
			cs.set("pending_coil", {})
	
	if data.has("layers"):
		CoilIO.apply_coil(data, base_layer, walls_layer, hazard_layer, marker_layer)
		_recalc_biomass()
		_show_status("Restored coil from Playtest.")
		print("BuilderMode: restored coil snapshot from CoilSession.")

## --- Validation & Playtest Handoff --------------------------------------------------------

## Validate popup is always strict; no dev bypass here.
func _on_validate_pressed() -> void:
	# Run a full check list and show a friendly popup
	_recalc_biomass()
	var result := _run_validation(false) # always strict on Validate
	_show_validation_dialog(result)

## Delegate to CoilValidator and adapt its result for the UI
func _run_validation(ignore_biomass: bool = false) -> ValidationResult:
	var out := ValidationResult.new()
	
	var result: Dictionary = CoilValidatorScript.validate(
		base_layer,
		walls_layer,
		hazard_layer,
		marker_layer,
		_biomass_used,
		biomass_cap,
		ignore_biomass
	)
	
	var ok_flag := false
	if result.has("ok"):
		ok_flag = bool(result["ok"])
	out.ok = ok_flag
	
	out.messages = []
	if result.has("messages") and result["messages"] is Array:
		for m in result["messages"]:
			out.messages.append(String(m))
	
	if result.has("spawn") and result["spawn"] is Vector2i:
		out.spawn = result["spawn"]
	if result.has("heart") and result["heart"] is Vector2i:
		out.heart = result["heart"]
	
	if out.ok and out.messages.is_empty():
		out.messages.append("✅ Valid coil. Ready to Playtest or Save.")
	
	return out

## Populate and show the validation dialog
func _show_validation_dialog(r: ValidationResult) -> void:
	if validate_dialog == null or validate_body == null:
		_show_status("Validation dialog missing in scene.")
		return
	
	# Force a readable size & wrapping on open
	validate_dialog.min_size = Vector2i(560, 360)     # floor
	validate_dialog.size = Vector2i(640, 420)         # actual open size
	validate_body.autowrap_mode = TextServer.AUTOWRAP_WORD
	validate_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	validate_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	validate_body.clear()
	validate_body.append_text("")  # ensures we start fresh
	
	if r.ok:
		validate_dialog.title = "Validation Passed"
	else:
		validate_dialog.title = "Validation Issues"
	# Build the message list
	for m in r.messages:
		validate_body.append_text(m + "\n")
	# Extra friendly coords if available
	if r.spawn.x > -900000:
		validate_body.append_text("• Spawn at %s\n" % [str(r.spawn)])
	if r.heart.x > -900000:
		validate_body.append_text("• Heartroot at %s\n" % [str(r.heart)])
	validate_dialog.popup_centered() # uses 'size' above

## Playtest is strict unless Dev Mode is ON and ignore_biomass_limit is true (GameFlags/meta/checkbox).
func _on_playtest_pressed() -> void:
	# Validate first
	
	_recalc_biomass()
	## Validate, then decide if biomass cap can be bypassed in dev
	var allow_over: bool = false
	if has_node("/root/GameFlags"):
		var gf: Node = get_node("/root/GameFlags")

		var bypass: bool = false
		if gf.has_meta("ignore_biomass_limit"):
			bypass = bool(gf.get_meta("ignore_biomass_limit"))
		elif ignore_biomass_limit:
			bypass = ignore_biomass_limit.button_pressed
		
		if bool(gf.dev_mode_enabled) and bypass:
			allow_over = true
	
	if allow_over and _biomass_used > biomass_cap:
		_show_status("Dev bypass: biomass over cap (%d/%d), playtesting anyway." % [_biomass_used, biomass_cap])
	
	print("BuilderMode: start_playtest request → biomass ", _biomass_used, "/", biomass_cap, ", allow_over=", allow_over)
	var result := _run_validation(allow_over)
	if not result.ok:
		_show_validation_dialog(result)
		return
	
	# Optional but handy: autosave a snapshot
	_autosave_playtest()
	
	# Hand off to Explore via CoilSession
	var data: Dictionary = _capture_coil()
	if has_node("/root/CoilSession"):
		get_node("/root/CoilSession").call("start_playtest", data)
	else:
		_show_status("Playtest: CoilSession autoload missing.")

## --- Utility Helpers --------------------------------------------------------

## Update the status label and print to the console
func _show_status(msg: String) -> void:
	status_label.text = msg
	print(msg)

## Find the default Flesh brush with rule_profile BASE
func _find_default_flesh_brush() -> BrushEntry:
	if brush_registry == null:
		return null
	for be in brush_registry.brushes:
		if be is BrushEntry and be.rule_profile == "BASE" and be.source_id >= 0:
			return be
	return null

#func _on_publish_btn_pressed() -> void:
	#pass # Replace with function body.
## Publish is ALWAYS strict. No dev bypass. Writes to user://Published/ and updates manifest.
func _on_publish_pressed() -> void:
	_recalc_biomass()
	var result := _run_validation(false)  # false => no biomass bypass (STRICT)
	if not result.ok:
		_show_validation_dialog(result)  # Friendly popup you already have
		return
	
	# Ensure Published/ exists (sibling to save_dir)
	var pub_dir := "user://Published"
	_ensure_dir(pub_dir)
	
	# Timestamped publish path
	var ts := Time.get_datetime_string_from_system(false, true).replace(":", "-")
	var pub_path := "%s/coil_%s.json" % [pub_dir, ts]
	
	# Capture a fresh, validated snapshot (includes validated flag + details)
	var data := _capture_coil()
	
	var f := FileAccess.open(pub_path, FileAccess.WRITE)
	if f == null:
		_show_status("Publish failed (" + str(FileAccess.get_open_error()) + ").")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	
	# Update/append manifest entry
	_update_publish_manifest(pub_dir, pub_path, data)
	
	_show_status("Published to Local: " + pub_path)
	
	# Sync chip state (should be valid at this point)
	_update_validation_chip(true)

## Strictly recompute validation and refresh Draft/Valid chip & Publish enable
func _refresh_validation_state() -> void:
	var r := _run_validation(false)  # strict
	_last_validation_ok = r.ok
	_update_validation_chip(_last_validation_ok)

## Small UI updater for the ValidationChip and Publish button
func _update_validation_chip(is_ok: bool) -> void:
	if validation_chip:
		if is_ok:
			validation_chip.text = "Valid"
			validation_chip.modulate = Color(0.75, 1.0, 0.75)  # soft green
		else:
			validation_chip.text = "Draft"
			validation_chip.modulate = Color(1.0, 0.75, 0.75)  # soft red

	# Enable/disable Publish affordance (belt & braces: we still re-check inside publish)
	if publish_btn:
		publish_btn.disabled = not is_ok

## Ensure a directory exists (recursive)
#func _ensure_dir(dir_path: String) -> void:
	#if DirAccess.open(dir_path) == null:
		#var ok := DirAccess.make_dir_recursive_absolute(dir_path)
		#if ok != OK:
			#_show_status("Failed to create: " + dir_path)
func _ensure_dir(dir_path: String) -> void:
	if DirAccess.open(dir_path) == null:
		var err: int = DirAccess.make_dir_recursive_absolute(dir_path)  # typed int (Error enum)
		if err != OK:
			_show_status("Failed to create: " + dir_path)

### Append/update publish manifest with a single entry
#func _update_publish_manifest(pub_dir: String, pub_path: String, data: Dictionary) -> void:
	#var manifest_path := pub_dir + "/manifest.json"
	#var manifest: Dictionary = {"version": 1, "items": []}
#
	## Load existing manifest if present
	#if FileAccess.file_exists(manifest_path):
		#var f_in := FileAccess.open(manifest_path, FileAccess.READ)
		#if f_in:
			#var txt := f_in.get_as_text()
			#f_in.close()
			#var parsed := JSON.parse_string(txt)
			#if typeof(parsed) == TYPE_DICTIONARY:
				#manifest = parsed
#
	## Build new/updated entry
	#var meta := data.get("meta", {}) as Dictionary
	#var entry := {
		#"path": pub_path,
		#"title": "Untitled",  # placeholder; later you can add a Title field in UI/meta
		#"published_at": _iso_timestamp(),
		#"biomass_used": meta.get("biomass_used", _biomass_used),
		#"biomass_cap": meta.get("biomass_cap", biomass_cap)
	#}
#
	## Upsert by path
	#var items := manifest.get("items", []) as Array
	#var replaced := false
	#for i in range(items.size()):
		#var it := items[i] as Dictionary
		#if (it.get("path", "") as String) == pub_path:
			#items[i] = entry
			#replaced = true
			#break
	#if not replaced:
		#items.append(entry)
	#manifest["items"] = items
#
	## Write manifest back
	#var f_out := FileAccess.open(manifest_path, FileAccess.WRITE)
	#if f_out:
		#f_out.store_string(JSON.stringify(manifest, "\t"))
		#f_out.close()
## Append/update publish manifest with a single entry (STRICT TYPING)
func _update_publish_manifest(pub_dir: String, pub_path: String, data: Dictionary) -> void:
	var manifest_path: String = pub_dir + "/manifest.json"
	
	# Start with a default manifest object
	var manifest: Dictionary = {
		"version": 1,
		"items": []  # Array of Dictionary entries
	}
	
	# If a manifest already exists, read and parse it
	if FileAccess.file_exists(manifest_path):
		var f_in: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
		if f_in != null:
			var txt: String = f_in.get_as_text()
			f_in.close()
			
			# IMPORTANT: parse result is Variant → store in a Variant first
			var parsed_v: Variant = JSON.parse_string(txt)
			if typeof(parsed_v) == TYPE_DICTIONARY:
				# Safe cast AFTER typeof check to satisfy typing
				manifest = parsed_v as Dictionary
	
	# Pull meta from the just-published coil data (also Variant-safe)
	var meta: Dictionary = {}
	var meta_v: Variant = data.get("meta", {})
	if typeof(meta_v) == TYPE_DICTIONARY:
		meta = meta_v as Dictionary
	
	# Build the manifest entry (use explicit ints/strings for strict typing)
	var entry: Dictionary = {
		"path": pub_path,
		"title": "Untitled",  # TODO: wire a title field later
		"published_at": _iso_timestamp(),
		"biomass_used": int(meta.get("biomass_used", _biomass_used)),
		"biomass_cap": int(meta.get("biomass_cap", biomass_cap))
	}
	
	# Get current items as a typed Array (via Variant)
	var items: Array = []
	var items_v: Variant = manifest.get("items", [])
	if typeof(items_v) == TYPE_ARRAY:
		items = items_v as Array
	# Upsert by matching "path"
	var replaced: bool = false
	for i in range(items.size()):
		var it_v: Variant = items[i]
		if typeof(it_v) == TYPE_DICTIONARY:
			var it: Dictionary = it_v as Dictionary
			var path_field_v: Variant = it.get("path", "")
			var path_field: String = path_field_v as String
			if path_field == pub_path:
				items[i] = entry
				replaced = true
				break
	
	if not replaced:
		items.append(entry)
	
	manifest["items"] = items
	
	# Write back to disk
	var f_out: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	if f_out != null:
		f_out.store_string(JSON.stringify(manifest, "\t"))
		f_out.close()

## ISO8601-like timestamp for metadata
func _iso_timestamp() -> String:
	return Time.get_datetime_string_from_system(true, true)  # UTC, with separators

## end builder_mode.gd
