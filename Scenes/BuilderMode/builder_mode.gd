## builder_mode.gd — Godot 4.4.1
## Responsibility: UI wiring (palette, dialogs, dev overlay), brush selection, paint/erase, live preview tinting,
## biomass counter, strict validation popup, playtest handoff, save/load/publish, and profile menu.
## Ownership boundaries:
##   • IO:        System/coil_io.gd
##   • Queries:   System/coil_query.gd
##   • Validate:  System/coil_validator.gd  (strict; playtest may bypass biomass if DevMode + flag)
## Strictness rules:
##   • Validate button: always strict (no bypass)
##   • Playtest: strict unless Dev Mode is ON and 'ignore_biomass_limit' is true (GameFlags meta or checkbox)
##   • Publish: ALWAYS strict
## External expectations:
##   • Autoloads: /root/GameFlags (dev flags), /root/CoilSession (playtest handoff), /root/ProfileManager (optional)
##   • Tile layers: Base, Walls, Hazard, Marker must be assigned via Inspector
extends Node2D

## --- Constants / Modules --------------------------------------------------------

const CoilIO := preload("res://System/coil_io.gd")
const CoilQueryScript := preload("res://System/coil_query.gd")
const CoilValidatorScript: GDScript = preload("res://System/coil_validator.gd")
const DIR_COILS: String = "user://coils"
const DIR_PUBLISHED: String = "user://Published"
const EXT_JSON: String = ".json"
const F_COIL_PREFIX: String = "coil_"
const PUBLISHED_MANIFEST: String = DIR_PUBLISHED + "/manifest.json"
const MENU_MANAGE_ID: int = 9999
const MANIFEST_VERSION: int = 1
const COIL_SCHEMA_VERSION: int = 1

## --- Data classes --------------------------------------------------------

## Simple data class used by the UI to display validation results
class ValidationResult:
	var ok: bool = false
	var messages: Array[String] = []
	var spawn: Vector2i = Vector2i(-999999, -999999)
	var heart: Vector2i = Vector2i(-999999, -999999)

## --- Exports --------------------------------------------------------

@export_group("Registry & Layers")
@export var brush_registry: BrushRegistry
@export var preview_layer: TileMapLayer
@export var base_layer: TileMapLayer
@export var walls_layer: TileMapLayer
@export var hazard_layer: TileMapLayer
@export var marker_layer: TileMapLayer

@export_group("Save/Export")
@export var save_dir: String = DIR_COILS
@export var start_flesh_rect: Rect2i = Rect2i(Vector2i(0, 0), Vector2i(24, 24)) # auto-fill when Start With Flesh is ON
@export var biomass_cap: int = 100  # hard cap unless dev bypass is enabled

## --- Scene references --------------------------------------------------------

@onready var coil_map: TileMap = $CoilMap
@onready var palette_row: HBoxContainer = %PaletteRow
@onready var status_label: Label = %StatusLabel
@onready var biomass_label: Label = %BiomassLabel
@onready var start_with_flesh_cb: CheckBox = %StartWithFlesh
@onready var ignore_biomass_limit: CheckBox = %IgnoreBiomassLimit
@onready var clear_base_confirm: ConfirmationDialog = %ClearBaseConfirm
@onready var dev_badge: Label = %DevBadge
@onready var validate_dialog: AcceptDialog = %ValidateDialog
@onready var validate_body: RichTextLabel = %Body
@onready var validate_btn: Button = %ValidateBtn
@onready var save_btn: Button = %SaveBtn
@onready var load_btn: Button = %LoadBtn
@onready var playtest_btn: Button = %PlaytestBtn
@onready var publish_btn: Button = %PublishBtn
@onready var hub_btn: Button = %HubBtn
@onready var title_edit: LineEdit = %TitleEdit
@onready var validation_chip: Label = %ValidationChip
@onready var load_dialog: FileDialog = %LoadDialog
@onready var _q: CoilQuery = CoilQueryScript.new()

