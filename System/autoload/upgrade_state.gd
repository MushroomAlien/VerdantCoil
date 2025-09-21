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

# Public API: populate from current profile (Track 5 will implement real storage).
# For Track 1, we set explicit defaults and emit a signal so listeners can react.
func load_active_loadout() -> void:
	# Populate from the ProfileManager's desired_loadout (if present).
	var use_hardened: bool = false
	var use_acid: bool = false
	var use_ghost: bool = false
	
	if has_node("/root/ProfileManager"):
		var pm: Node = get_node("/root/ProfileManager")
		if pm.has_method("get_desired_loadout"):
			var dl_v: Variant = pm.call("get_desired_loadout")
			if typeof(dl_v) == TYPE_DICTIONARY:
				var dl: Dictionary = dl_v as Dictionary
				if dl.has("HARDENED_SKIN"):
					use_hardened = bool(dl["HARDENED_SKIN"])
				if dl.has("ACID_SAC"):
					use_acid = bool(dl["ACID_SAC"])
				if dl.has("GHOST_TRAIL"):
					use_ghost = bool(dl["GHOST_TRAIL"])
	
	# Apply and notify
	_hardened_skin = use_hardened
	_acid_sac = use_acid
	_ghost_trail = use_ghost
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
