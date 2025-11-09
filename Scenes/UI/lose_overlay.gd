## res://Scenes/UI/lose_overlay.gd
## Godot 4.4.1
## Role: Show a modal "You died" overlay on global death, block world input,
##       and offer Retry (reload Explore) or Exit (return to Heartroot via CoilSession).

extends Control

# --- Exported NodePaths (drag in the Inspector for safe wiring) ---
@export_node_path("Button") var retry_button_path: NodePath
@export_node_path("Button") var exit_button_path: NodePath
@export_node_path("CanvasItem") var dimmer_path: NodePath
@export_node_path("Control") var dialog_path: NodePath

# --- Resolved nodes (typed) ---
@onready var _retry_btn: Button = get_node_or_null(retry_button_path)
@onready var _exit_btn: Button = get_node_or_null(exit_button_path)
@onready var _dimmer: CanvasItem = get_node_or_null(dimmer_path)
@onready var _dialog: Control = get_node_or_null(dialog_path)

# Keep a ref to HealthSystem to disconnect safely
var _health_system: Node = null

func _ready() -> void:
	# Start hidden; we'll show on death signal.
	visible = false

	# Connect button presses
	if _retry_btn != null:
		_retry_btn.pressed.connect(_on_retry_pressed)
	if _exit_btn != null:
		_exit_btn.pressed.connect(_on_exit_pressed)

	# Subscribe to global HealthSystem.died to open the overlay.
	if has_node("/root/HealthSystem"):
		_health_system = get_node("/root/HealthSystem")
		if _health_system.has_signal("died"):
			_health_system.connect("died", Callable(self, "_on_died"))

func _exit_tree() -> void:
	# Disconnect to avoid stale connections on reload.
	if _health_system != null:
		if _health_system.has_signal("died"):
			_health_system.disconnect("died", Callable(self, "_on_died"))
		_health_system = null

# --- Signal handlers ---

func _on_died() -> void:
	# Show overlay, block input (MouseFilter is already Stop on root Control).
	_show_overlay()

func _on_retry_pressed() -> void:
	# Reload the current Explore scene. Coil data is still in CoilSession.pending_coil.
	# This restarts the run cleanly without awarding anything.
	#get_tree().reload_current_scene()
	if has_node("/root/CoilSession"):
		get_node("/root/CoilSession").call("retry_last_coil")

func _on_exit_pressed() -> void:
	# Explicitly end the coil as a LOSS (no nutrient, no success flags).
	if has_node("/root/CoilSession"):
		get_node("/root/CoilSession").call("end_coil", false)
		return

	# Fallback if CoilSession is unavailable.
	get_tree().change_scene_to_file("res://Scenes/Heartroot/heartroot.tscn")

# --- Visual helpers ---

func _show_overlay() -> void:
	# Make visible, then optionally animate a small fade/scale for clarity.
	visible = true

	# Safety: ensure the dialog starts at normal scale before animating.
	if _dialog != null:
		_dialog.scale = Vector2(1.0, 1.0)
	if _dimmer != null:
		_dimmer.modulate.a = 0.0

	var t: Tween = create_tween()
	# Fade-in the dimmer quickly
	if _dimmer != null:
		t.tween_property(_dimmer, "modulate:a", 0.5, 0.12)
	# Subtle pop on the dialog
	if _dialog != null:
		t.tween_property(_dialog, "scale", Vector2(1.06, 1.06), 0.08)
		t.tween_property(_dialog, "scale", Vector2(1.00, 1.00), 0.10)

	# Move keyboard focus to Retry for quick Enter/Esc use
	if _retry_btn != null:
		_retry_btn.grab_focus()

## end res://Scenes/UI/lose_overlay.gd
