## res://System/upgrade_state.gd
## Godot 4.4.1
## Role: Global view of the upgrade loadout for the current run.
##
## Two distinct concepts live here:
##   _equipped — which upgrades are SLOTTED for this run (owned + desired in shop).
##               Populated from ProfileManager at run start. Never changes mid-run.
##   _active   — always false at run start. UpgradeController manages active state
##               in-scene; these booleans are only used by has_*() for effect queries.
##
## ExploreMode reads _equipped via is_equipped() to tell UpgradeController which
## slots are available. The crawler's UpgradeController then handles toggling.
extends Node

# --- Signals ---
signal loadout_changed()

# --- Equipped set ---
# Populated by load_active_loadout(). An upgrade is equipped if the player
# owns it AND has it in their desired_loadout in ProfileManager.
var _equipped: Dictionary = {
	"HARDENED_SKIN": false,
	"ACID_SAC":      false,
	"GHOST_TRAIL":   false,
}

# --- Active state (always starts false each run) ---
# UpgradeController is the runtime source of truth; these are legacy-compat stubs.
var _hardened_skin: bool = false
var _acid_sac: bool = false
var _ghost_trail: bool = false

func _ready() -> void:
	pass

# Reads desired_loadout ∩ owned_upgrades from ProfileManager to populate the
# equipped set. All active states are reset to false — upgrades begin inactive.
func load_active_loadout() -> void:
	# Clear everything first.
	_hardened_skin = false
	_acid_sac      = false
	_ghost_trail   = false
	_equipped = { "HARDENED_SKIN": false, "ACID_SAC": false, "GHOST_TRAIL": false }

	if not has_node("/root/ProfileManager"):
		push_error("UpgradeState: ProfileManager not found — loadout will be empty.")
		emit_signal("loadout_changed")
		return

	var pm: Node = get_node("/root/ProfileManager")

	if not pm.has_method("get_owned_upgrades") or not pm.has_method("get_desired_loadout"):
		push_error("UpgradeState: ProfileManager missing expected methods.")
		emit_signal("loadout_changed")
		return

	var owned_v: Variant  = pm.call("get_owned_upgrades")
	var desired_v: Variant = pm.call("get_desired_loadout")

	if typeof(owned_v) != TYPE_DICTIONARY or typeof(desired_v) != TYPE_DICTIONARY:
		push_error("UpgradeState: Unexpected types from ProfileManager.")
		emit_signal("loadout_changed")
		return

	var owned: Dictionary  = owned_v as Dictionary
	var desired: Dictionary = desired_v as Dictionary

	# Equipped = owned AND desired. Ghost Trail excluded until Phase 4 — even if
	# somehow present in desired_loadout it will never be equipped here.
	_equipped["HARDENED_SKIN"] = bool(owned.get("HARDENED_SKIN", false)) and bool(desired.get("HARDENED_SKIN", false))
	_equipped["ACID_SAC"]      = bool(owned.get("ACID_SAC",      false)) and bool(desired.get("ACID_SAC",      false))
	_equipped["GHOST_TRAIL"]   = false  # locked until Phase 4

	emit_signal("loadout_changed")

# --- Public: equipped queries (used by ExploreMode + UpgradeRow) ---

# True if the upgrade is slotted for this run (available to toggle in-run).
func is_equipped(key: String) -> bool:
	return bool(_equipped.get(key, false))

# --- Public: active queries (used by tile effect code via UpgradeController) ---
# These remain false at run start. In-scene, UpgradeController is the authority.

func has_hardened_skin() -> bool:
	return _hardened_skin

func has_acid_sac() -> bool:
	return _acid_sac

func has_ghost_trail() -> bool:
	return _ghost_trail

# Dev helper: force active states for testing without going through ProfileManager.
func set_runtime_overrides(hardened: bool, acid: bool, ghost: bool) -> void:
	_hardened_skin = hardened
	_acid_sac      = acid
	_ghost_trail   = ghost
	emit_signal("loadout_changed")

## end res://System/upgrade_state.gd
