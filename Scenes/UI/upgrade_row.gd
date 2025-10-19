## res://Scenes/UI/upgrade_row.gd
# res://UI/upgrade_row.gd
# Godot 4.4.1
# HUD row that mirrors the Crawler's UpgradeController and/or the global UpgradeState.

extends HBoxContainer

# --- Assign these in the editor ---
@export_node_path("CanvasItem") var hardened_icon_path: NodePath
@export_node_path("CanvasItem") var acid_icon_path: NodePath
@export_node_path("CanvasItem") var ghost_icon_path: NodePath

@export var active_modulate: Color = Color(1, 1, 1, 1)
@export var inactive_modulate: Color = Color(0.55, 0.55, 0.55, 1)

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
    # Map enum -> icon and tint
    if upgrade == _controller.Upgrade.HARDENED_SKIN:
        _set_icon(_hardened_icon, value)
    elif upgrade == _controller.Upgrade.ACID_SAC:
        _set_icon(_acid_icon, value)
    elif upgrade == _controller.Upgrade.GHOST_TRAIL:
        _set_icon(_ghost_icon, value)

# --- Read from UpgradeController if we have it ---
func _refresh_from_controller() -> void:
    if _controller == null:
        return
    var H: bool = false
    var A: bool = false
    var G: bool = false

    if _controller.has_method("has_upgrade"):
        H = bool(_controller.call("has_upgrade", _controller.Upgrade.HARDENED_SKIN))
        A = bool(_controller.call("has_upgrade", _controller.Upgrade.ACID_SAC))
        G = bool(_controller.call("has_upgrade", _controller.Upgrade.GHOST_TRAIL))

    _set_icon(_hardened_icon, H)
    _set_icon(_acid_icon, A)
    _set_icon(_ghost_icon, G)

# --- Fallback: read current values from UpgradeState (run start) ---
func _refresh_from_state() -> void:
    var H: bool = false
    var A: bool = false
    var G: bool = false

    if has_node("/root/UpgradeState"):
        var us: Node = get_node("/root/UpgradeState")
        if us.has_method("has_hardened_skin"):
            H = bool(us.call("has_hardened_skin"))
        if us.has_method("has_acid_sac"):
            A = bool(us.call("has_acid_sac"))
        if us.has_method("has_ghost_trail"):
            G = bool(us.call("has_ghost_trail"))

    _set_icon(_hardened_icon, H)
    _set_icon(_acid_icon, A)
    _set_icon(_ghost_icon, G)

# --- Tint helper (typed & explicit) ---
func _set_icon(icon: CanvasItem, is_active: bool) -> void:
    if icon == null:
        return
    if is_active:
        icon.modulate = active_modulate
    else:
        icon.modulate = inactive_modulate

## end res://Scenes/UI/upgrade_row.gd
