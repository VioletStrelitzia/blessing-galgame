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
		background.modulate.a = 1.0


## 背景交叉淡变：旧图复制为临时节点淡出，新图淡入
func transition_background(tex: Texture, duration: float) -> void:
	if not background:
		return
	if duration <= 0.0 or background.texture == null:
		set_background_texture(tex)
		return

	var old := Sprite2D.new()
	old.texture = background.texture
	old.centered = background.centered
	old.position = background.position
	old.offset = background.offset
	old.scale = background.scale
	old.z_index = background.z_index + 1  # 旧图盖在上层淡出
	add_child(old)

	background.texture = tex
	background.modulate.a = 0.0

	var tween := create_tween().set_parallel(true)
	tween.tween_property(old, "modulate:a", 0.0, duration)
	tween.tween_property(background, "modulate:a", 1.0, duration)
	tween.finished.connect(old.queue_free)
