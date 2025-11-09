## res://System/upgrade_state.gd
## Godot 4.4.1
## Role: Global runtime view of selected upgrades for this play session.
## - Reads from ProfileManager (later). For Track 1, defaults to false.
## - ExploreMode will call load_active_loadout() at start of a run.
extends Node

# --- Signals ---
signal loadout_changed()

# --- State (explicit booleans) ---
var _hardened_skin: bool = false
var _acid_sac: bool = false
var _ghost_trail: bool = false

func _ready() -> void:
	# Keep defaults for editor runs. We will call load_active_loadout()
	# when Explore starts a run.
	pass

# For Phase 1.6:
# - Every run starts with ALL upgrades OFF.
# - We ignore any "desired_loadout" stored in profiles for now.
func load_active_loadout() -> void:
	_hardened_skin = false
	_acid_sac = false
	_ghost_trail = false
	emit_signal("loadout_changed")

# Public getters (explicit).
func has_hardened_skin() -> bool:
	return _hardened_skin

func has_acid_sac() -> bool:
	return _acid_sac

func has_ghost_trail() -> bool:
	return _ghost_trail

# Dev helper: temporary override for testing (used under GameFlags dev mode).
func set_runtime_overrides(hardened: bool, acid: bool, ghost: bool) -> void:
	_hardened_skin = hardened
	_acid_sac = acid
	_ghost_trail = ghost
	emit_signal("loadout_changed")

## end res://System/upgrade_state.gd
