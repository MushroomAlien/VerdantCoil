## coil_session.gd
extends Node
# Holds the coil we want to test and swaps to ExploreMode.

# Set this to your ExploreMode scene path.
@export var explore_scene_path: String = "res://Scenes/World/ExploreMode.tscn"
@export var builder_scene_path: String = "res://Scenes/BuilderMode/BuilderMode.tscn"

var pending_coil: Dictionary = {}  # the last coil handed off from Builder

## Return the pending coil snapshot and clear it for the next session
func consume_pending_coil() -> Dictionary:
	var out: Dictionary = {}
	if typeof(pending_coil) == TYPE_DICTIONARY:
		# Deep-duplicate to keep the original snapshot intact if someone mutates later
		out = pending_coil.duplicate(true)
	pending_coil = {}
	print("CoilSession: consumed pending coil.")
	return out

## Start ExploreMode with an explicit snapshot (Builder hands it in)
func start_playtest(coil: Dictionary) -> void:
	pending_coil = coil
	var meta_v: Variant = coil.get("meta", {})
	var used: int = -1
	var cap: int = -1
	if typeof(meta_v) == TYPE_DICTIONARY:
		var meta: Dictionary = meta_v as Dictionary
		if meta.has("biomass_used"):
			used = int(meta["biomass_used"])
		if meta.has("biomass_cap"):
			cap = int(meta["biomass_cap"])
	print("CoilSession: start_playtest → biomass ", used, "/", cap, ".")
	if explore_scene_path == "":
		push_error("Explore scene path is empty.")
		return
	get_tree().change_scene_to_file(explore_scene_path)

## Return to BuilderMode; Builder will restore from the session snapshot
func return_to_builder() -> void:
	print("CoilSession: return_to_builder() called.")
	if builder_scene_path == "":
		push_error("CoilSession: builder_scene_path is empty.")
		return
	get_tree().change_scene_to_file(builder_scene_path)


## end coil_session.gd
