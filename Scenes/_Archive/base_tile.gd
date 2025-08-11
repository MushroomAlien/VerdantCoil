## base_tile.gd

extends Node2D
## Base class for all interactable tiles in Verdant Coil.
## Each tile type inherits from this and overrides its behavior.

# --- Tile Metadata ---
@export var tile_type: String = "Base"
@export var biomass_cost: int = 1  # Used later in Builder mode

# Group tag for lookup
func _ready() -> void:
	add_to_group("tiles")

# Called when the crawler moves onto this tile
func on_crawler_entered(crawler: Node) -> void:
	# By default, do nothing. Subclasses will override this.
	print("[BaseTile] Crawler entered a tile of type:", tile_type)

## end base_tile.gd
