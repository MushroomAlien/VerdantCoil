## System/game_flags.gd
# Global developer flags and toggle logic (Godot 4.4.1)

extends Node

signal dev_mode_changed(enabled: bool)

var dev_mode_enabled: bool = false
var cheats_enabled: bool = false  # Master switch for all in-game cheats

var ignore_biomass_limit: bool = false

func _ready() -> void:
	# Enable dev mode automatically in the editor or if the build carries the 'dev' feature.
	dev_mode_enabled = Engine.is_editor_hint() or OS.has_feature("dev")
	emit_signal("dev_mode_changed", dev_mode_enabled)

	# Cheats are allowed in editor, or if build carries a 'cheats' feature flag.
	# In playtest/release exports we simply won't include 'cheats'.
	cheats_enabled = Engine.is_editor_hint() or OS.has_feature("cheats")

func _unhandled_input(event: InputEvent) -> void:
	# Runtime secret toggle: Ctrl+Alt+D (project action 'toggle_dev_mode')
	if event.is_action_pressed("toggle_dev_mode"):
		toggle_dev_mode()

func toggle_dev_mode() -> void:
	dev_mode_enabled = !dev_mode_enabled
	emit_signal("dev_mode_changed", dev_mode_enabled)
	print("Dev Mode:", dev_mode_enabled)

## end game_flags.gd
