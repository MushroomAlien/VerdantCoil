## coil_session.gd
extends Node
# Holds the coil we want to test and swaps to ExploreMode.

# Set this to your ExploreMode scene path.
@export var explore_scene_path: String = "res://Scenes/World/ExploreMode.tscn"
@export var builder_scene_path: String = "res://Scenes/BuilderMode/BuilderMode.tscn"
@export var heartroot_scene_path: String = "res://Scenes/Heartroot/heartroot.tscn"

var pending_coil: Dictionary = {}  # the last coil handed off from Builder
var _origin: String = "hub"   # "builder" or "hub"

### Start ExploreMode with an explicit snapshot (Builder hands it in)
func start_coil(coil: Dictionary, origin: String = "hub") -> void:
	pending_coil = coil
	_origin = origin
	
	# Check if the coil that was loaded has the correct meta data
	var meta := coil.get("meta", {}) as Dictionary
	var used := int(meta.get("biomass_used", -1))
	var cap  := int(meta.get("biomass_cap", -1))
	if used >= 0 and cap >= 0:
		print("CoilSession: start_coil → biomass ", used, "/", cap, ".")
	
	get_tree().change_scene_to_file(explore_scene_path)

func end_coil() -> void:
	# called by Explore when the run ends (win/exit)
	if has_node("/root/ProfileManager") and (_origin == "hub"):
		var pm: Node = get_node("/root/ProfileManager")
		if pm.has_method("add_nutrient"):
			var REWARD_PER_COIL: int = 1  # keep simple for 1.6(b)
			print("Added ", REWARD_PER_COIL, " nutrient on win!")
			pm.call("add_nutrient", REWARD_PER_COIL)
	
	if _origin == "builder":
		return_to_builder()
	else:
		return_to_heartroot()

# Keep older call sites working (Explore/LoseOverlay/Heartroot).
func start_playtest(coil: Dictionary, origin: String = "hub") -> void:
	start_coil(coil, origin)

func end_playtest() -> void:
	end_coil()

## Return the pending coil snapshot and clear it for the next session
func consume_pending_coil() -> Dictionary:
	var out: Dictionary = {}
	if typeof(pending_coil) == TYPE_DICTIONARY:
		# Deep-duplicate to keep the original snapshot intact if someone mutates later
		out = pending_coil.duplicate(true)
	pending_coil = {}
	print("CoilSession: consumed pending coil.")
	return out

## Return to BuilderMode; Builder will restore from the session snapshot
func return_to_builder() -> void:
	print("CoilSession: return_to_builder() called.")
	if builder_scene_path == "":
		push_error("CoilSession: builder_scene_path is empty.")
		return
	get_tree().change_scene_to_file(builder_scene_path)

func return_to_heartroot() -> void:
	print("CoilSession: return_to_heartroot() called.")
	if heartroot_scene_path == "":
		push_error("CoilSession: heartroot_scene_path is empty.")
		return
	get_tree().change_scene_to_file(heartroot_scene_path)

## end coil_session.gd
