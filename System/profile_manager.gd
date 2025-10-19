 ## res://System/profile_manager.gd
 ## Godot 4.4.1 — Minimal Player Profile manager
 ## Strict typing, JSON stored in user://Profiles/

extends Node

signal profile_list_changed
signal current_profile_changed(profile_id: String)
# --- Signals for UI to subscribe to (resource counters + upgrades panel) ---
signal resources_changed(nutrient: int, sporeprint: int)
signal upgrades_changed()

# --- Whitelist of known upgrade keys so we can validate input everywhere ---
const UPGRADE_KEYS: Array[String] = [
	"HARDENED_SKIN",
	"ACID_SAC",
	"GHOST_TRAIL"
]
const DIR_PROFILES: String = "user://Profiles"
const PATH_MANIFEST: String = "user://Profiles/manifest.json"

# --- Internal State (cached after load) ---
var _manifest: Dictionary = {}                 # {"version":1, "current_profile_id":"...", "items":[...]}

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
	# Create a brand-new profile JSON with defaulted, explicit fields.
	var id: String = _new_id()
	var now: String = _iso_timestamp()

	# --- Default resources (Phase 1.6 economy) ---
	var default_nutrient: int = 0
	var default_sporeprint: int = 0

	# --- Default upgrade ownership (none owned at start) ---
	var default_owned: Dictionary = {}
	for key in UPGRADE_KEYS:
		default_owned[key] = false

	# --- Default desired loadout (nothing active until owned + toggled) ---
	var default_loadout: Dictionary = {}
	for key in UPGRADE_KEYS:
		default_loadout[key] = false

	var data: Dictionary = {
		"id": id,
		"display_name": display_name,
		"avatar_color": "#87CEEB",
		"last_opened_coil_path": "",
		"version": 1,
		"created_at": now,
		"last_used_at": now,
		# Economy + upgrades
		"nutrient": default_nutrient,
		"sporeprint": default_sporeprint,
		"owned_upgrades": default_owned,
		"desired_loadout": default_loadout
	}

	_save_profile_file(id, data)
	return id

# --- Ensure a profile Dictionary has all new Phase 1.6 fields and valid shapes. ---
func _ensure_profile_defaults_shape(p: Dictionary) -> Dictionary:
	# Defensive clone so we do not mutate caller's reference accidentally.
	var out: Dictionary = p.duplicate(true)

	# Resources
	if not out.has("nutrient"):
		out["nutrient"] = 0
	if typeof(out["nutrient"]) != TYPE_INT:
		out["nutrient"] = int(out["nutrient"])

	if not out.has("sporeprint"):
		out["sporeprint"] = 0
	if typeof(out["sporeprint"]) != TYPE_INT:
		out["sporeprint"] = int(out["sporeprint"])

	# Ownership dictionary
	if not out.has("owned_upgrades"):
		out["owned_upgrades"] = {}
	if typeof(out["owned_upgrades"]) != TYPE_DICTIONARY:
		out["owned_upgrades"] = {}

	# Ensure all known keys exist and are boolean
	for key in UPGRADE_KEYS:
		var has_key: bool = out["owned_upgrades"].has(key)
		if not has_key:
			out["owned_upgrades"][key] = false
		else:
			var v: Variant = out["owned_upgrades"][key]
			out["owned_upgrades"][key] = bool(v)

	# Desired-loadout dictionary
	if not out.has("desired_loadout"):
		out["desired_loadout"] = {}
	if typeof(out["desired_loadout"]) != TYPE_DICTIONARY:
		out["desired_loadout"] = {}

	# Ensure all known keys exist and are boolean
	for key in UPGRADE_KEYS:
		var has_key2: bool = out["desired_loadout"].has(key)
		if not has_key2:
			out["desired_loadout"][key] = false
		else:
			var v2: Variant = out["desired_loadout"][key]
			out["desired_loadout"][key] = bool(v2)

	return out

# --- Validate a proposed loadout against ownership and known keys. ---
func _sanitize_desired_loadout(proposed: Dictionary, owned: Dictionary) -> Dictionary:
	var clean: Dictionary = {}
	for key in UPGRADE_KEYS:
		# Only known keys; value must be boolean; cannot activate if not owned.
		var wants_active: bool = false
		if proposed.has(key):
			wants_active = bool(proposed[key])
		var is_owned: bool = false
		if owned.has(key):
			is_owned = bool(owned[key])
		# Rule: cannot set active if not owned.
		if is_owned:
			clean[key] = wants_active
		else:
			clean[key] = false
	return clean

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
			"items": [],
			"created_at": now_iso
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
	# Load, then ensure new fields exist (migration), and resave if anything changed.
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

	var raw: Dictionary = parsed_v as Dictionary
	var shaped: Dictionary = _ensure_profile_defaults_shape(raw)

	# If migration added/changed fields, persist immediately for stability.
	var needs_save: bool = (JSON.stringify(raw) != JSON.stringify(shaped))
	if needs_save:
		_save_profile_file(id, shaped)

	return shaped

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

