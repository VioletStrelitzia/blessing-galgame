extends Control

@export var load_scene: PackedScene
@export var in_time: float = 0.5
@export var fade_in_time: float = 1.5
@export var pause_time: float = 1.5
@export var fade_out_time: float = 1.5
@export var out_time: float = 0.5
#@export var splash_screen: TextureRect
@export var splash_screen_container: Node

var load_next_flag: bool = true

var splash_screens: Array


func get_screens() -> void:
	splash_screens = splash_screen_container.get_children()
	for screen in splash_screens:
		screen.modulate.a = 0.0


func fade() -> void:
	for screen in splash_screens:
		var tween = self.create_tween()
		tween.tween_interval(in_time)
		tween.tween_property(screen, "modulate:a", 1.0, fade_in_time)
		tween.tween_interval(pause_time)
		
		if screen != splash_screens[-1]:
			tween.tween_property(screen, "modulate:a", 0.0, fade_out_time)
			tween.tween_interval(out_time)

		await tween.finished
	if load_next_flag:
		SceneManager.mount_and_unmount({
			"ui": {"主菜单": Global.scenes["主菜单"]}
		}, {
			"ui": {"启动画面": Global.scenes["启动画面"]}
		})


func _ready() -> void:
	SceneManager.pre_load({
		"ui": {"主菜单": Global.scenes["主菜单"]}
	})
	get_screens()
	fade()


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and \
		event.button_index == MOUSE_BUTTON_LEFT and \
		event.is_pressed()) or \
		event.is_action_pressed("ui_accept"):
		#get_tree().change_scene_to_packed(load_scene)
		if load_next_flag:
			SceneManager.mount_and_unmount({
				"ui": {"主菜单": Global.scenes["主菜单"]}
			}, {
				"ui": {"启动画面": Global.scenes["启动画面"]}
			}, 1, 1)
			load_next_flag = false
