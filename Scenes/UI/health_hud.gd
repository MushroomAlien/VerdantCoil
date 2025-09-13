# res://UI/HUD/health_hud.gd
# Godot 4.4.1
# Role: Listen to HealthSystem and render heart icons for current/max.

extends CanvasLayer

@onready var hearts_row: HBoxContainer = $MarginContainer/HeartsRow

# We keep a simple cache of TextureRects for reuse.
var _heart_nodes: Array[TextureRect] = []

# Placeholder colors (filled vs empty). Replace with textures later if desired.
const COLOR_FILLED := Color(1.0, 0.3, 0.3, 1.0)  # red-ish
const COLOR_EMPTY  := Color(0.35, 0.35, 0.35, 1.0)

func _ready() -> void:
	# Subscribe to health changes immediately
	if has_node("/root/HealthSystem"):
		var hs := get_node("/root/HealthSystem")
		if hs.has_signal("health_changed"):
			hs.connect("health_changed", Callable(self, "_on_health_changed"))
		
		# Ask for current values once, so we render immediately
		if hs.has_method("get_current") and hs.has_method("get_max"):
			var c := int(hs.call("get_current"))
			var m := int(hs.call("get_max"))
			_render_hearts(c, m)

func _on_health_changed(current: int, max: int) -> void:
	_render_hearts(current, max)

func _render_hearts(current: int, max: int) -> void:
	# Safety clamps to avoid weird states
	if max < 1:
		max = 1
	if current < 0:
		current = 0
	if current > max:
		current = max
	
	# Ensure we have exactly 'max' children in the row
	var needed := max
	var have := hearts_row.get_child_count()
	
	# If we have fewer than needed, add more
	if have < needed:
		var to_add := needed - have
		var i := 0
		while i < to_add:
			var t := TextureRect.new()
			t.custom_minimum_size = Vector2(24, 24)
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			# For now we show colored squares; easy to swap for textures later.
			var bg := ColorRect.new()
			bg.color = COLOR_EMPTY
			bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bg.custom_minimum_size = Vector2(24, 24)
			# Nest the ColorRect so we can recolor it quickly
			t.add_child(bg)
			
			hearts_row.add_child(t)
			_heart_nodes.append(t)
			i += 1
	
	# If we have more than needed, remove extras from the end
	if have > needed:
		var to_remove := have - needed
		var j := 0
		while j < to_remove:
			var idx := hearts_row.get_child_count() - 1
			var node := hearts_row.get_child(idx)
			hearts_row.remove_child(node)
			node.queue_free()
			j += 1
		# Also trim our cache
		_trim_cache_to(needed)
	
	# Now color the first 'current' as filled, the rest as empty
	var k := 0
	while k < max:
		var trect := hearts_row.get_child(k)
		var bg := trect.get_child(0)
		if k < current:
			(bg as ColorRect).color = COLOR_FILLED
		else:
			(bg as ColorRect).color = COLOR_EMPTY
		k += 1

func _trim_cache_to(n: int) -> void:
	var size_now := _heart_nodes.size()
	if size_now <= n:
		return
	var pop_count := size_now - n
	var p := 0
	while p < pop_count:
		_heart_nodes.pop_back()
		p += 1