# --- Public getters for Hub/UI ---

func get_resources() -> Dictionary:
	# Returns current profile's nutrient and sporeprint in a small dictionary.
	var id: String = get_current_profile_id()
	if id == "":
		return {"nutrient": 0, "sporeprint": 0}
	var p: Dictionary = _load_profile_file(id)
	var out: Dictionary = {
		"nutrient": int(p.get("nutrient", 0)),
		"sporeprint": int(p.get("sporeprint", 0))
	}
	return out

func get_owned_upgrades() -> Dictionary:
	# Returns a shallow copy to avoid external mutation.
	var id: String = get_current_profile_id()
	if id == "":
		return {}
	var p: Dictionary = _load_profile_file(id)
	var owned: Dictionary = p.get("owned_upgrades", {})
	return owned.duplicate(true)

func get_desired_loadout() -> Dictionary:
	# Returns a shallow copy to avoid external mutation.
	var id: String = get_current_profile_id()
	if id == "":
		return {}
	var p: Dictionary = _load_profile_file(id)
	var loadout: Dictionary = p.get("desired_loadout", {})
	return loadout.duplicate(true)

func buy_upgrade(key: String, cost: int) -> bool:
	# Attempts to purchase an upgrade with Nutrient.
	# Returns true on success, false on failure (insufficient funds, invalid key, or already owned).
	var id: String = get_current_profile_id()
	if id == "":
		return false

	# Validate key
	var is_known: bool = UPGRADE_KEYS.has(key)
	if not is_known:
		push_error("ProfileManager.buy_upgrade: unknown key " + key)
		return false

	# Load and enforce defaults
	var p: Dictionary = _load_profile_file(id)
	var nutrient: int = int(p.get("nutrient", 0))
	var owned: Dictionary = p.get("owned_upgrades", {})
	var already_owned: bool = false
	if owned.has(key):
		already_owned = bool(owned[key])

	# Fail if already owned
	if already_owned:
		return false

	# Check cost
	if cost < 0:
		cost = 0
	var can_afford: bool = nutrient >= cost
	if not can_afford:
		return false

	# Deduct and set owned
	nutrient = nutrient - cost
	owned[key] = true
	p["nutrient"] = nutrient
	p["owned_upgrades"] = owned

	# Optionally: do not auto-toggle active; UI will set desired_loadout explicitly later.

	# Persist and notify
	_save_profile_file(id, p)
	_touch_manifest_last_used(id)
	_save_manifest()

	# Emit signals so Hub pills and cards can refresh
	emit_signal("resources_changed", nutrient, int(p.get("sporeprint", 0)))
	emit_signal("upgrades_changed")
	return true

func set_desired_loadout(loadout: Dictionary) -> void:
	# Saves the player's desired run-active upgrades.
	# Enforces: only known keys, booleans, and cannot set active if not owned.
	var id: String = get_current_profile_id()
	if id == "":
		return

	var p: Dictionary = _load_profile_file(id)
	var owned: Dictionary = p.get("owned_upgrades", {})
	var clean: Dictionary = _sanitize_desired_loadout(loadout, owned)

	p["desired_loadout"] = clean
	_save_profile_file(id, p)
	_touch_manifest_last_used(id)
	_save_manifest()

	emit_signal("upgrades_changed")

# --- Public: resource helpers (centralize mutations + emit) ---

func add_nutrient(delta: int) -> void:
	# Increments Nutrient by delta (clamped ≥ 0). Emits resources_changed.
	if delta == 0:
		return
	var id: String = get_current_profile_id()
	if id == "":
		return
	var p: Dictionary = _load_profile_file(id)
	var nutrient: int = int(p.get("nutrient", 0))
	var sporeprint: int = int(p.get("sporeprint", 0))

	# Clamp to avoid negative totals
	nutrient = nutrient + delta
	if nutrient < 0:
		nutrient = 0

	p["nutrient"] = nutrient
	_save_profile_file(id, p)
	_touch_manifest_last_used(id)
	_save_manifest()

	emit_signal("resources_changed", nutrient, sporeprint)

func add_sporeprint(delta: int) -> void:
	# Increments Sporeprint by delta (clamped ≥ 0). Emits resources_changed.
	if delta == 0:
		return
	var id: String = get_current_profile_id()
	if id == "":
		return
	var p: Dictionary = _load_profile_file(id)
	var nutrient: int = int(p.get("nutrient", 0))
	var sporeprint: int = int(p.get("sporeprint", 0))

	sporeprint = sporeprint + delta
	if sporeprint < 0:
		sporeprint = 0

	p["sporeprint"] = sporeprint
	_save_profile_file(id, p)
	_touch_manifest_last_used(id)
	_save_manifest()

	emit_signal("resources_changed", nutrient, sporeprint)


## end res://System/profile_manager.gd
