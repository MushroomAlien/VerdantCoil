## coil_session.gd
extends Node
# Holds the coil we want to test and swaps to ExploreMode.

# Set this to your ExploreMode scene path.
@export var explore_scene_path: String = "res://Scenes/World/ExploreMode.tscn"
@export var builder_scene_path: String = "res://Scenes/BuilderMode/BuilderMode.tscn"

var pending_coil: Dictionary = {}  # the last coil handed off from Builder

func start_playtest(coil: Dictionary) -> void:
	# Store the data, then change scenes to ExporeMode.
	pending_coil = coil
	if explore_scene_path == "":
		push_error("Explore scene path is empty.")
		return
	get_tree().change_scene_to_file(explore_scene_path)

func return_to_builder() -> void:
	# Return to BuilderMode
	if builder_scene_path == "":
		push_error("CoilSession: builder_scene_path is empty.")
		return
	get_tree().change_scene_to_file(builder_scene_path)

## end coil_session.gd
