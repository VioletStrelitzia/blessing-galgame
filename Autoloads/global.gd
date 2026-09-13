extends Node

const _config_path: String = "config.json"

## 剧本变量
var vars: Dictionary[String, float] = {}

var main: Node

var exe_dir = OS.get_executable_path().get_base_dir()

var text_interval: float = 0.05
var auto_wait_time: float = 0.5

## 配置字典
@export var config: Dictionary = {
	"logger": {  # 日志参数
		"file": "",  # 日志输出文件路径
		"level": "INFO",  # 日志输出级别
	},
	"scripts": {  # 剧本脚本参数
		"check": true,
		"read_dir": "scripts",  # 剧本读取路径
		"save_dir": "GalSs",  # 生成的 godot 剧本资产保存路径
	},
	"audio_dir": "Resources".path_join("audio"),  # 图片文件夹路径
	"image_dir": "Resources".path_join("image"),  # 图片文件夹路径
	"res_json": "index.json",  # 资源映射文件
	"mod_dir": "mods",
	"main_menu": {
		"bgm": "demo_bgm",
		"background": "Resources".path_join("image").path_join("生成电影概念图.png"),
		"title": "",
	},
	"begin_script": "",  # 起始幕
	"character": {
		"max": 4,
	},
	"dialogue_ui": {
		"wait_time_per_char": 0.05,
		"auto_wait_time": 0.5,
	},
	"initial_volume": {
		"master": 0,
		"music": 0,
		"sfx": 0,
		"voice": 0,
	},
	"save_dir": "Saves",
}

## 场景表
var scenes: Dictionary = {
	"启动画面": "res://Scenes/SplashScreen/splash_screen_manager.tscn",
	"主菜单": "res://Scenes/MainMenu/main_menu.tscn",
	"存档UI": "res://Scenes/SaveUI/save_ui.tscn",
	"设置菜单": "res://Scenes/SettingUI/setting_ui.tscn",
	"对话UI": "res://Scenes/DialogueUI/dialogue_ui.tscn",
	"GalUI": "res://Scenes/GalUI/gal_ui.tscn",
	"Gal2D": "res://Scenes/GalWorld2d/gal_world2d.tscn",
	"选择UI": "res://Scenes/OptionUI/option_ui.tscn"
}


func _ready() -> void:
	var config_json = Utils.load_json(_config_path)

	if not config_json.is_empty():
		Utils.merge_dicts(config, config_json)
		GalLogger.info("配置文件加载成功")
	
	GalLogger.set_log_file(config["logger"]["file"])
	GalLogger.set_log_level(config["logger"]["level"])

	if not config.has("begin_script") or config["begin_script"] == "":
		GalLogger.error("未设置初始幕剧本")
	
	# 应用配置中的设置
	apply_loaded_settings()


func add_var(key: String, value: float) -> void:
	vars[key] = value


func apply_loaded_settings() -> void:
	# 音量
	var initial_volume = config["initial_volume"]
	AudioServer.set_bus_volume_db(AudioManager.Bus.MASTER, initial_volume["master"])
	AudioServer.set_bus_volume_db(AudioManager.Bus.MUSIC, initial_volume["music"])
	AudioServer.set_bus_volume_db(AudioManager.Bus.SFX, initial_volume["sfx"])
	AudioServer.set_bus_volume_db(AudioManager.Bus.VOICE, initial_volume["voice"])

	# 对话
	text_interval = config["dialogue_ui"]["wait_time_per_char"]
	auto_wait_time = config["dialogue_ui"]["auto_wait_time"]
	
	GalLogger.info("设置已应用")


func save_config() -> void:
	# 从当前状态回写到 config（保存的是 dB 值）
	config["initial_volume"]["master"] = AudioServer.get_bus_volume_db(AudioManager.Bus.MASTER)
	config["initial_volume"]["music"] = AudioServer.get_bus_volume_db(AudioManager.Bus.MUSIC)
	config["initial_volume"]["sfx"] = AudioServer.get_bus_volume_db(AudioManager.Bus.SFX)
	config["initial_volume"]["voice"] = AudioServer.get_bus_volume_db(AudioManager.Bus.VOICE)
	
	config["dialogue_ui"]["wait_time_per_char"] = text_interval
	config["dialogue_ui"]["auto_wait_time"] = auto_wait_time
	
	var json_string = JSON.stringify(config, "\t")
	
	var file = FileAccess.open(_config_path, FileAccess.WRITE)
	if FileAccess.get_open_error() == OK:
		file.store_string(json_string)
		GalLogger.info("配置已保存: %s" % _config_path)
	else:
		GalLogger.error("无法写入配置文件: %s" % _config_path)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_config()
		get_tree().quit()
