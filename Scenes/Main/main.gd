extends Node

@export var world2d: Node2D
@export var ui: Control
@export var transition_controller: SceneTransitionController
@export var initial_scene_path: String


func _ready() -> void:
	Global.main = self
	SceneManager.scene_managers["world2d"]["mount_point"] = world2d
	SceneManager.scene_managers["ui"]["mount_point"] = ui
	SceneManager.transition_controller = transition_controller
	GalLogger.info("加载完毕")
	SceneManager.mount_and_unmount({
		"ui": {"启动画面": initial_scene_path}
	}, {}, 0, 0, false)


func add_world_2d(child: Node2D):
	world2d.add_child(child)


func remove_world_2d(child: Node2D):
	world2d.remove_child(child)


func add_ui(child: Control):
	ui.add_child(child)


func remove_ui(child: Control):
	ui.remove_child(child)
