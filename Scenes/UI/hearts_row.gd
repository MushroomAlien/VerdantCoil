## hearts_row.gd
## Godot 4.4.1
## Role: Visualize health as a row of hearts (top-left).
## - Subscribes to /root/HealthSystem.health_changed.
## - Lights the first `current` hearts; dims the rest up to `max_health`.
## - Hides any extra heart nodes beyond `max_health`.
##
## KISS principles:
## - No ternaries.
## - Explicit variables and checks.
## - Clear comments on every step.

extends HBoxContainer

@export var full_modulate: Color = Color(1, 1, 1, 1)             # Bright "full" heart
@export var empty_modulate: Color = Color(0.35, 0.35, 0.35, 0.9)  # Dim "empty" heart

# Keep a ref to HealthSystem if connected so we can disconnect cleanly
var _health_system: Node = null

func _ready() -> void:
	# Subscribe to the global HealthSystem if present.
	if has_node("/root/HealthSystem"):
		_health_system = get_node("/root/HealthSystem")
		# Connect to live updates
		if _health_system.has_signal("health_changed"):
			_health_system.connect("health_changed", Callable(self, "_on_health_changed"))
		# Initialize once from getters if available
		var current: int = 0
		var max_health: int = 0
		if _health_system.has_method("get_current"):
			var v_cur: Variant = _health_system.call("get_current")
			current = int(v_cur)
		if _health_system.has_method("get_max"):
			var v_max: Variant = _health_system.call("get_max")
			max_health = int(v_max)
		_update_visual(current, max_health)
	else:
		# No HealthSystem present: fall back to a safe default visual
		_update_visual(0, get_child_count())

func _exit_tree() -> void:
	# Disconnect to avoid stale connections if this HUD is removed/reloaded.
	if _health_system != null:
		if _health_system.has_signal("health_changed"):
			_health_system.disconnect("health_changed", Callable(self, "_on_health_changed"))
		_health_system = null

# Signal handler from HealthSystem.
func _on_health_changed(current: int, max_health: int) -> void:
	_update_visual(current, max_health)

# Applies tinting and visibility to children.
# Algorithm:
# 1) Sanitize inputs: clamp current to [0, max_health]; clamp max_health to >= 0.
# 2) For each child i:
#    - If i < max_health: child.visible = true; tint "full" if i < current else "empty".
#    - Else: child.visible = false (do not show hearts beyond the reported maximum).
func _update_visual(current: int, max_health: int) -> void:
	# --- Sanitize inputs ---
	if max_health < 0:
		max_health = 0
	if current < 0:
		current = 0
	if current > max_health:
		current = max_health

	# --- Apply to each child in order ---
	var total_children: int = get_child_count()
	var i: int = 0
	while i < total_children:
		var child: Node = get_child(i)

		# Only attempt to modulate visible nodes (CanvasItem or subclasses like TextureRect)
		if child is CanvasItem:
			var item: CanvasItem = child

			# Show only up to max_health hearts
			var within_max: bool = i < max_health
			item.visible = within_max

			if within_max:
				# Light the first `current` hearts; dim the rest up to max_health
				var is_full: bool = i < current
				if is_full:
					item.modulate = full_modulate
				else:
					item.modulate = empty_modulate
		i += 1
	# (Optional) This is a good insertion point for tiny feedback when health drops or rises.
	# For example, you could briefly scale the first changed heart.
	# We keep it out for 1.6(b) to stay KISS.

## end heartsrow.gd