## --- State --------------------------------------------------------

var _title_cache: String = ""
var _current_index: int = 0
var _is_painting_left := false
var _is_erasing_right := false
var _last_preview_cell: Vector2i = Vector2i(999999, 999999)
var _palette_buttons: Array[TextureButton] = []
var _biomass_used: int = 0
var _last_validation_ok: bool = false
var undo_stack: Array = []
var redo_stack: Array = []

## --- UI wiring & Lifecycle --------------------------------------------------------

## Wires all UI and dev controls, mirrors palette → brushes, selects default brush,
## optionally pre-fills Base with Flesh, restores a pending coil from Playtest, and
## syncs biomass + validation chip on entry.
func _ready() -> void:
	# Basic sanity checks
	if brush_registry == null: push_error("❌ BrushRegistry not assigned on BuilderMode.")
	if coil_map == null: push_error("❌ CoilMap TileMap not found.")
	if base_layer == null: push_error("❌ base_layer not assigned on BuilderMode.")
	if walls_layer == null: push_error("❌ walls_layer not assigned on BuilderMode.")
	if hazard_layer == null: push_error("❌ hazard_layer not assigned on BuilderMode.")
	if marker_layer == null: push_error("❌ marker_layer not assigned on BuilderMode.")

	# Reset undo/redo each time this scene is (re)entered
	undo_stack.clear()
	redo_stack.clear()

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
	if hub_btn:
		hub_btn.pressed.connect(_on_hub_pressed)
	if load_dialog:
		load_dialog.file_selected.connect(_on_load_file_selected)
	if title_edit:
		title_edit.text_changed.connect(_on_title_changed)
		# Nice QoL: pressing Enter just blurs the field; not required for saving anymore.
		title_edit.text_submitted.connect(func(_t): title_edit.release_focus())

	# Wire each palette button (by order) to a brush (by order).
	# Left to right buttons map to registry.brushes[0..N]
	# Use a ButtonGroup so only one brush is active at a time; this keeps selection state in sync with the registry.
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

## Undo/Redo system
# Each undo/redo "command" will be stored as a Dictionary.
# For now we only support "paint" commands affecting a single cell.
# Later we can extend this to erase and multi-cell strokes.
#
# Example shape:
# {
#     "kind": "paint",
#     "coords": Vector2i(x, y),
#     "layer_name": "Base", # or whatever your TileMap layer node is called
#     "before": { "source_id": int, "atlas_coords": Vector2i },
#     "after":  { "source_id": int, "atlas_coords": Vector2i },
# }
#
# undo_stack: Array[Dictionary]
# redo_stack: Array[Dictionary]

func _get_tile_state(layer: TileMapLayer, coords: Vector2i) -> Dictionary:
	# In Godot 4 TileMapLayer, we don't specify a layer index
	var source_id := layer.get_cell_source_id(coords)
	if source_id == -1:
		# Represent empty cells with a special marker.
		return {
			"is_empty": true,
			"source_id": -1,
			"atlas_coords": Vector2i.ZERO,
		}

	var atlas_coords := layer.get_cell_atlas_coords(coords)
	return {
		"is_empty": false,
		"source_id": source_id,
		"atlas_coords": atlas_coords,
	}

# Record a single-cell paint command into the undo stack.
func _record_paint_command(coords: Vector2i, layer: TileMapLayer, before_state: Dictionary, after_state: Dictionary) -> void:
	var cmd: Dictionary = {
		"kind": "paint",
		"coords": coords,
		# Store a NodePath so we can re-resolve the layer every time
		"layer_path": get_path_to(layer),
		"layer_name": layer.name,  # optional, for debugging only
		"before": before_state,
		"after": after_state,
	}

	undo_stack.append(cmd)
	redo_stack.clear()

