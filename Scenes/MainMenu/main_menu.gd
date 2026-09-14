extends Control
const LOG_TAG := "MainMenu"


@export var bgm: AudioStream
@export var background: Texture
@export var sprite2d: Sprite2D
@export var title: RichTextLabel


func _ready() -> void:
	SceneManager.pre_load({"ui": {"设置菜单": Global.scenes["设置菜单"]}})
	title.text = Global.config["main_menu"]["title"]
	bgm = ResourceManager.load("audio", Global.config["main_menu"]["bgm"])
	sprite2d.texture = ResourceManager.load(
		"texture", Global.config["main_menu"]["background"])
	AudioManager.play_music(bgm)
	$VBoxContainer/Start.grab_focus()
	GalLogger.info(LOG_TAG, "主菜单准备完毕")


func _enter_tree() -> void:
	AudioManager.play_music(bgm)
	var gal_world2d = SceneManager.get_scene("world2d", "pool", "Gal2D")
	if gal_world2d:
		gal_world2d.set_background_texture(null)


func _on_start_pressed() -> void:
	StoryManager.next_script = Global.config["begin_script"]
	StoryManager.next_story(false)
	return


func _on_exit_pressed() -> void:
	Global.save_config()
	get_tree().quit()


func _on_load_pressed() -> void:
	get_tree().paused = true
	SceneManager.mount({"ui": {"存档UI": Global.scenes["存档UI"]}})
	#var sg := load("res://Saves/save1.tres") as SavedGame
	#StoryManager.load(sg)


func _on_setting_pressed() -> void:
	get_tree().paused = true
	SceneManager.mount({"ui": {"设置菜单": Global.scenes["设置菜单"]}})
