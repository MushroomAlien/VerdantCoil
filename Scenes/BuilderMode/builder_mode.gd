## builder_mode.gd
## Data-driven Builder: picks a brush from a registry, validates, then paints.

extends Node2D

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0),
	Vector2i(0, 1), Vector2i(0, -1)
]

## --- External registry (set this in the Inspector) ---
@export var brush_registry: BrushRegistry

## --- Coil map layer nodes ---
@export var preview_layer: TileMapLayer
@export var base_layer: TileMapLayer
@export var walls_layer: TileMapLayer
@export var hazard_layer: TileMapLayer
@export var marker_layer: TileMapLayer

## --- Scene references ---
@onready var coil_map: TileMap = $CoilMap
@onready var palette_row: HBoxContainer = $UI/TopBar/PaletteRow
@onready var biomass_label: Label = $UI/TopBar/PaletteRow/BiomassLabel
@onready var status_label: Label = $UI/TopBar/StatusLabel
@onready var start_with_flesh_cb: CheckBox = $UI/TopBar/StartWithFlesh
@onready var clear_base_confirm: ConfirmationDialog = $UI/TopBar/ClearBaseConfirm
@onready var dev_badge: Label = $UI/DevOverlay/DevBadge
@onready var validate_btn: Button = $UI/TopBar/PaletteRow/ValidateBtn
@onready var save_btn: Button = $UI/TopBar/PaletteRow/SaveBtn
@onready var playtest_btn: Button = $UI/TopBar/PaletteRow/PlaytestBtn
@onready var validate_dialog: AcceptDialog = $UI/TopBar/ValidateDialog
@onready var validate_body: RichTextLabel = $UI/TopBar/ValidateDialog/Body

## Size of the prefill area for Flesh (adjust to your map size)
@export var start_flesh_rect: Rect2i = Rect2i(Vector2i(0, 0), Vector2i(24, 24))

## --- Current brush selection ---
var _current_index: int = 0
var _is_painting_left := false
var _is_erasing_right := false
var _last_preview_cell: Vector2i = Vector2i(999999, 999999)
var _palette_buttons: Array[TextureButton] = []

## --- Biomass variables ---
@export var biomass_cap: int = 100  # tweak anytime in Inspector
var _biomass_used: int = 0

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

	# Wire each palette button (by order) to a brush (by order).
	# Left to right buttons map to registry.brushes[0..N]
	#var _palette_group := ButtonGroup.new()  # keep one group
	#var i := 0
	#for child in palette_row.get_children():
		#print("child :", child)
		#if child is TextureButton:
			#child.toggle_mode = true
			#child.button_group = _palette_group
			#child.focus_mode = Control.FOCUS_NONE
			#child.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			#child.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
			#child.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			#
			#var idx := i
			#child.pressed.connect(func(): _select_brush(idx))
			## Set icon
			#if brush_registry != null and idx < brush_registry.brushes.size():
				#var be := brush_registry.brushes[idx]
				#if be.icon:
					#child.texture_normal = be.icon
				#child.tooltip_text = be.display_name
			## Inactive look by default
			#child.self_modulate = Color(0.7, 0.7, 0.7, 1.0)
			#child.scale = Vector2.ONE
			#i += 1
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
	_recalc_biomass()

func _process(_delta: float) -> void:
	_update_preview()

func _layer_for(index: int) -> TileMapLayer:
	match index:
		0: return base_layer
		1: return walls_layer
		2: return hazard_layer
		3: return marker_layer
		_: return null

func _cell_under_mouse() -> Vector2i:
	# Convert current global mouse position to a TileMap cell once.
	var mouse_world: Vector2 = get_global_mouse_position()
	var mouse_local: Vector2 = base_layer.to_local(mouse_world)
	return base_layer.local_to_map(mouse_local)

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

## --- Selection / Status -------------------------------------------------------
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

func _show_status(msg: String) -> void:
	status_label.text = msg
	print(msg)

## --- Painting / Erasing -------------------------------------------------------
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

func _erase_at(coords: Vector2i) -> void:
	# Simple MVP: remove from all known layers at this cell
	for layer_node in [marker_layer, hazard_layer, walls_layer]:
		if layer_node:
			layer_node.erase_cell(coords)
			
	# Recalc biomass after successful placement
	_recalc_biomass()

## --- Validation helpers -------------------------------------------------------
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