# Very simple debug undo: only supports "paint" commands right now.
func _debug_undo_last_command() -> void:
	if undo_stack.is_empty():
		_show_status("Undo: stack empty.")
		return  # nothing to undo

	# Take the last command.
	var cmd: Dictionary = undo_stack.pop_back()

	# Currently we only support paint commands.
	if cmd.get("kind") != "paint":
		return  # ignore unknown commands for now

	# Resolve the layer from its stored NodePath
	var layer_path_v: Variant = cmd.get("layer_path", NodePath(""))
	if typeof(layer_path_v) != TYPE_NODE_PATH:
		push_error("Undo: missing or invalid layer_path in command.")
		return

	var layer_path: NodePath = layer_path_v
	var layer_node := get_node_or_null(layer_path)
	if layer_node == null:
		push_error("Undo: could not resolve layer at path '%s'" % String(layer_path))
		return

	var layer := layer_node as TileMapLayer
	if layer == null:
		push_error("Undo: node at '%s' is not a TileMapLayer." % String(layer_path))
		return

	var coords: Vector2i = cmd.get("coords", Vector2i.ZERO)
	var before_state: Dictionary = cmd.get("before", {})

	# Apply the "before" tile state back to the map.
	if before_state.get("is_empty", true):
		# Empty tile -> clear the cell.
		layer.erase_cell(coords)
	else:
		# Restore previous tile details.
		var src_id: int = before_state.get("source_id", -1)
		var atlas_coords: Vector2i = before_state.get("atlas_coords", Vector2i.ZERO)
		# TileMapLayer.set_cell(coords, source_id, atlas_coords)
		layer.set_cell(coords, src_id, atlas_coords)

	# Optional: push this command to redo_stack so we can redo later.
	redo_stack.append(cmd)

	# Recalculate biomass so UI stays correct.
	if has_method("_recalc_biomass"):
		_recalc_biomass()

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

	# Debug: undo last paint command when the debug action is pressed.----------
	if event.is_action_pressed("builder_undo_debug"):
		_debug_undo_last_command()
		return

## Toggle visibility for dev-only badge
func _on_dev_mode_changed(enabled: bool) -> void:
	if dev_badge:
		dev_badge.visible = enabled
	var state_text: String = "OFF"
	if enabled:
		state_text = "ON"
	_show_status("Dev Mode: " + state_text)

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

### Place a tile using the selected brush after validation
#func _paint_at(coords: Vector2i) -> void:
	#var b: BrushEntry = _current_brush()
	#if b == null:
		#_show_status("⚠️ No brush selected.")
		#return
	#
	## ERASER: just erase and return
	#if b.rule_profile == "ERASER":
		#_erase_at(coords)
		#return
	#
	## Validate according to rule profile (see functions below)
	#if not _validate_placement(b, coords):
		#return
	#
	## Place the tile (BASE/WALL/POOL/MARKER)
	#if b.source_id < 0:
		#_show_status("⚠️ Source ID not set for brush: " + b.display_name)
		#return
	#
	#var layer := _layer_for(b.target_layer)
	#if layer == null:
		#_show_status("⚠️ Unknown target layer: " + str(b.target_layer))
		#return
	#
	## Place the tile
	#layer.set_cell(coords, b.source_id, b.atlas_coords)
	#
	## If we just placed a marker, enforce singletons (Spawn and Heartroot)
	#if layer == marker_layer:
		#_enforce_single_spawn_at(coords)
		#_enforce_single_heartroot_at(coords)
	#
	## Recalc biomass after successful placement
	#_recalc_biomass()

