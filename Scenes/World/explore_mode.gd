## explore_mode.gd
extends Node2D

@onready var crawler_scene := preload("res://Scenes/Actors/Crawler.tscn")

func _ready() -> void:
	var crawler = crawler_scene.instantiate()
	crawler.position = Grid.to_world(Vector2i(12, 23))  # Example tile position
	add_child(crawler)

## end explore_mode.gd
