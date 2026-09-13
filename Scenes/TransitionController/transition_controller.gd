class_name SceneTransitionController extends Control

@export var background: ColorRect
@export var animation_player: AnimationPlayer

signal transition_finished

func transition(animation: String, seconds: float) -> void:
	GalLogger.info("执行 " + animation + " 切换")
	self.mouse_filter = Control.MOUSE_FILTER_STOP
	animation_player.play(animation, -1.0, 1 / seconds)
	await animation_player.animation_finished
	transition_finished.emit()
	self.mouse_filter = Control.MOUSE_FILTER_IGNORE
