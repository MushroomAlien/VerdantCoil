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

# --- Upgrade shop definitions ---
# Cost is in Nutrient.
const UPGRADE_DEFS: Array = [
	{ "key": "HARDENED_SKIN", "display": "Hardened Skin", "desc": "Reduces acid damage by 1 per step.", "cost": 3 },
	{ "key": "ACID_SAC",      "display": "Acid Sac",      "desc": "Digest and pass through digestible walls.", "cost": 5 },
	{ "key": "GHOST_TRAIL",   "display": "Ghost Trail",   "desc": "Leave bioluminescent spores on every tile you walk off.", "cost": 8 },
]

# --- Local state (typed) ---
var _library_items: Array = []  # Array<Dictionary> each entry mirrors manifest item
var _manifest_path: String = "user://Published/manifest.json"
var _upgrades_window: Window = null  # single instance guard

func _ready() -> void:
	# Always match SafeArea to the actual viewport size, regardless of resolution
	$UI/SafeArea.size = get_viewport_rect().size
	$UI/SafeArea.position = Vector2.ZERO
	# Wire UI signals
	create_btn.pressed.connect(_on_create_pressed)
	rename_btn.pressed.connect(_on_rename_pressed)
	delete_btn.pressed.connect(_on_delete_pressed)
	set_active_btn.pressed.connect(_on_set_active_pressed)
	profiles_list.item_activated.connect(_on_profiles_item_activated) # double-click convenience
	play_btn.pressed.connect(_on_play_pressed)
	build_btn.pressed.connect(_on_build_pressed)
	upgrades_btn.pressed.connect(_on_upgrades_pressed)
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
		cs.call("start_coil", coil, "hub")

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

# -----------------------------
# Upgrade Shop
# -----------------------------

func _on_upgrades_pressed() -> void:
	# Don't open a second window if one is already visible.
	if _upgrades_window != null and is_instance_valid(_upgrades_window):
		_upgrades_window.grab_focus()
		return

	var win: Window = Window.new()
	win.title = "Upgrades"
	win.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	win.size = Vector2i(480, 360)
	win.unresizable = true

	# Clean up the window reference when it is closed.
	win.close_requested.connect(func() -> void:
		win.queue_free()
		_upgrades_window = null
	)

	add_child(win)
	_upgrades_window = win
	_build_upgrade_content(win)
	win.popup()

# Builds (or rebuilds) the full content inside the upgrade window.
# Called on first open and after every buy/equip action.
func _build_upgrade_content(win: Window) -> void:
	# Remove any existing child nodes before rebuilding.
	for child in win.get_children():
		win.remove_child(child)
		child.queue_free()

	# Fetch current state from ProfileManager.
	var owned: Dictionary = {}
	var desired: Dictionary = {}
	var nutrient: int = 0

	if has_node("/root/ProfileManager"):
		var pm: Node = get_node("/root/ProfileManager")

		var owned_v: Variant = pm.call("get_owned_upgrades")
		if typeof(owned_v) == TYPE_DICTIONARY:
			owned = owned_v as Dictionary

		var desired_v: Variant = pm.call("get_desired_loadout")
		if typeof(desired_v) == TYPE_DICTIONARY:
			desired = desired_v as Dictionary

		var res_v: Variant = pm.call("get_resources")
		if typeof(res_v) == TYPE_DICTIONARY:
			var res: Dictionary = res_v as Dictionary
			nutrient = int(res.get("nutrient", 0))

	# Root margin so content doesn't press against the window edges.
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	win.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Nutrient balance header.
	var header: Label = Label.new()
	header.text = "Nutrient balance: %d" % nutrient
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	# One row per upgrade definition.
	for def_v in UPGRADE_DEFS:
		if typeof(def_v) != TYPE_DICTIONARY:
			continue
		var def: Dictionary = def_v as Dictionary

		var key: String       = String(def.get("key",     ""))
		var display: String   = String(def.get("display", key))
		var desc: String      = String(def.get("desc",    ""))
		var cost: int         = int(def.get("cost",       0))
		var locked: bool      = bool(def.get("locked",    false))
		var is_owned: bool    = bool(owned.get(key,       false))
		var is_desired: bool  = bool(desired.get(key,     false))

		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vbox.add_child(row)

		# Left side: name + description.
		var info: VBoxContainer = VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var name_lbl: Label = Label.new()
		name_lbl.text = display + ("  [owned]" if is_owned else "")
		info.add_child(name_lbl)

		var desc_lbl: Label = Label.new()
		desc_lbl.text = desc
		desc_lbl.modulate = Color(0.7, 0.7, 0.7, 1.0)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc_lbl)

		# Right side: action button.
		if locked:
			# Not yet implemented — show a disabled placeholder.
			var lbl: Label = Label.new()
			lbl.text = "Locked"
			lbl.modulate = Color(0.45, 0.45, 0.45, 1.0)
			row.add_child(lbl)

		elif is_owned:
			# Owned: slot or remove from the run loadout.
			var equip_btn: Button = Button.new()
			equip_btn.text = "Remove" if is_desired else "Slot"
			equip_btn.custom_minimum_size = Vector2(80, 0)
			# Capture state at build time for the closure.
			var captured_key: String = key
			var captured_desired: Dictionary = desired.duplicate()
			equip_btn.pressed.connect(func() -> void:
				_toggle_desired(captured_key, captured_desired, win)
			)
			row.add_child(equip_btn)

		else:
			# Not owned: show a buy button, disabled if insufficient funds.
			var buy_btn: Button = Button.new()
			buy_btn.text = "Buy (%d N)" % cost
			buy_btn.custom_minimum_size = Vector2(80, 0)
			buy_btn.disabled = nutrient < cost
			var captured_key: String = key
			var captured_cost: int = cost
			buy_btn.pressed.connect(func() -> void:
				_do_buy(captured_key, captured_cost, win)
			)
			row.add_child(buy_btn)

		vbox.add_child(HSeparator.new())

# Flips one upgrade in the desired loadout and persists it.
func _toggle_desired(key: String, current_desired: Dictionary, win: Window) -> void:
	if not has_node("/root/ProfileManager"):
		return
	var pm: Node = get_node("/root/ProfileManager")

	# Flip the target key; leave all others as-is.
	var new_desired: Dictionary = current_desired.duplicate()
	new_desired[key] = not bool(new_desired.get(key, false))

	pm.call("set_desired_loadout", new_desired)
	# Rebuild so the button label and state are immediately correct.
	_build_upgrade_content(win)

# Attempts to purchase an upgrade and rebuilds the window on success.
func _do_buy(key: String, cost: int, win: Window) -> void:
	if not has_node("/root/ProfileManager"):
		return
	var pm: Node = get_node("/root/ProfileManager")

	var success_v: Variant = pm.call("buy_upgrade", key, cost)
	var bought: bool = bool(success_v)

	if not bought:
		push_error("Heartroot: buy_upgrade failed for key=%s cost=%d" % [key, cost])
		return

	# Rebuild so the newly owned upgrade shows its equip button.
	_build_upgrade_content(win)

## end res://Scenes/Heartroot/Heartroot.gd
