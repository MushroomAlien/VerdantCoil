## upgrade_controller.gd
extends Node

## Tracks and manages crawler upgrade states.
## Designed to be easily expandable in later phases.

# --- Signals ---
signal upgrade_changed(upgrade: Upgrade, value: bool)

# --- Upgrade Enum ---
enum Upgrade {
	HARDENED_SKIN,
	ACID_SAC,
	GHOST_TRAIL,
}

# --- Internal State (booleans for now) ---
var _hardened_skin: bool = false
var _acid_sac: bool = false
var _ghost_trail: bool = false

# --- Public Methods ---

# Check if a given upgrade is active
func has_upgrade(upgrade: Upgrade) -> bool:
	match upgrade:
		Upgrade.HARDENED_SKIN: return _hardened_skin
		Upgrade.ACID_SAC: return _acid_sac
		Upgrade.GHOST_TRAIL: return _ghost_trail
		_: return false

# Toggle a given upgrade's state and emit signal
func toggle_upgrade(upgrade: Upgrade) -> void:
	match upgrade:
		Upgrade.HARDENED_SKIN:
			_hardened_skin = !_hardened_skin
			emit_signal("upgrade_changed", upgrade, _hardened_skin)
			print("Hardened Skin:", _hardened_skin)
		Upgrade.ACID_SAC:
			_acid_sac = !_acid_sac
			emit_signal("upgrade_changed", upgrade, _acid_sac)
			print("Acid Sac:", _acid_sac)
		Upgrade.GHOST_TRAIL:
			_ghost_trail = !_ghost_trail
			emit_signal("upgrade_changed", upgrade, _ghost_trail)
			print("Ghost Trail:", _ghost_trail)

## end upgrade_controller.gd
