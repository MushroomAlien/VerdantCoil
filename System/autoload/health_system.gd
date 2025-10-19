# res://System/autoload/health_system.gd
# Godot 4.4.1
# Role: Global health authority for the current run.
# - Holds current and max health.
# - Emits signals when health changes or reaches zero.
# - No UI here; HUD will subscribe later.
extends Node

# --- Signals (other nodes listen to these) ---
signal health_changed(current: int, max: int)
signal died()  # Emitted exactly once when health reaches 0 from >0.

# --- State (explicit ints; defaults are safe and small) ---
var _max_health: int = 3
var _current_health: int = 3
var _is_dead: bool = false

# Called once after autoload is ready.
func _ready() -> void:
    # Ensure internal invariants are valid at startup.
    # The HUD will query immediately, so emit a first change.
    #_emit_health_changed()
    print("health_system _ready() running...")

# Public API: reset health for a new run.
# Example: reset(3) → sets max=3, current=3, clears death flag.
func reset(max_health: int) -> void:
    if max_health < 1:
        max_health = 1  # Prevent invalid max
    _max_health = max_health
    _current_health = _max_health
    _is_dead = false
    _emit_health_changed()

# Public API: apply damage. Source is a string label for future analytics ("acid", "enemy", etc.).
# Damage cannot be negative. Health is clamped to [0, max].
func apply_damage(amount: int, _source: String = "") -> void:
    # The _source parameter is intentionally unused for now.
    # We keep it so callers can pass context (e.g., "acid", "spike") for future VFX/SFX.
    # Current logic only cares about 'amount'.
    if amount < 0:
        amount = 0
    if _is_dead:
        return  # Ignore further damage after death has occurred

    var new_value: int = _current_health - amount
    if new_value < 0:
        new_value = 0
    _current_health = new_value
    _emit_health_changed()

    # Check for death transition: not dead before, now exactly 0.
    if (not _is_dead) and _current_health == 0:
        _is_dead = true
        emit_signal("died")

# Public API: heal. Clamped to max.
func heal(amount: int) -> void:
    if amount < 0:
        amount = 0
    if _is_dead:
        return  # Dead runs cannot heal (simple rule for now)
    var new_value: int = _current_health + amount
    if new_value > _max_health:
        new_value = _max_health
    _current_health = new_value
    _emit_health_changed()

# Public API: getters (clear and explicit).
func get_current() -> int:
    return _current_health

func get_max() -> int:
    return _max_health

func is_dead() -> bool:
    return _is_dead

# Internal helper: notify listeners of a health change.
func _emit_health_changed() -> void:
    emit_signal("health_changed", _current_health, _max_health)
    print("emit_signal(\"health_changed\", _current_health, _max_health)")
    print("current_health: ", _current_health, "; max_health: ", _max_health)

# end res://System/autoload/health_system.gd
