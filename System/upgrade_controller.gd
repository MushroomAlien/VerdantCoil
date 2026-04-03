## upgrade_controller.gd
extends Node

## Tracks per-run upgrade state for the Crawler.
## Two distinct concepts:
##   _equipped — which upgrades were slotted before this run (set once by ExploreMode).
##   _active   — which upgrades are currently switched ON (toggled by the player mid-run).
## An upgrade that is not equipped cannot be toggled; pressing its key does nothing.

# --- Signals ---
signal upgrade_changed(upgrade: Upgrade, value: bool)

# --- Upgrade Enum ---
enum Upgrade {
	HARDENED_SKIN,
	ACID_SAC,
	GHOST_TRAIL,
}

# --- Equipped set (populated once at run start by ExploreMode) ---
var _equipped: Dictionary = {
	"HARDENED_SKIN": false,
	"ACID_SAC":      false,
	"GHOST_TRAIL":   false,
}

# --- Active set (all start false; player toggles mid-run) ---
# Ghost Trail has no active boolean — it is a single-use action, not a toggle.
var _hardened_skin: bool = false
var _acid_sac: bool = false

func _ready() -> void:
	add_to_group("upgrade_controller")

# --- Called by ExploreMode once at run start ---
# Tells this controller which upgrades the player slotted for this run.
func set_equipped(upgrade: Upgrade, value: bool) -> void:
	match upgrade:
		Upgrade.HARDENED_SKIN: _equipped["HARDENED_SKIN"] = value
		Upgrade.ACID_SAC:      _equipped["ACID_SAC"]      = value
		Upgrade.GHOST_TRAIL:   _equipped["GHOST_TRAIL"]   = value

# --- Public: active queries ---

# True if the upgrade is currently switched ON (applying its effects this turn).
func has_upgrade(upgrade: Upgrade) -> bool:
	match upgrade:
		Upgrade.HARDENED_SKIN: return _hardened_skin
		Upgrade.ACID_SAC:      return _acid_sac
		Upgrade.GHOST_TRAIL:   return false  ## action, not a toggle; never active
		_: return false

# --- Public: equipped queries ---

# True if the upgrade was slotted before this run (available to activate).
func is_equipped(upgrade: Upgrade) -> bool:
	match upgrade:
		Upgrade.HARDENED_SKIN: return bool(_equipped.get("HARDENED_SKIN", false))
		Upgrade.ACID_SAC:      return bool(_equipped.get("ACID_SAC",      false))
		Upgrade.GHOST_TRAIL:   return bool(_equipped.get("GHOST_TRAIL",   false))
		_: return false

# Toggle a given upgrade ON/OFF.
# Silently ignored if the upgrade was not slotted for this run —
# no signal is emitted and no turn is consumed.
func toggle_upgrade(upgrade: Upgrade) -> void:
	match upgrade:
		Upgrade.HARDENED_SKIN:
			if not bool(_equipped.get("HARDENED_SKIN", false)):
				return
			_hardened_skin = !_hardened_skin
			emit_signal("upgrade_changed", upgrade, _hardened_skin)
			print("[UPGRADE] Hardened Skin:", _hardened_skin)
		Upgrade.ACID_SAC:
			if not bool(_equipped.get("ACID_SAC", false)):
				return
			_acid_sac = !_acid_sac
			emit_signal("upgrade_changed", upgrade, _acid_sac)
			print("[UPGRADE] Acid Sac:", _acid_sac)
		## Ghost Trail is handled in crawler.gd as a direct action; toggle_upgrade
		## is never called for it. No case needed here.

## end upgrade_controller.gd