func _validate_placement(b: BrushEntry, coords: Vector2i, report := true) -> bool:
	match b.rule_profile:
		"BASE":
			# Flesh is always allowed. (If you want to forbid overpainting, add checks here.)
			return true
		
		"WALL":
			# Rule A: Walls must sit on Flesh
			if not _has_base(coords):
				return _reject_or_false("Walls require Flesh beneath.", report)
			# Rule B: Walls cannot overlap an existing hazard
			if _hazard_kind_at(coords) != "":
				return _reject_or_false("Walls cannot overlap pools.", report)
			return true
		
		"POOL":
			# Rule A: Pools must sit on Flesh
			if not _has_base(coords):
				return _reject_or_false("Pools require Flesh beneath.", report)
			# Rule B: Pools cannot overlap walls (same cell)
			if _has_wall(coords):
				return _reject_or_false("Pools cannot overlap walls.", report)
			return true
		
		"MARKER":
			# Rule A: Markers require Flesh
			if not _has_base(coords):
				return _reject_or_false("Markers require Flesh beneath.", report)
			# Rule B: Must not be blocked or hazardous
			if _has_wall(coords) or _hazard_kind_at(coords) != "":
				return _reject_or_false("Markers can’t sit under walls or pools.", report)
			return true
		
		"ERASER":
			# Handled earlier; never reaches here.
			return true
		_:
			#return _reject("Unknown rule profile: " + b.rule_profile)
			return _reject_or_false("Unknown rule profile: " + b.rule_profile, report)

## Ensures only one spawn marker exists on the Markers layer.
## If the tile we just placed at `coords` has custom_data is_spawn = true,
## erase all other cells in the Markers layer that also have is_spawn = true.
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

## Ensures only one Heartroot exists on the Markers layer.
## If the tile at `coords` has custom_data is_goal = true,
## erase any other cells in the Markers layer that also have is_goal = true.
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

## --- Start-with-Flesh ---------------------------------------------------------
## Called when the checkbox is toggled. We only *add* flesh; never auto-erase.
func _on_start_with_flesh_toggled(pressed: bool) -> void:
	if pressed:
		_apply_start_with_flesh(true)
	else:
		_prompt_clear_base()

## One-shot prefill of the base layer. Skips cells that already have something.
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

## Remove all cells from the Base/Flesh layer.
## Note: This only clears the base layer; walls/pools/markers remain as-is.
## --- Smart Clear (with confirmation) ------------------------------------------
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

## Called when the user clicks "OK" in the dialog
func _on_clear_base_confirmed() -> void:
	_smart_clear_base_rect(start_flesh_rect)
	_show_status("Cleared base and dependent tiles in %dx%d area." % [start_flesh_rect.size.x, start_flesh_rect.size.y])
	# Keep the checkbox unticked (it already is). No refill.

## Counts used cells for a given layer within rect
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

## Remove Flesh in the rect, and also remove any walls/pools/markers in that rect.
## "Smart" = only within the seeded rectangle; everything outside remains untouched.
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

## Helper: find a brush whose rule_profile is "BASE"
func _find_default_flesh_brush() -> BrushEntry:
	if brush_registry == null:
		return null
	for be in brush_registry.brushes:
		if be is BrushEntry and be.rule_profile == "BASE" and be.source_id >= 0:
			return be
	return null

# Return false silently, or route through _reject if reporting is enabled.
func _reject_or_false(msg: String, report: bool) -> bool:
	if report:
		_show_status("🚫 " + msg)
		#return _reject(msg)  # prints + shakes/beeps (if you wired SFX)
	return false

## Update the preview cell under the mouse
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

## --- Biomass helpers ----------------------------------------------------------
## Safely read 'cost' from a cell on a given layer. If no tile or no key -> 0.
func _tile_cost(layer: TileMapLayer, coords: Vector2i) -> int:
	if layer == null:
		return 0
	var td: TileData = layer.get_cell_tile_data(coords)
	if td == null:
		return 0
	var v = td.get_custom_data("cost")
	return int(v) if (v is int) else 0

## Recalculate total biomass by scanning all layers (fast enough for 24x24).
func _recalc_biomass() -> void:
	var total := 0
	for layer_node in [base_layer, walls_layer, hazard_layer, marker_layer]:
		if layer_node:
			for c in layer_node.get_used_cells():
				total += _tile_cost(layer_node, c)
	_biomass_used = total
	_update_biomass_label()

## Update the label and warn softly if over cap.
func _update_biomass_label() -> void:
	if biomass_label == null:
		return
	
	biomass_label.text = "Biomass: %d / %d" % [_biomass_used, biomass_cap]
	var col := Color(1, 1, 1)
	if _biomass_used > biomass_cap:
		col = Color(1, 0.25, 0.25)
	biomass_label.modulate = col

# --- Actions: Validate / Save / Playtest --------------------------------------

func _on_validate_pressed() -> void:
	# Run a full check list and show a friendly popup
	var result := _run_validation()
	_show_validation_dialog(result)

func _on_save_pressed() -> void:
	# Phase 1.5 will implement real JSON save/export.
	_show_status("Save: coming in Phase 1.5 (JSON export).")
	# (Optional: gray this button out until 1.5.)