## Remove tiles at the cell across relevant layers
func _erase_at(coords: Vector2i) -> void:
	# Simple MVP: erase Hazards/Walls/Markers at this cell; keep Base Flesh intact.
	for layer_node in [base_layer, marker_layer, hazard_layer, walls_layer]:
		if layer_node:
			layer_node.erase_cell(coords)

	# Recalc biomass after successful placement
	_recalc_biomass()

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

	# --- NEW: capture the "before" state for undo ---
	var before_state := _get_tile_state(layer, coords)

	# Place the tile
	layer.set_cell(coords, b.source_id, b.atlas_coords)

	# If we just placed a marker, enforce singletons (Spawn and Heartroot)
	if layer == marker_layer:
		_enforce_single_spawn_at(coords)
		_enforce_single_heartroot_at(coords)

	# Recalc biomass after successful placement
	_recalc_biomass()
	# --- NEW: capture the "after" state and record the command ---

	var after_state := _get_tile_state(layer, coords)
	# If nothing actually changed (e.g. painting same tile on top), don't record undo noise.
	if before_state == after_state:
		return

	_record_paint_command(coords, layer, before_state, after_state)

## Emit a friendly inline status and return false (used by placement validators).
func _reject_or_false(msg: String, report: bool) -> bool:
	if report:
		_show_status("🚫 " + msg)
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
	# Note: we tint the WHOLE preview layer (not per-cell materials). This is simple and cheap; if we ever want per-cell tint,
	# we'll switch to a separate ghost atlas or shaders.

	# Clear the previous preview cell
	if preview_layer and _last_preview_cell.x < 900000:
		preview_layer.erase_cell(_last_preview_cell)

	# Compute current mouse cell
	var coords := _cell_under_mouse()
	_last_preview_cell = coords

	var b := _current_brush()
	if b == null or b.rule_profile == "ERASER":
		if preview_layer:
			preview_layer.modulate = Color(1,1,1,0.5)
		return

	# Always place the ghost tile
	if preview_layer and b.source_id >= 0:
		preview_layer.set_cell(coords, b.source_id, b.atlas_coords)
		# Now tint based on validity
		var ok: bool = _validate_placement(b, coords, false)
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
	var v: Variant = td.get_custom_data("cost")
	if v is int:
		return int(v)
	return 0

## Recompute the biomass total across all layers
func _recalc_biomass() -> void:
	# O(N used cells) recompute for clarity. For larger maps we can micro-opt by delta-adjusting on each paint/erase.
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

## Start-with-Flesh: convenience for quick greyboxing. Turning it OFF offers a smart clear of the same rect,
## removing dependent tiles inside that area first (Walls/Hazards/Markers) before erasing Flesh.
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

## Save the current coil to a JSON file in the user directory
func _on_save_pressed() -> void:
	# Keep numbers fresh in the save
	_recalc_biomass()
	# Ensure directory exists
	if DirAccess.open(save_dir) == null:
		var err: int = DirAccess.make_dir_recursive_absolute(save_dir)
		if err != OK:
			_show_status("Save failed: couldn't create " + save_dir)
			return

	# Build a timestamped filename
	var path: String = _timestamp_file(save_dir, F_COIL_PREFIX, EXT_JSON)
	# Write JSON
	var data := _capture_coil()  # CHANGED: _capture_coil now includes validation snapshot
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_show_status("Save failed (" + str(FileAccess.get_open_error()) + ").")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	_show_status("Saved: " + path)

	if data.has("meta") and (data["meta"] as Dictionary).has("validated"):
		var ok_now := bool((data["meta"] as Dictionary)["validated"])
		_update_validation_chip(ok_now)

	# Remember last_opened_coil_path on current profile
	if has_node("/root/ProfileManager"):
		var pm2: Node = get_node("/root/ProfileManager")
		if pm2.has_method("set_current_last_opened_coil"):
			pm2.call("set_current_last_opened_coil", path)

## Open a file dialog to choose a coil to load
func _on_load_pressed() -> void:
	# Ensure save_dir exists (e.g., "user://coils")
	if DirAccess.open(save_dir) == null:
		var err: int = DirAccess.make_dir_recursive_absolute(save_dir)
		if err != OK:
			_show_status("Failed to create " + save_dir)
	if load_dialog:
		load_dialog.access = FileDialog.ACCESS_USERDATA
		load_dialog.current_dir = save_dir        # e.g., "user://coils"
		load_dialog.popup_centered()

