## res://Scenes/UI/resource_counters.gd
## Godot 4.4.1
## Responsibility:
## - Display current Nutrient and Sporeprint values during Explore runs.
## - Listen to ProfileManager signals to update live.
## - Play a tiny pulse animation on gains to reinforce feedback.
##
## This script is attached to: ExploreMode/HUD/SafeArea/TopRight/ResourceCounters (HBoxContainer)
## Children are two "pill" panels with an icon and a label:
##   - NutrientPill (PanelContainer) -> NutrientRow (HBoxContainer) -> NIcon (TextureRect), NLabel (Label)
##   - SporeprintPill (PanelContainer) -> SporeRow (HBoxContainer) -> SIcon (TextureRect), SLabel (Label)

extends HBoxContainer

# --- Exported NodePaths so we do not rely on brittle string lookups ---
@export_node_path("Label") var nutrient_label_path: NodePath
@export_node_path("Label") var sporeprint_label_path: NodePath
@export_node_path("Control") var nutrient_pill_path: NodePath
@export_node_path("Control") var sporeprint_pill_path: NodePath

# --- Resolved node references (typed) ---
@onready var _nutrient_label: Label = get_node_or_null(nutrient_label_path)
@onready var _spore_label: Label = get_node_or_null(sporeprint_label_path)
@onready var _nutrient_pill: Control = get_node_or_null(nutrient_pill_path)
@onready var _spore_pill: Control = get_node_or_null(sporeprint_pill_path)

# --- Local cache so we can detect "increases" for pulse animations ---
var _last_nutrient: int = -1
var _last_sporeprint: int = -1

func _ready() -> void:
	# 1) Connect to ProfileManager signals if available
	_connect_profile_signals()

	# 2) Set initial text safely from current profile values
	_refresh_from_profile()

# Connect to signals we care about:
# - resources_changed(nutrient, sporeprint): when counters change (e.g., coil completion)
# - current_profile_changed(id): when the active profile changes
func _connect_profile_signals() -> void:
	if has_node("/root/ProfileManager"):
		var pm: Node = get_node("/root/ProfileManager")
		if pm.has_signal("resources_changed"):
			pm.connect("resources_changed", Callable(self, "_on_resources_changed"))
		if pm.has_signal("current_profile_changed"):
			pm.connect("current_profile_changed", Callable(self, "_on_profile_changed"))

# Pull values from ProfileManager once (used on _ready and when profile changes)
func _refresh_from_profile() -> void:
	var nutrient_value: int = 0
	var sporeprint_value: int = 0

	if has_node("/root/ProfileManager"):
		var pm: Node = get_node("/root/ProfileManager")
		if pm.has_method("get_resources"):
			var res_v: Variant = pm.call("get_resources")
			if typeof(res_v) == TYPE_DICTIONARY:
				var res: Dictionary = res_v as Dictionary
				var n_v: Variant = res.get("nutrient", 0)
				var s_v: Variant = res.get("sporeprint", 0)
				nutrient_value = int(n_v)
				sporeprint_value = int(s_v)

	_update_nutrient(nutrient_value)
	_update_sporeprint(sporeprint_value)

# Update the nutrient label and pulse if it increased
func _update_nutrient(value: int) -> void:
	if _nutrient_label != null:
		_nutrient_label.text = str(value)

	# Pulse only when value increases (reinforce gains, avoid distraction on non-changes)
	var should_pulse: bool = false
	if _last_nutrient >= 0:
		if value > _last_nutrient:
			should_pulse = true

	_last_nutrient = value

	if should_pulse:
		_pulse(_nutrient_pill)

# Update the sporeprint label and pulse if it increased
func _update_sporeprint(value: int) -> void:
	if _spore_label != null:
		_spore_label.text = str(value)

	var should_pulse: bool = false
	if _last_sporeprint >= 0:
		if value > _last_sporeprint:
			should_pulse = true

	_last_sporeprint = value

	if should_pulse:
		_pulse(_spore_pill)

# Tiny scale pulse to make gains feel good without covering gameplay
func _pulse(target: Control) -> void:
	if target == null:
		return
	# Reset first to avoid compounding scales when many events happen quickly
	target.scale = Vector2(1.0, 1.0)

	var t: Tween = create_tween()
	# Grow slightly, then return to 1.0
	t.tween_property(target, "scale", Vector2(1.10, 1.10), 0.08)
	t.tween_property(target, "scale", Vector2(1.00, 1.00), 0.12)

# --- Signal handlers ---

# Called whenever ProfileManager tells us the resources changed
func _on_resources_changed(nutrient: int, sporeprint: int) -> void:
	_update_nutrient(nutrient)
	_update_sporeprint(sporeprint)

# Called when current profile changes (we should re-read values)
func _on_profile_changed(_id: String) -> void:
	_refresh_from_profile()

## end res://Scenes/UI/resource_counters.gd
