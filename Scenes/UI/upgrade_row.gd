## res://Scenes/UI/upgrade_row.gd
# res://UI/upgrade_row.gd
# Godot 4.4.1
# HUD row that mirrors the Crawler's UpgradeController and/or the global UpgradeState.

extends HBoxContainer

# --- Assign these in the editor ---
@export_node_path("CanvasItem") var hardened_icon_path: NodePath
@export_node_path("CanvasItem") var acid_icon_path: NodePath
@export_node_path("CanvasItem") var ghost_icon_path: NodePath

@export var active_modulate: Color   = Color(1, 1, 1, 1)           # upgrade is ON
@export var equipped_modulate: Color = Color(0.75, 0.75, 0.75, 1)  # slotted but inactive
@export var inactive_modulate: Color = Color(0.35, 0.35, 0.35, 1)  # not in this run's loadout
@export var locked_modulate: Color   = Color(0.3, 0.3, 0.3, 0.45)  # not yet implemented

# --- Resolved nodes (typed) ---
@onready var _hardened_icon: CanvasItem = get_node_or_null(hardened_icon_path)
@onready var _acid_icon: CanvasItem     = get_node_or_null(acid_icon_path)
@onready var _ghost_icon: CanvasItem    = get_node_or_null(ghost_icon_path)

# Reference to the crawler's controller (set from ExploreMode)
var _controller: Node = null

func _ready() -> void:
	# Optional: listen to global loadout so we can tint once at run start.
	if has_node("/root/UpgradeState"):
		var us: Node = get_node("/root/UpgradeState")
		if us.has_signal("loadout_changed"):
			us.connect("loadout_changed", Callable(self, "_refresh_from_state"))

	_refresh_from_state()  # safe even if UpgradeState not present

# --- Public: called by ExploreMode after spawning the crawler ---
func set_controller(controller: Node) -> void:
	_controller = controller
	if _controller != null and _controller.has_signal("upgrade_changed"):
		_controller.connect("upgrade_changed", Callable(self, "_on_controller_upgrade_changed"))
	# Initial sync from the controller, if available
	_refresh_from_controller()

# --- Signal handler from UpgradeController (instant visual feedback) ---
func _on_controller_upgrade_changed(upgrade: int, value: bool) -> void:
	# value = new active state. Read equipped state from the controller too.
	var equipped: bool = false
	if _controller != null and _controller.has_method("is_equipped"):
		equipped = bool(_controller.call("is_equipped", upgrade))

	if upgrade == _controller.Upgrade.HARDENED_SKIN:
		_set_icon_state(_hardened_icon, value, equipped)
	elif upgrade == _controller.Upgrade.ACID_SAC:
		_set_icon_state(_acid_icon, value, equipped)
	elif upgrade == _controller.Upgrade.GHOST_TRAIL:
		_set_icon_state(_ghost_icon, value, equipped)

# --- Read from UpgradeController if we have it ---
func _refresh_from_controller() -> void:
	if _controller == null:
		return

	# Read both active and equipped states from the controller.
	var h_active: bool = false
	var a_active: bool = false
	var g_active: bool = false
	var h_equipped: bool = false
	var a_equipped: bool = false
	var g_equipped: bool = false

	if _controller.has_method("has_upgrade"):
		h_active = bool(_controller.call("has_upgrade", _controller.Upgrade.HARDENED_SKIN))
		a_active = bool(_controller.call("has_upgrade", _controller.Upgrade.ACID_SAC))
		g_active = bool(_controller.call("has_upgrade", _controller.Upgrade.GHOST_TRAIL))

	if _controller.has_method("is_equipped"):
		h_equipped = bool(_controller.call("is_equipped", _controller.Upgrade.HARDENED_SKIN))
		a_equipped = bool(_controller.call("is_equipped", _controller.Upgrade.ACID_SAC))
		g_equipped = bool(_controller.call("is_equipped", _controller.Upgrade.GHOST_TRAIL))

	_set_icon_state(_hardened_icon, h_active, h_equipped)
	_set_icon_state(_acid_icon,     a_active, a_equipped)
	_set_icon_state(_ghost_icon,    g_active, g_equipped)

# --- Fallback: read equipped set from UpgradeState (called at run start before controller exists) ---
# At this point no upgrade is active yet, so we only show equipped vs not-equipped.
func _refresh_from_state() -> void:
	var h_equipped: bool = false
	var a_equipped: bool = false

	var g_equipped: bool = false

	if has_node("/root/UpgradeState"):
		var us: Node = get_node("/root/UpgradeState")
		if us.has_method("is_equipped"):
			h_equipped = bool(us.call("is_equipped", "HARDENED_SKIN"))
			a_equipped = bool(us.call("is_equipped", "ACID_SAC"))
			g_equipped = bool(us.call("is_equipped", "GHOST_TRAIL"))

	# Nothing is active yet — show equipped state only (active = false).
	_set_icon_state(_hardened_icon, false, h_equipped)
	_set_icon_state(_acid_icon,     false, a_equipped)
	_set_icon_state(_ghost_icon,    false, g_equipped)

# --- Tint helpers ---

# Three-state icon renderer.
# active=true → bright (upgrade is ON).
# active=false, equipped=true → medium (slotted this run, available to activate).
# active=false, equipped=false → dim (not in this run's loadout).
func _set_icon_state(icon: CanvasItem, is_active: bool, is_equipped: bool) -> void:
	if icon == null:
		return
	if is_active:
		icon.modulate = active_modulate
	elif is_equipped:
		icon.modulate = equipped_modulate
	else:
		icon.modulate = inactive_modulate

# Renders an icon as locked/unavailable — distinct from not-slotted.
# Used for Ghost Trail until Phase 4.
func _set_icon_locked(icon: CanvasItem) -> void:
	if icon == null:
		return
	icon.modulate = locked_modulate

## end res://Scenes/UI/upgrade_row.gd
