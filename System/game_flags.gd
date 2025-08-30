# Global developer flags and toggle logic (Godot 4.4.1)
extends Node

signal dev_mode_changed(enabled: bool)

var dev_mode_enabled: bool = false

func _ready() -> void:
	# Default ON in editor or if build has 'dev' feature; otherwise OFF.
	dev_mode_enabled = Engine.is_editor_hint() or OS.has_feature("dev")
	emit_signal("dev_mode_changed", dev_mode_enabled)

func _unhandled_input(event: InputEvent) -> void:
	# Runtime secret toggle: Ctrl+Alt+D (project action 'toggle_dev_mode')
	if event.is_action_pressed("toggle_dev_mode"):
		toggle_dev_mode()

func toggle_dev_mode() -> void:
	dev_mode_enabled = !dev_mode_enabled
	emit_signal("dev_mode_changed", dev_mode_enabled)
	print("Dev Mode:", dev_mode_enabled)