## Load a selected coil JSON and apply it to layers
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
	#var meta_v: Variant = data.get("meta", {})
	#if typeof(meta_v) == TYPE_DICTIONARY:
		#var meta: Dictionary = meta_v
		#var creator_id: String = String(meta.get("creator_profile_id", ""))
		#var cur_id: String = _current_profile_id()
		#if creator_id != "" and cur_id != "" and creator_id != cur_id:
			#_show_status("⚠ Loaded coil from another profile.")
	#CoilIO.apply_coil(data, base_layer, walls_layer, hazard_layer, marker_layer)
	#_recalc_biomass()
	#_show_status("Loaded: " + path)
	#_refresh_validation_state()  # don't touch disk; just reflect truth in UI
	## Remember last_opened_coil_path on current profile
	#if has_node("/root/ProfileManager"):
		#var pm3: Node = get_node("/root/ProfileManager")
		#if pm3.has_method("set_current_last_opened_coil"):
			#pm3.call("set_current_last_opened_coil", path)
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

	# Warn if coil belongs to another profile
	var meta_v: Variant = data.get("meta", {})
	if typeof(meta_v) == TYPE_DICTIONARY:
		var meta: Dictionary = meta_v
		var creator_id: String = String(meta.get("creator_profile_id", ""))
		var cur_id: String = _current_profile_id()
		if creator_id != "" and cur_id != "" and creator_id != cur_id:
			_show_status("⚠ Loaded coil from another profile.")
		# Populate TitleEdit if present
		if is_instance_valid(title_edit):
			var t_v: Variant = meta.get("title", "")
			if typeof(t_v) == TYPE_STRING:
				title_edit.text = String(t_v)

	CoilIO.apply_coil(data, base_layer, walls_layer, hazard_layer, marker_layer)
	_recalc_biomass()
	_show_status("Loaded: " + path)
	_refresh_validation_state()
	# Remember last_opened_coil_path on current profile
	if has_node("/root/ProfileManager"):
		var pm3: Node = get_node("/root/ProfileManager")
		if pm3.has_method("set_current_last_opened_coil"):
			pm3.call("set_current_last_opened_coil", path)

## Autosave a snapshot before starting playtest
func _autosave_playtest() -> void:
	if DirAccess.open(save_dir) == null:
		var err2: int = DirAccess.make_dir_recursive_absolute(save_dir)
		if err2 != OK:
			_show_status("Failed to create " + save_dir)
			return
	var path := "%s/_autosave_playtest.json" % [save_dir]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_capture_coil(), "\t"))
		f.close()
		_show_status("Autosaved: " + path)

