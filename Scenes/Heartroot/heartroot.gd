## res://Scenes/Heartroot/heartroot.gd
## Godot 4.4.1 — Main hub. Profiles + Library, launches Explore/Builder via CoilSession.
extends Control

# --- Version Displays ---
@export var version_major: int = 0
@export var version_minor: int = 1
@export var version_patch: int = 0
@export var include_build_date: bool = true   # add ".yymmdd"
@export var build_tag: String = ""            # optional "a", "b", etc.

# --- Nodes (typed, robust via %UniqueName) ---

@onready var title_label: Label   = %TitleLabel
@onready var version_label: Label = %VersionLabel

@onready var profiles_list: ItemList   = %ProfilesList
@onready var new_name: LineEdit        = %NewName
@onready var create_btn: Button        = %CreateBtn
@onready var rename_btn: Button        = %RenameBtn
@onready var delete_btn: Button        = %DeleteBtn
@onready var set_active_btn: Button    = %SetActiveBtn

@onready var play_btn: Button              = %PlayBtn
@onready var build_btn: Button             = %BuildBtn
@onready var upgrades_btn: Button          = %UpgradesBtn
@onready var refresh_library_btn: Button   = %RefreshLibraryBtn
@onready var exit_btn: Button              = %ExitBtn

@onready var mine_only_cb: CheckBox    = %MineOnly
@onready var library_list: ItemList    = %LibraryList
@onready var play_selected_btn: Button = %PlaySelectedBtn

# --- Local state (typed) ---
var _library_items: Array = []  # Array<Dictionary> each entry mirrors manifest item
var _manifest_path: String = "user://Published/manifest.json"

func _ready() -> void:
	# Wire UI signals
	create_btn.pressed.connect(_on_create_pressed)
	rename_btn.pressed.connect(_on_rename_pressed)
	delete_btn.pressed.connect(_on_delete_pressed)
	set_active_btn.pressed.connect(_on_set_active_pressed)
	profiles_list.item_activated.connect(_on_profiles_item_activated) # double-click convenience
	play_btn.pressed.connect(_on_play_pressed)
	build_btn.pressed.connect(_on_build_pressed)
	refresh_library_btn.pressed.connect(_on_refresh_library_pressed)
	exit_btn.pressed.connect(_on_exit_pressed)
	mine_only_cb.toggled.connect(func(_pressed): _refresh_library())
	library_list.item_activated.connect(_on_library_item_activated)
	play_selected_btn.pressed.connect(_on_play_selected_pressed)
	
	# If the game is running in a browser, hide the button (browsers don’t allow page exit)
	if OS.get_name() == "Web":
		exit_btn.visible = false
	
	# Subscribe to profile manager events, if present
	if has_node("/root/ProfileManager"):
		var pm: Node = get_node("/root/ProfileManager")
		if pm.has_signal("profile_list_changed"):
			pm.connect("profile_list_changed", Callable(self, "_refresh_profiles"))
		if pm.has_signal("current_profile_changed"):
			pm.connect("current_profile_changed", Callable(self, "_refresh_profiles"))
	
	_refresh_profiles()
	_refresh_library()
	_refresh_version_label()

# -----------------------------
# Profiles
# -----------------------------
func _refresh_profiles(_changed_id: String = "") -> void:
	profiles_list.clear()
	
	if not has_node("/root/ProfileManager"):
		return
	
	var pm: Node = get_node("/root/ProfileManager")
	
	var items_v: Variant = pm.call("get_profiles")
	if typeof(items_v) != TYPE_ARRAY:
		return
	var items: Array = items_v as Array
	
	var current_id_v: Variant = pm.call("get_current_profile_id")
	var current_id: String = String(current_id_v)
	
	for d_v in items:
		if typeof(d_v) != TYPE_DICTIONARY:
			continue
		
		var d: Dictionary = d_v as Dictionary
		var id: String = String(d.get("id", ""))
		var display_name: String = String(d.get("display_name", "Player"))
		var is_active: bool = (id == current_id)
		var row_text: String = display_name + "  (" + id + ")"
		if is_active:
			row_text = "★ " + row_text + "   [ACTIVE]"
		
		var row: int = profiles_list.add_item(row_text)
		profiles_list.set_item_metadata(row, id)
		
		# ←← Put your RESET lines right here (for every row)
		profiles_list.set_item_custom_bg_color(row, Color(0, 0, 0, 0))
		profiles_list.set_item_custom_fg_color(row, Color(1, 1, 1, 1))
		
		# Then, if this is the active one, override with the highlight
		if is_active:
			profiles_list.select(row)
			profiles_list.set_item_custom_bg_color(row, Color(0.18, 0.33, 0.22, 1.0))
			profiles_list.set_item_custom_fg_color(row, Color(0.9, 1.0, 0.9, 1.0))

func _selected_profile_id() -> String:
	var sel: PackedInt32Array = profiles_list.get_selected_items()
	if sel.size() == 0:
		return ""
	var idx: int = int(sel[0])
	var meta_v: Variant = profiles_list.get_item_metadata(idx)
	return String(meta_v)

func _on_create_pressed() -> void:
	if not has_node("/root/ProfileManager"):
		return
	var name_in: String = new_name.text
	var pm: Node = get_node("/root/ProfileManager")
	pm.call("create_profile", name_in)
	new_name.text = ""
	_refresh_profiles()

func _on_rename_pressed() -> void:
	if not has_node("/root/ProfileManager"):
		return
	var id: String = _selected_profile_id()
	if id == "":
		return
	var new_label: String = new_name.text
	if new_label.strip_edges() == "":
		return
	var pm: Node = get_node("/root/ProfileManager")
	pm.call("rename_profile", id, new_label)
	new_name.text = ""
	_refresh_profiles()

