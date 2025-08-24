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
@onready var status_label: Label = $UI/StatusLabel

## --- Layer indices (match Explore/Crawler) ---
#const LAYER_BASE     := 0
#const LAYER_WALLS    := 1
#const LAYER_HAZARDS  := 2
#const LAYER_MARKERS  := 3

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
	var i: int = 0
	for child in palette_row.get_children():
		if child is BaseButton:
			var idx: int = i
			child.pressed.connect(func():
				_select_brush(idx)
			)
			i += 1
	
	# Default select the first brush, if any
	if brush_registry != null and brush_registry.brushes.size() > 0:
		_select_brush(0)

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
	layer.set_cell(coords, b.source_id, b.atlas_coords)

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
			# Rule B: Pools cannot overlap walls
			if _has_wall(coords):
				return _reject("Pools cannot overlap walls.")
			# Rule C: Pools cannot touch walls orthogonally
			for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				if _has_wall(coords + dir):
					return _reject("Pools can’t touch walls (N/E/S/W).")
			# Rule D: Pools cannot touch a different pool kind orthogonally
			if b.hazard_kind != "":
				for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					var neighbor := _hazard_kind_at(coords + dir)
					if neighbor != "" and neighbor != b.hazard_kind:
						return _reject("Different pools can’t touch (N/E/S/W).")
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

func _reject(msg: String) -> bool:
	_show_status("🚫 " + msg)
	return false

## end builder_mode.gd