## --- Save current coil as Dictionary snapshot (with validation flag & details) ---
func _capture_coil() -> Dictionary:
	var tileset_path: String = ""
	if coil_map.tile_set:
		tileset_path = coil_map.tile_set.resource_path

	# Strict validation snapshot (no biomass bypass)
	var validation_result: ValidationResult = _run_validation(false)
	_last_validation_ok = validation_result.ok  # cache for UI

	# Optional coords: null when not present (strictly typed)
	var spawn_v: Variant = null
	if validation_result.spawn.x > -900000:
		spawn_v = {"x": validation_result.spawn.x, "y": validation_result.spawn.y}
	var heart_v: Variant = null
	if validation_result.heart.x > -900000:
		heart_v = {"x": validation_result.heart.x, "y": validation_result.heart.y}

	var validation_payload: Dictionary = {
	"ok": validation_result.ok,
	"messages": validation_result.messages,
	"spawn": spawn_v,          # ← will be null when not present
	"heart": heart_v,          # ← will be null when not present
	"biomass_used": _biomass_used,
	"biomass_cap": biomass_cap,
	"validator_version": 1,
	"timestamp": _iso_timestamp()
	}

	return {
	"meta": {
		"schema_version": COIL_SCHEMA_VERSION,       # existing
		"coil_schema_version": 2,                    # NEW (explicit coil schema version)
		"id": _new_coil_id(),                        # NEW (stable-ish id for this saved coil)
		"biomass_cap": biomass_cap,
		"biomass_used": _biomass_used,
		"tileset": tileset_path,
		"validated": validation_result.ok,
		"validation": validation_payload,
		"creator_profile_id": _current_profile_id(),
		"creator_profile_name": _current_profile_name(),
		"title": _current_title(),
		"game_version": _game_version_string(),
		"notes": "",                                 # NEW (placeholder)
		"visual_theme": ""                           # NEW (placeholder)
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

## Delegate to CoilValidator (strict by default). Only Playtest may pass ignore_biomass=true when DevMode + flag is set.
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

## Validate popup is always strict; no dev bypass here.
func _on_validate_pressed() -> void:
	# Run a full check list and show a friendly popup
	_recalc_biomass()
	var result: ValidationResult = _run_validation(false) # always strict on Validate
	_show_validation_dialog(result)

## Playtest is strict unless Dev Mode is ON and ignore_biomass_limit is true (GameFlags/meta/checkbox).
func _on_playtest_pressed() -> void:
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

	print("BuilderMode: start_coil request → biomass ", _biomass_used, "/", biomass_cap, ", allow_over=", allow_over)
	var result := _run_validation(allow_over)
	if not result.ok:
		_show_validation_dialog(result)
		return

	# Optional but handy: autosave a snapshot
	_autosave_playtest()

	# Hand off to Explore via CoilSession
	var data: Dictionary = _capture_coil()
	if has_node("/root/CoilSession"):
		get_node("/root/CoilSession").call("start_coil", data, "builder")
	else:
		_show_status("Playtest: CoilSession autoload missing.")

## --- Publish Cluster --------------------------------------------------------

## Publish (Local Stub): strict validation → JSON to user://Published/ → manifest upsert.
## No backend yet; this is Phase 1.4/1.5 local “share” semantics.
func _on_publish_pressed() -> void:
	_recalc_biomass()
	var result: ValidationResult = _run_validation(false) # false => no biomass bypass (STRICT)
	if not result.ok:
		_show_validation_dialog(result)  # Friendly popup you already have
		return

	# Ensure Published/ exists (sibling to save_dir)
	var pub_dir: String = DIR_PUBLISHED
	_ensure_dir(pub_dir)

	# Timestamped publish path
	var pub_path: String = _timestamp_file(pub_dir, F_COIL_PREFIX, EXT_JSON)

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

## Ensure a directory exists (recursive)
func _ensure_dir(dir_path: String) -> void:
	if DirAccess.open(dir_path) == null:
		var err: int = DirAccess.make_dir_recursive_absolute(dir_path)  # typed int (Error enum)
		if err != OK:
			_show_status("Failed to create: " + dir_path)

## Manifest contract:
##   version:int, items:Array<{ path, title, published_at, biomass_used:int, biomass_cap:int, profile_id }>
func _update_publish_manifest(_pub_dir: String, pub_path: String, data: Dictionary) -> void:
	var manifest_path: String = PUBLISHED_MANIFEST

	# Start with a default manifest object
	var manifest: Dictionary = {
		"version": MANIFEST_VERSION,
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

	var coil_id: String = ""
	if meta.has("id"):
		var id_v: Variant = meta.get("id")
		if typeof(id_v) == TYPE_STRING:
			coil_id = String(id_v)

	# Determine profile_id, safe default ""
	var profile_id: String = ""
	if has_node("/root/ProfileManager"):
		var pm: Node = get_node("/root/ProfileManager")
		if pm.has_method("get_current_profile_id"):
			var pid_v: Variant = pm.call("get_current_profile_id")
			if typeof(pid_v) == TYPE_STRING:
				profile_id = String(pid_v)

	# Build the manifest entry (use explicit ints/strings for strict typing)
	var title_from_meta: String = String(meta.get("title", "Untitled"))
	var coil_version: String = String(meta.get("game_version", ""))

	var entry: Dictionary = {
		"path": pub_path,
		"title": title_from_meta,
		"published_at": _iso_timestamp(),
		"biomass_used": int(meta.get("biomass_used", _biomass_used)),
		"biomass_cap": int(meta.get("biomass_cap", biomass_cap)),
		"profile_id": profile_id,
		"game_version": coil_version,
		"id": coil_id,                 # NEW
		"checksum": "",                # NEW (placeholder)
		"thumbnail_path": "",          # NEW (placeholder)
		"visibility": "local"          # NEW (local vs cloud later)
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

func _timestamp_file(dir_path: String, prefix: String, ext: String) -> String:
	var ts: String = Time.get_datetime_string_from_system(false, true).replace(":", "-")
	return "%s/%s%s%s" % [dir_path, prefix, ts, ext]

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

## Strictly recompute validation and refresh Draft/Valid chip & Publish enable
func _refresh_validation_state() -> void:
	var r := _run_validation(false)  # strict
	_last_validation_ok = r.ok
	_update_validation_chip(_last_validation_ok)

func _current_profile_id() -> String:
	if has_node("/root/ProfileManager"):
		var pm: Node = get_node("/root/ProfileManager")
		if pm.has_method("get_current_profile_id"):
			return String(pm.call("get_current_profile_id"))
	return ""

func _current_profile_name() -> String:
	if has_node("/root/ProfileManager"):
		var pm: Node = get_node("/root/ProfileManager")
		if pm.has_method("get_current_profile"):
			var v: Variant = pm.call("get_current_profile")
			if typeof(v) == TYPE_DICTIONARY:
				return String((v as Dictionary).get("display_name", ""))
	return ""

func _current_title() -> String:
	# Prefer the live cache updated by text_changed (works even while the field is focused).
	var t := _title_cache.strip_edges()
	if t != "":
		return t
	# Fallback to the LineEdit’s text (covers loads / first paint).
	if is_instance_valid(title_edit):
		t = title_edit.text.strip_edges()
		if t != "":
			return t
	return "Untitled"

func _on_title_changed(new_text: String) -> void:
	_title_cache = new_text

func _game_version_string() -> String:
	if has_node("/root/BuildInfo"):
		var b: Node = get_node("/root/BuildInfo")
		if b.has_method("version_string"):
			return String(b.call("version_string"))
	# Fallback to ProjectSettings if you ever set it there
	if ProjectSettings.has_setting("application/config/version"):
		var v: Variant = ProjectSettings.get_setting("application/config/version")
		if typeof(v) == TYPE_STRING:
			return String(v)
	return "0.0.0"

func _on_hub_pressed() -> void:
	# Optional: autosave a snapshot before leaving (comment out if you don’t want it)
	# _autosave_playtest()
	if has_node("/root/CoilSession"):
		get_node("/root/CoilSession").call("return_to_heartroot")
	else:
		get_tree().change_scene_to_file("res://Scenes/Heartroot/heartroot.tscn")

# Returns a stable-ish id string for a coil (UTC timestamp + msec).
# Format: yyyymmdd_hhmmss_msec (same family as ProfileManager ids).
func _new_coil_id() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system(true)  # UTC
	var yy: int = int(dt["year"])
	var mm: int = int(dt["month"])
	var dd: int = int(dt["day"])
	var hh: int = int(dt["hour"])
	var mi: int = int(dt["minute"])
	var ss: int = int(dt["second"])
	var msec: int = Time.get_ticks_msec() % 1000

	var id_str: String = str(yy)
	id_str += _pad2(mm)
	id_str += _pad2(dd)
	id_str += "_"
	id_str += _pad2(hh)
	id_str += _pad2(mi)
	id_str += _pad2(ss)
	id_str += "_"
	id_str += str(msec)
	return id_str

# Utility used by _new_coil_id()
func _pad2(n: int) -> String:
	if n < 10:
		return "0" + str(n)
	return str(n)

## end builder_mode.gd
