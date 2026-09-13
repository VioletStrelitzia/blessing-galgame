class_name GalWorld2d extends Node2D

@export var background: Sprite2D
@export var characters: Array[Character]

func _init() -> void:
	var character_scene = load("res://Scenes/Character/character.tscn")
	characters.resize(Global.config["character"]["max"])
	
	for i in range(characters.size()):
		var character_instance = character_scene.instantiate() as Character
		characters[i] = character_instance
		characters[i].z_index = characters.size() - i
		add_child(character_instance, true)


func _ready() -> void:
	background.z_index = 0


func set_background_texture(tex: Texture):
	if background:
		background.texture = tex
