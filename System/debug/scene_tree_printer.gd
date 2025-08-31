## scene_tree_printer.gd
extends Node
class_name SceneTreePrinter

# ------------------------------------------------------------------------------
# BASIC CONTROLS (turn behavior on/off and choose where we start printing)
# ------------------------------------------------------------------------------

## If true, printing happens automatically in _ready().
@export var printing_on: bool = true

## If true, start from the engine's root (/root). If false, start from this node (self).
@export var start_from_root: bool = true

## Optional: if you set this to a valid NodePath, we start from that node instead.
## This overrides start_from_root/self.
@export var start_node_path: NodePath

## Limit how deep we recurse into the tree.
## -1 = no limit. 0 = just the start node. 1 = start node and its children, etc.
@export var max_depth: int = -1

# ------------------------------------------------------------------------------
# FILTERS (leave empty to disable that filter)
# ------------------------------------------------------------------------------

## Only print node names that match this regex. Example: "^UI" prints names starting with "UI".
@export var name_regex: String = ""

## If non-empty, only nodes whose type is IN this list will be printed.
## Example: ["TileMap", "Control"].
@export var include_types: PackedStringArray = []

## If non-empty, nodes whose type is IN this list will be skipped.
## Example: ["CollisionShape2D"].
@export var exclude_types: PackedStringArray = []

# ------------------------------------------------------------------------------
# EXTRA INFO (choose what extra facts to show for each node)
# ------------------------------------------------------------------------------

## Show which groups a node belongs to (useful for debugging signal buses and filters).
@export var include_groups: bool = false

## Show the unique path to the node (e.g. /root/Main/Level/Cam).
@export var include_path: bool = false

## Show the resource path of the attached script, if any (e.g. res://player.gd).
@export var include_script_path: bool = false

## Show how many children the node has.
@export var include_children_count: bool = false

## Show the node's instance ID (helpful for correlating logs to specific nodes).
@export var include_instance_id: bool = false

# ------------------------------------------------------------------------------
# OUTPUT OPTIONS (choose where the text goes and in what order)
# ------------------------------------------------------------------------------

## If true, siblings are printed in alphabetical order by name.
@export var sort_children_by_name: bool = false

## Print to the Output console.
@export var output_to_console: bool = true

## Also write to a file under user:// (your app data directory).
@export var output_to_file: bool = false

## The file to write if output_to_file is true.
@export var output_file_path: String = "user://scene_tree.txt"

## Copy the full output to your clipboard (handy for sharing or quick pasting).
@export var copy_to_clipboard: bool = false

# ------------------------------------------------------------------------------
# INTERNALS (you normally don't need to touch these)
# ------------------------------------------------------------------------------

## We build the output as a list of lines, then join once at the end for speed.
var _lines: PackedStringArray = []

## Compiled regular expression (if name_regex is set and valid).
var _rx: RegEx

func _ready() -> void:
	# 1) Compile the regex (if one was provided). If it's invalid, we warn and ignore it.
	if name_regex.strip_edges() != "":
		_rx = RegEx.new()
		var err := _rx.compile(name_regex)
		if err != OK:
			push_warning("SceneTreePrinter: Invalid name_regex; ignoring it.")
			_rx = null

	# 2) If printing is disabled, do nothing.
	if not printing_on:
		return

	# 3) Figure out which node to start from (root, self, or a specific NodePath).
	var root := _resolve_start_node()
	if root == null:
		push_warning("SceneTreePrinter: Start node not found; nothing to print.")
		return

	# 4) Build the output lines recursively.
	_lines.clear()
	_print_node_recursive(root, 0)

	# 5) Join once and send the text wherever you asked (console, file, clipboard).
	var text := "\n".join(_lines)

	if output_to_console:
		print(text)

	if output_to_file:
		_write_to_file(text)

	if copy_to_clipboard:
		# Godot 4.x: clipboard lives on DisplayServer.
		DisplayServer.clipboard_set(text)

## Decide which node to begin from based on your export settings.
func _resolve_start_node() -> Node:
	# Highest priority: explicit NodePath, if provided and valid.
	if String(start_node_path) != "":
		if has_node(start_node_path):
			return get_node(start_node_path)
		else:
			push_warning("SceneTreePrinter: start_node_path not found in this scene.")
			return null

	# Otherwise, root or self.
	if start_from_root:
		return get_tree().root
	return self

## Recursively walk the tree and add one line per node.
## - depth: how many levels deep we are (used for indentation).
func _print_node_recursive(node: Node, depth: int) -> void:
	# Respect the depth limit, if one is set.
	if max_depth >= 0 and depth > max_depth:
		return

	# FILTER: name regex (if set). If the name doesn't match, we SKIP printing this node
	# but we STILL recurse into its children so that deeper matches aren't lost.
	if _rx and _rx.search(node.name) == null:
		for child in _get_children(node):
			_print_node_recursive(child, depth + 1)
		return

	# FILTER: include/exclude by type. We compare against get_class() (e.g. "Control", "TileMap").
	var cls := node.get_class()
	if include_types.size() > 0 and not _class_matches(cls, include_types):
		for child in _get_children(node):
			_print_node_recursive(child, depth + 1)
		return

	if exclude_types.size() > 0 and _class_matches(cls, exclude_types):
		for child in _get_children(node):
			_print_node_recursive(child, depth + 1)
		return

	# Build a single readable line for THIS node.
	var parts: PackedStringArray = []

	# Indentation visually shows the hierarchy. Each depth adds a "> ".
	parts.append("> ".repeat(depth) + node.name + " (" + cls + ")")

	# Optional extra facts (toggle in the Inspector).
	if include_children_count:
		parts.append("[children=" + str(node.get_child_count()) + "]")

	if include_instance_id:
		parts.append("[id=" + str(node.get_instance_id()) + "]")

	if include_path:
		# get_path() returns a NodePath; wrap with str() to concatenate safely.
		parts.append("[path=" + str(node.get_path()) + "]")

	if include_script_path:
		# get_script() can be null or a Variant; cast to Script for safety.
		var scr: Script = node.get_script() as Script
		if scr:
			var sp := scr.resource_path
			if sp != "":
				parts.append("[script=" + sp + "]")

	if include_groups:
		# get_groups() returns an Array of group names. Convert entries to strings and join.
		var groups_arr: Array = []
		for g in node.get_groups():
			groups_arr.append(str(g))
		if groups_arr.size() > 0:
			parts.append("[groups=" + ", ".join(groups_arr) + "]")

	# Add the final line for this node to our list.
	_lines.append(" ".join(parts))

	# Recurse into children.
	for child in _get_children(node):
		_print_node_recursive(child, depth + 1)

## Return this node's children, optionally sorted by name for stable output.
func _get_children(node: Node) -> Array:
	var children := node.get_children()  # Array[Node]
	if sort_children_by_name:
		children.sort_custom(func(a, b): return a.name < b.name)
	return children

## Check if a class name matches any name in the provided list exactly (case-sensitive).
## Tip: If you want "ancestry" matching (e.g. treat Button as Control), include both names
## in include_types, or extend this function later to walk the inheritance chain.
func _class_matches(cls: String, list: PackedStringArray) -> bool:
	for t in list:
		if cls == t:
			return true
	return false

## Write the final text to disk. Uses user:// so it works on every platform.
func _write_to_file(text: String) -> void:
	var f := FileAccess.open(output_file_path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	else:
		push_warning("SceneTreePrinter: Could not open file for writing: " + output_file_path)


## end scene_tree_printer.gd
