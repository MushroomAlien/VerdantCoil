 ## res://System/profile_manager.gd
 ## Godot 4.4.1 — Minimal Player Profile manager
 ## Strict typing, JSON stored in user://Profiles/

extends Node

signal profile_list_changed
signal current_profile_changed(profile_id: String)

const DIR_PROFILES: String = "user://Profiles"
const PATH_MANIFEST: String = "user://Profiles/manifest.json"

# --- Internal State (cached after load) ---
var _manifest: Dictionary = {}                 # {"version":1, "current_profile_id":"...", "items":[...]}
var _profiles_by_id: Dictionary = {}           # id -> Dictionary (loaded lazily when needed)

# --- Lifecycle ---
func _ready() -> void:
	# Ensure folder exists
	if DirAccess.open(DIR_PROFILES) == null:
		var err: int = DirAccess.make_dir_recursive_absolute(DIR_PROFILES)
		if err != OK:
			push_error("ProfileManager: failed to create " + DIR_PROFILES)
			return
	
	# Load or create manifest
	_manifest = _load_manifest()
	_dedupe_manifest()
	_save_manifest()
	
	# If empty, create a default profile
	var items: Array = []
	var items_v: Variant = _manifest.get("items", [])
	if typeof(items_v) == TYPE_ARRAY:
		items = items_v as Array
	
	if items.size() == 0:
		var new_id: String = _create_profile_file("Player 1")
		_append_manifest_item(new_id, "Player 1")
		_set_current_profile_id(new_id)
		_save_manifest()
	
	emit_signal("profile_list_changed")
	emit_signal("current_profile_changed", get_current_profile_id())

# --- Public API (strict typed) ---

func get_profiles() -> Array:
	# Returns a shallow copy of items from manifest
	var out: Array = []
	var items_v: Variant = _manifest.get("items", [])
	if typeof(items_v) == TYPE_ARRAY:
		var items: Array = items_v as Array
		for v in items:
			if typeof(v) == TYPE_DICTIONARY:
				out.append((v as Dictionary).duplicate(false))
	return out

func get_current_profile_id() -> String:
	var id_v: Variant = _manifest.get("current_profile_id", "")
	return String(id_v)

func get_current_profile() -> Dictionary:
	var id: String = get_current_profile_id()
	return _load_profile_file(id)

# Create a new profile, append to manifest, persist, and notify UI
func create_profile(display_name: String) -> String:
	if display_name.strip_edges() == "":
		display_name = "Player"
	var new_id: String = _create_profile_file(display_name)  # writes the profile_*.json
	_append_manifest_item(new_id, display_name)              # add one entry (no duplicates)
	_save_manifest()
	emit_signal("profile_list_changed")
	return new_id

func _create_profile_file(display_name: String) -> String:
	var id: String = _new_id()
	var now: String = _iso_timestamp()
	var data: Dictionary = {
		"id": id,
		"display_name": display_name,
		"avatar_color": "#87CEEB",
		"last_opened_coil_path": "",
		"version": 1,
		"created_at": now,
		"last_used_at": now
	}
	_save_profile_file(id, data)
	return id

func rename_profile(id: String, new_name: String) -> void:
	if id == "":
		return
	if new_name.strip_edges() == "":
		return
	
	var p: Dictionary = _load_profile_file(id)
	if p.is_empty():
		return
	
	p["display_name"] = new_name
	_save_profile_file(id, p)
	_update_manifest_name(id, new_name)
	_save_manifest()
	emit_signal("profile_list_changed")