func _on_delete_pressed() -> void:
	if not has_node("/root/ProfileManager"):
		return
	var id: String = _selected_profile_id()
	if id == "":
		return
	var pm: Node = get_node("/root/ProfileManager")
	pm.call("delete_profile", id)
	_refresh_profiles()

func _on_set_active_pressed() -> void:
	if not has_node("/root/ProfileManager"):
		return
	var id: String = _selected_profile_id()
	if id == "":
		return
	var pm: Node = get_node("/root/ProfileManager")
	pm.call("set_current_profile", id)
	_refresh_profiles()

func _on_profiles_item_activated(_index: int) -> void:
	_on_set_active_pressed()

# -----------------------------
# Library (Published manifest)
# -----------------------------
func _refresh_library() -> void:
	library_list.clear()
	_library_items.clear()
	
	# Bail early if there’s no manifest yet.
	if not FileAccess.file_exists(_manifest_path):
		return
	
	var f: FileAccess = FileAccess.open(_manifest_path, FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	
	var parsed_v: Variant = JSON.parse_string(txt)
	if typeof(parsed_v) != TYPE_DICTIONARY:
		return
	var manifest: Dictionary = parsed_v as Dictionary
	
	var arr_v: Variant = manifest.get("items", [])
	if typeof(arr_v) != TYPE_ARRAY:
		return
	var arr: Array = arr_v as Array
	
	# --- Optional: “Mine only” filter needs the current profile id ---
	var current_id: String = ""
	if has_node("/root/ProfileManager"):
		var pm: Node = get_node("/root/ProfileManager")
		var id_v: Variant = pm.call("get_current_profile_id")
		current_id = String(id_v)
	
	# Show newest first (simple stable reverse)
	for i in range(arr.size() - 1, -1, -1):
		var it_v: Variant = arr[i]
		if typeof(it_v) == TYPE_DICTIONARY:
			var it: Dictionary = it_v as Dictionary
			
			# ---- Mine only filter (skip entries that aren’t mine) ----
			if mine_only_cb.button_pressed and current_id != "":
				var owner_id: String = String(it.get("profile_id", ""))
				if owner_id != current_id:
					continue
			# ----------------------------------------------------------
			
			_library_items.append(it)
			
			var title: String = String(it.get("title", "Untitled"))
			var path: String = String(it.get("path", ""))
			var when: String = String(it.get("published_at", ""))
			
			# --- NEW: version pulled from manifest entry (safe if missing) ---
			var ver: String = String(it.get("game_version", ""))
			# -----------------------------------------------------------------
			
			# Build the row text. Only append version if present to avoid noise
			# on older manifests that don’t have game_version yet.
			var row_text: String = title + "   —   " + when
			if ver != "":
				row_text += "   —   v " + ver
			row_text += "\n" + path
			
			var row: int = library_list.add_item(row_text)
			library_list.set_item_metadata(row, path)

func _on_refresh_library_pressed() -> void:
	_refresh_library()

func _play_coil_at_path(path: String) -> void:
	if path == "":
		return
	if not FileAccess.file_exists(path):
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	var parsed_v: Variant = JSON.parse_string(txt)
	if typeof(parsed_v) != TYPE_DICTIONARY:
		return
	var coil: Dictionary = parsed_v as Dictionary
	if has_node("/root/CoilSession"):
		var cs: Node = get_node("/root/CoilSession")
		cs.call("start_playtest", coil, "hub")

func _on_library_item_activated(index: int) -> void:
	var meta_v: Variant = library_list.get_item_metadata(index)
	var path: String = String(meta_v)
	_play_coil_at_path(path)

func _on_play_selected_pressed() -> void:
	var sel: PackedInt32Array = library_list.get_selected_items()
	if sel.size() == 0:
		return
	var idx: int = int(sel[0])
	_on_library_item_activated(idx)

# -----------------------------
# Main actions
# -----------------------------
func _on_play_pressed() -> void:
	# If a library item is selected, play that. Otherwise, try profile's last opened coil.
	var sel: PackedInt32Array = library_list.get_selected_items()
	if sel.size() > 0:
		var idx: int = int(sel[0])
		_on_library_item_activated(idx)
		return

	if has_node("/root/ProfileManager"):
		var pm: Node = get_node("/root/ProfileManager")
		var last_path: String = String(pm.call("get_current_last_opened_coil"))
		if last_path != "":
			_play_coil_at_path(last_path)

func _on_build_pressed() -> void:
	# Let CoilSession take us to Builder to keep navigation consistent
	if has_node("/root/CoilSession"):
		var cs: Node = get_node("/root/CoilSession")
		cs.call("return_to_builder")

func _refresh_version_label() -> void:
	if version_label == null:
		return
	var core: String = "%d.%d.%d" % [version_major, version_minor, version_patch]
	var text_out: String = core
	if include_build_date:
		text_out += "." + _yymmdd_today()
	if build_tag.strip_edges() != "":
		text_out += build_tag
	version_label.text = "v " + text_out

func _yymmdd_today() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system(false) # local time
	var yy: int = int(dt["year"]) % 100
	var mm: int = int(dt["month"])
	var dd: int = int(dt["day"])
	return _pad2(yy) + _pad2(mm) + _pad2(dd)

func _pad2(n: int) -> String:
	if n < 10:
		return "0" + str(n)
	return str(n)

func _on_exit_pressed() -> void:
	# In editor this stops the running game; in desktop export it quits the app.
	get_tree().quit()

## end res://Scenes/Heartroot/Heartroot.gd
