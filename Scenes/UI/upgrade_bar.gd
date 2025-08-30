## upgrade_bar.gd

extends Control
## Updates upgrade icons when upgrade state changes

@onready var hardened_icon: TextureButton = $IconRow/HardenedSkinIcon
@onready var acid_icon: TextureButton = $IconRow/AcidSacIcon
@onready var ghost_icon: TextureButton = $IconRow/GhostTrailIcon

func _ready() -> void:
	# Access UpgradeController through the crawler
	call_deferred("_connect_to_upgrade_controller")

func _connect_to_upgrade_controller() -> void:
	var crawler = get_tree().get_current_scene().get_node("Crawler")
	if crawler == null:
		push_error("Could not find Crawler node in current scene!")
		return
	
	var upgrades = crawler.get_node("UpgradeController")
	if upgrades == null:
		push_error("Could not find UpgradeController node in Crawler!")
		return
	
	# Connect to signal and sync UI
	upgrades.upgrade_changed.connect(_on_upgrade_changed)
	# Set icon states
	for i in upgrades.Upgrade.values():
		_on_upgrade_changed(i, upgrades.has_upgrade(i))

func _on_upgrade_changed(upgrade: int, value: bool) -> void:
	var color := Color.WHITE if value else Color.GRAY

	match upgrade:
		0: hardened_icon.modulate = color
		1: acid_icon.modulate = color
		2: ghost_icon.modulate = color

## end upgrade_bar.gd
