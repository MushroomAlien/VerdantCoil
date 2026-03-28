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

# Reads the player's desired loadout from ProfileManager and cross-checks it
# against owned upgrades. An upgrade is only active if the player both OWNS it
# and has selected it in their desired loadout. Falls back to all-off if
# ProfileManager is unavailable (e.g. editor runs without the autoload).
func load_active_loadout() -> void:
	# Start from a clean slate.
	_hardened_skin = false
	_acid_sac = false
	_ghost_trail = false

	# Resolve ProfileManager via the safe autoload access pattern.
	if not has_node("/root/ProfileManager"):
		push_error("UpgradeState: ProfileManager not found — upgrades will default to off.")
		emit_signal("loadout_changed")
		return

	var pm: Node = get_node("/root/ProfileManager")

	if not pm.has_method("get_owned_upgrades") or not pm.has_method("get_desired_loadout"):
		push_error("UpgradeState: ProfileManager is missing expected methods.")
		emit_signal("loadout_changed")
		return

	# Fetch both dictionaries and guard their types before use.
	var owned_v: Variant = pm.call("get_owned_upgrades")
	var desired_v: Variant = pm.call("get_desired_loadout")

	if typeof(owned_v) != TYPE_DICTIONARY or typeof(desired_v) != TYPE_DICTIONARY:
		push_error("UpgradeState: Unexpected types from ProfileManager — upgrades will default to off.")
		emit_signal("loadout_changed")
		return

	var owned: Dictionary = owned_v as Dictionary
	var desired: Dictionary = desired_v as Dictionary

	# Active = owned AND in the desired loadout. Missing keys default to false.
	_hardened_skin = bool(owned.get("HARDENED_SKIN", false)) and bool(desired.get("HARDENED_SKIN", false))
	_acid_sac      = bool(owned.get("ACID_SAC",      false)) and bool(desired.get("ACID_SAC",      false))
	_ghost_trail   = bool(owned.get("GHOST_TRAIL",   false)) and bool(desired.get("GHOST_TRAIL",   false))

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
