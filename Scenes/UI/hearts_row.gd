## hearts_row.gd
## Godot 4.4.1
## Role: Visualize health as a row of hearts (top-left).
## - Listens to /root/HealthSystem.health_changed.
## - Shows N full hearts (active), and dims the rest (inactive).

extends HBoxContainer

@export var full_modulate: Color = Color(1, 1, 1, 1)     # normal
@export var empty_modulate: Color = Color(0.35, 0.35, 0.35, 0.9)  # dimmed

func _ready() -> void:
	# Subscribe to the global health system if present.
	if has_node("/root/HealthSystem"):
		var hs: Node = get_node("/root/HealthSystem")
		if hs.has_signal("health_changed"):
			hs.connect("health_changed", Callable(self, "_on_health_changed"))
			# Initialize immediately using current values if getters exist.
			var cur: int = 0
			var mx: int = 0
			if hs.has_method("get_current"):
				cur = int(hs.call("get_current"))
			if hs.has_method("get_max"):
				mx = int(hs.call("get_max"))
			_update_visual(cur, mx)

# Signal handler from HealthSystem.
func _on_health_changed(current: int, max: int) -> void:
	_update_visual(current, max)

# Apply tinting to children.
# Algorithm:
# - i from 0 to child_count - 1
# - If i < current: set full_modulate
# - Else: set empty_modulate
func _update_visual(current: int, max: int) -> void:
	var count: int = get_child_count()

	# Optional: if the row has fewer nodes than max, we could add more;
	# For Track 2 we simply tint what exists and ignore extra max.
	for i in range(count):
		var child := get_child(i)
		if child is CanvasItem:
			var as_item: CanvasItem = child
			if i < current:
				as_item.modulate = full_modulate
			else:
				as_item.modulate = empty_modulate

## end heartsrow.gd