func _on_playtest_pressed() -> void:
	# We’ll hook this in soon via a tiny Autoload handoff to ExploreMode.
	_show_status("Playtest: coming next — quick handoff to ExploreMode.")

# Data container for validation results
class ValidationResult:
	var ok: bool = false
	var messages: Array[String] = []
	var spawn: Vector2i = Vector2i(-999999, -999999)
	var heart: Vector2i = Vector2i(-999999, -999999)

# Run the checks defined in our docs (spawn, heartroot, solvable path).
# Biomass budget check is kept soft here until your BiomassManager is in.
func _run_validation() -> ValidationResult:
	var r := ValidationResult.new()

	# 1) Exactly one Spawn and Heartroot (Markers layer)
	var spawn_cells := _find_marker_cells("is_spawn")
	var heart_cells := _find_marker_cells("is_goal")

	if spawn_cells.size() != 1:
		r.messages.append("❌ Place exactly one Spawn (found %d)." % spawn_cells.size())
	else:
		r.spawn = spawn_cells[0]

	if heart_cells.size() != 1:
		r.messages.append("❌ Place exactly one Heartroot (found %d)." % heart_cells.size())
	else:
		r.heart = heart_cells[0]

	# 2) Path exists from Spawn → Heartroot (walkable flesh, no walls, no blocking hazards)
	if r.spawn.x > -900000 and r.heart.x > -900000:
		if not _is_reachable(r.spawn, r.heart):
			r.messages.append("❌ Heartroot unreachable from Spawn.")
	else:
		# If either is missing, the path check is moot.
		pass

	# (Optional) 3) Biomass cap — wire to your real budget when ready.
	# if _current_biomass() > _biomass_cap():
	#     r.messages.append("❌ Biomass over cap by %d." % (_current_biomass() - _biomass_cap()))

	# Result state
	r.ok = (r.messages.size() == 0)
	if r.ok:
		r.messages.append("✅ Valid coil. Ready to Playtest or Save.")
	return r

# Find all cells in Markers layer that have a given boolean flag in custom_data.
func _find_marker_cells(flag_key: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if marker_layer == null:
		return out
	for c in marker_layer.get_used_cells():
		var td := marker_layer.get_cell_tile_data(c)
		if td != null and bool(td.get_custom_data(flag_key) or false):
			out.append(c)
	return out

# Simple BFS for reachability on our rules (flesh required, no walls, no hazards).
func _is_reachable(start: Vector2i, goal: Vector2i) -> bool:
	# Trivial case: same cell
	if start == goal:
		return true
	# visited can be typed; Vector2i works fine as a Dictionary key
	var visited: Dictionary = {}
	var q: Array[Vector2i] = []
	q.append(start)
	visited[start] = true
	while q.size() > 0:
		# pop_front() returns Variant → cast or type the variable explicitly
		var cur: Vector2i = q.pop_front() as Vector2i
		if cur == goal:
			return true
		# DIRS is a typed Array[Vector2i], so 'dir' is Vector2i too
		for dir in DIRS:
			var nxt: Vector2i = cur + dir
			# Walk rules: must have Flesh, no Walls, no Hazards
			# ---- Traversal rules (MVP):
			# 1) Must have Flesh on Base
			if not _has_base(nxt):
				continue
			# 2) Solid walls block (digest walls DO NOT block)
			if _is_solid_wall(nxt):
				continue
			# 3) Hazards do NOT block (acid/sticky are passable with upgrades)
			#    -> intentionally no check of _hazard_kind_at(nxt)
			if not visited.has(nxt):
				visited[nxt] = true
				q.append(nxt)
	return false

# Fill and show the AcceptDialog nicely.
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

# Returns true only when a SOLID wall tile is at coords.
func _is_solid_wall(coords: Vector2i) -> bool:
	if walls_layer == null:
		return false
	var td: TileData = walls_layer.get_cell_tile_data(coords)
	if td == null:
		return false
	# Preferred: boolean custom data
	var v = td.get_custom_data("is_solid")
	if v is bool:
		return v
	# Fallback: string kind, e.g. "SOLID" / "DIGEST"
	var k = td.get_custom_data("wall_kind")
	if k is String:
		return (String(k) == "SOLID")
	# If no metadata, be conservative: treat as solid.
	return true


## DEV MODE gate: show/hide dev-only UI and ping status
func _on_dev_mode_changed(enabled: bool) -> void:
	if start_with_flesh_cb:
		start_with_flesh_cb.visible = enabled
	if dev_badge:
		dev_badge.visible = enabled
	# Friendly ping so you always know the state
	_show_status("Dev Mode: " + ("ON" if enabled else "OFF"))

## end builder_mode.gd