func delete_profile(id: String) -> void:
	# Safety: cannot delete current; cannot delete last profile
	if id == "":
		return
	if id == get_current_profile_id():
		push_error("ProfileManager: cannot delete the active profile.")
		return
	
	var items: Array = get_profiles()
	if items.size() <= 1:
		push_error("ProfileManager: cannot delete the last remaining profile.")
		return
	
	# Delete file
	var path: String = _profile_path(id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	
	_remove_manifest_item(id)
	_save_manifest()
	emit_signal("profile_list_changed")

func set_current_profile(id: String) -> void:
	if id == "":
		return
	# Verify exists
	var exists: bool = _manifest_has_id(id)
	if not exists:
		return
	_set_current_profile_id(id)
	_touch_manifest_last_used(id)
	_save_manifest()
	emit_signal("current_profile_changed", id)

func update_field(id: String, key: String, value: Variant) -> void:
	if id == "":
		return
	var p: Dictionary = _load_profile_file(id)
	if p.is_empty():
		return
	p[key] = value
	_save_profile_file(id, p)
	_touch_manifest_last_used(id)
	_save_manifest()

# Convenience for current profile last_opened_coil_path
func set_current_last_opened_coil(path: String) -> void:
	var id: String = get_current_profile_id()
	if id != "":
		update_field(id, "last_opened_coil_path", path)

func get_current_last_opened_coil() -> String:
	var id: String = get_current_profile_id()
	if id == "":
		return ""
	var p: Dictionary = _load_profile_file(id)
	var v: Variant = p.get("last_opened_coil_path", "")
	return String(v)

# --- Internal helpers (typed, no ternaries) ---

func _load_manifest() -> Dictionary:
	if not FileAccess.file_exists(PATH_MANIFEST):
		var now_iso: String = _iso_timestamp()
		return {
			"version": 1,
			"current_profile_id": "",
			"items": []
		}
	
	var f: FileAccess = FileAccess.open(PATH_MANIFEST, FileAccess.READ)
	if f == null:
		return {"version": 1, "current_profile_id": "", "items": []}
	var txt: String = f.get_as_text()
	f.close()
	var parsed_v: Variant = JSON.parse_string(txt)
	if typeof(parsed_v) != TYPE_DICTIONARY:
		return {"version": 1, "current_profile_id": "", "items": []}
	return parsed_v as Dictionary

func _save_manifest() -> void:
	var f: FileAccess = FileAccess.open(PATH_MANIFEST, FileAccess.WRITE)
	if f == null:
		push_error("ProfileManager: cannot write manifest.")
		return
	f.store_string(JSON.stringify(_manifest, "\t"))
	f.close()

func _profile_path(id: String) -> String:
	return DIR_PROFILES + "/profile_" + id + ".json"

func _load_profile_file(id: String) -> Dictionary:
	if id == "":
		return {}
	var path: String = _profile_path(id)
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt: String = f.get_as_text()
	f.close()
	var parsed_v: Variant = JSON.parse_string(txt)
	if typeof(parsed_v) != TYPE_DICTIONARY:
		return {}
	return parsed_v as Dictionary

func _save_profile_file(id: String, data: Dictionary) -> void:
	var path: String = _profile_path(id)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("ProfileManager: cannot write profile " + id)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

func _append_manifest_item(id: String, display_name: String) -> void:
	var items: Array = []
	var items_v: Variant = _manifest.get("items", [])
	if typeof(items_v) == TYPE_ARRAY:
		items = items_v as Array
	var now: String = _iso_timestamp()
	var entry: Dictionary = {
		"id": id,
		"display_name": display_name,
		"created_at": now,
		"last_used_at": now
	}
	items.append(entry)
	_manifest["items"] = items

func _remove_manifest_item(id: String) -> void:
	var items: Array = []
	var items_v: Variant = _manifest.get("items", [])
	if typeof(items_v) == TYPE_ARRAY:
		items = items_v as Array
	var new_items: Array = []
	for v in items:
		if typeof(v) == TYPE_DICTIONARY:
			var d: Dictionary = v as Dictionary
			var vid: String = String(d.get("id", ""))
			if vid != id:
				new_items.append(d)
	_manifest["items"] = new_items
	# Clear current if it was pointing to this id
	var cur: String = get_current_profile_id()
	if cur == id:
		_manifest["current_profile_id"] = ""

func _update_manifest_name(id: String, new_name: String) -> void:
	var items: Array = []
	var items_v: Variant = _manifest.get("items", [])
	if typeof(items_v) == TYPE_ARRAY:
		items = items_v as Array
	for i in range(items.size()):
		var v: Variant = items[i]
		if typeof(v) == TYPE_DICTIONARY:
			var d: Dictionary = v as Dictionary
			var vid: String = String(d.get("id", ""))
			if vid == id:
				d["display_name"] = new_name
				items[i] = d
				break
	_manifest["items"] = items

func _manifest_has_id(id: String) -> bool:
	var items: Array = []
	var items_v: Variant = _manifest.get("items", [])
	if typeof(items_v) == TYPE_ARRAY:
		items = items_v as Array
	for v in items:
		if typeof(v) == TYPE_DICTIONARY:
			var d: Dictionary = v as Dictionary
			var vid: String = String(d.get("id", ""))
			if vid == id:
				return true
	return false

func _set_current_profile_id(id: String) -> void:
	_manifest["current_profile_id"] = id

func _touch_manifest_last_used(id: String) -> void:
	var items: Array = []
	var items_v: Variant = _manifest.get("items", [])
	if typeof(items_v) == TYPE_ARRAY:
		items = items_v as Array
	var now: String = _iso_timestamp()
	for i in range(items.size()):
		var v: Variant = items[i]
		if typeof(v) == TYPE_DICTIONARY:
			var d: Dictionary = v as Dictionary
			var vid: String = String(d.get("id", ""))
			if vid == id:
				d["last_used_at"] = now
				items[i] = d
				break
	_manifest["items"] = items

func _new_id() -> String:
	# Simple timestamp-based ID; good enough for local usage
	# Format: yyyymmdd_hhmmss_msec
	var dt: Dictionary = Time.get_datetime_dict_from_system(true)  # UTC
	var y: int = int(dt["year"])
	var m: int = int(dt["month"])
	var d: int = int(dt["day"])
	var hh: int = int(dt["hour"])
	var mm: int = int(dt["minute"])
	var ss: int = int(dt["second"])
	var msec: int = Time.get_ticks_msec() % 1000
	var y_s: String = str(y)
	var m_s: String = _pad2(m)
	var d_s: String = _pad2(d)
	var hh_s: String = _pad2(hh)
	var mm_s: String = _pad2(mm)
	var ss_s: String = _pad2(ss)
	var ms_s: String = str(msec)
	return y_s + m_s + d_s + "_" + hh_s + mm_s + ss_s + "_" + ms_s

func _pad2(n: int) -> String:
	if n < 10:
		return "0" + str(n)
	return str(n)

func _iso_timestamp() -> String:
	return Time.get_datetime_string_from_system(true, true)  # UTC, with separators

func _dedupe_manifest() -> void:
	var items: Array = []
	var items_v: Variant = _manifest.get("items", [])
	if typeof(items_v) == TYPE_ARRAY:
		items = items_v as Array

	var seen: Dictionary = {}
	var clean: Array = []
	for v in items:
		if typeof(v) == TYPE_DICTIONARY:
			var d: Dictionary = v as Dictionary
			var id: String = String(d.get("id", ""))
			if id != "" and not seen.has(id):
				seen[id] = true
				clean.append(d)
	_manifest["items"] = clean

## end res://System/profile_manager.gd
