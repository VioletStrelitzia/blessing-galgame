class_name GalUI
extends Control

@export var load_button: Button
@export var save_button: Button
@export var skip_button: Button
@export var auto_button: Button

signal skip_button_pressed
signal auto_button_pressed


func _ready() -> void:
	Synchronizer.mode_changed.connect(_on_mode_changed)
	_on_mode_changed(Synchronizer.mode)


func _on_mode_changed(mode: Synchronizer.Mode) -> void:
	var is_stop := mode == Synchronizer.Mode.STOP
	skip_button.disabled = is_stop
	auto_button.disabled = is_stop
	auto_button.button_pressed = (mode == Synchronizer.Mode.AUTO)


func _on_skip_pressed() -> void:
	skip_button_pressed.emit()


func _on_auto_pressed() -> void:
	auto_button_pressed.emit()


func _on_save_pressed() -> void:
	SaveManager.save_game(-1)


func _on_load_pressed() -> void:
	get_tree().paused = true
	SceneManager.mount({"ui": {"存档UI": Global.scenes["存档UI"]}})


func _on_setting_pressed() -> void:
	get_tree().paused = true
	SceneManager.mount({"ui": {"设置菜单": Global.scenes["设置菜单"]}})


func _on_exit_pressed() -> void:
	var option_ui = SceneManager.get_scene("ui", "mounted", "选择UI")
	if option_ui:
		option_ui.canceled.emit()
	StoryManager._jump_main_menu()
