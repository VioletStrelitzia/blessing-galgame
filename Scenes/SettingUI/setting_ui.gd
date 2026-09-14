class_name SettingUI extends Control
const LOG_TAG := "SettingUI"


@export var master_bus_slider: HSlider
@export var music_bus_slider: HSlider
@export var sfx_bus_slider: HSlider
@export var voice_bus_slider: HSlider
@export var text_interval_slider: HSlider
@export var auto_wait_time_slider: HSlider


func _ready() -> void:
	initialize_sliders()


func initialize_sliders() -> void:
	# 音量
	master_bus_slider.value = db_to_linear(AudioServer.get_bus_volume_db(AudioManager.Bus.MASTER))
	music_bus_slider.value = db_to_linear(AudioServer.get_bus_volume_db(AudioManager.Bus.MUSIC))
	sfx_bus_slider.value = db_to_linear(AudioServer.get_bus_volume_db(AudioManager.Bus.SFX))
	voice_bus_slider.value = db_to_linear(AudioServer.get_bus_volume_db(AudioManager.Bus.VOICE))
	
	# 文本/自动
	text_interval_slider.value = Global.text_interval
	auto_wait_time_slider.value = Global.auto_wait_time


func _on_master_bus_slider_value_changed(value: float) -> void:
	AudioManager.set_volume(AudioManager.Bus.MASTER, value)

func _on_music_bus_slider_value_changed(value: float) -> void:
	AudioManager.set_volume(AudioManager.Bus.MUSIC, value)

func _on_sfx_bus_slider_value_changed(value: float) -> void:
	AudioManager.set_volume(AudioManager.Bus.SFX, value)

func _on_voice_bus_slider_value_changed(value: float) -> void:
	AudioManager.set_volume(AudioManager.Bus.VOICE, value)


func _on_text_interval_slider_value_changed(value: float) -> void:
	Global.text_interval = value
	GalLogger.info(LOG_TAG, "文本间隔更新: %s" % value)

func _on_auto_wait_time_slider_value_changed(value: float) -> void:
	Global.auto_wait_time = value
	GalLogger.info(LOG_TAG, "自动等待时间更新: %s" % value)


func _on_exit_pressed() -> void:
	get_tree().paused = false
	SceneManager.unmount({"ui": {"设置菜单": Global.scenes["设置菜单"]}}, false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().paused = false
		SceneManager.unmount({"ui": {"设置菜单": Global.scenes["设置菜单"]}}, false)
