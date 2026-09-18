extends Node
const LOG_TAG := "AudioManager"


enum Bus {
	MASTER,
	MUSIC,
	SFX,
	VOICE
}

## Bus 枚举 → 总线名常量表（与 default_bus_layout.tres 一致；不再与总线索引隐式耦合）
const BUS_NAMES: Dictionary = {
	Bus.MASTER: "Master",
	Bus.MUSIC: "Music",
	Bus.SFX: "SFX",
	Bus.VOICE: "Voice",
}

## 语音播放完成（转发自 VoiceManager，为「AUTO 等语音播完」预留）
signal voice_finished

@onready var music_manager: MusicAudioPlayerManager = $MusicManager
@onready var sfx_manager: SFXAudioPlayerManager = $SFXManager
@onready var voice_manager: VoiceAudioPlayerManager = $VoiceManager


func _ready() -> void:
	# 启动断言：任一总线名解析失败说明总线布局被改，立刻暴露而非静默错位
	for bus in BUS_NAMES:
		if _bus_index(bus) == -1:
			GalLogger.error(LOG_TAG, "找不到音频总线: '%s'" % BUS_NAMES[bus])
	music_manager.set_bus(BUS_NAMES[Bus.MUSIC])
	sfx_manager.set_bus(BUS_NAMES[Bus.SFX])
	voice_manager.set_bus(BUS_NAMES[Bus.VOICE])
	voice_manager.voice_finished.connect(_on_voice_finished)
	GalLogger.info(LOG_TAG, "加载完成")


func _exit_tree() -> void:
	# 退出时立即停止所有播放并释放流引用，避免 AudioStreamPlayback 滞留到音频线程收尾之后
	for player in music_manager.players + sfx_manager.players:
		player.stop()
		player.stream = null
	voice_manager.player.stop()
	voice_manager.player.stream = null


func _on_voice_finished() -> void:
	voice_finished.emit()


func play_music(
	audio: AudioStream,
	from_position: float = 0.0,
	fade_out_duration: float = 1.0,
	fade_in_duration: float = 1.0,
	loop: bool = true,
	volume: float = 1.0
) -> void:
	music_manager.play(audio, from_position, fade_out_duration, fade_in_duration, loop, volume)


func stop_music(fade_out_duration: float = 1.0) -> void:
	music_manager.stop(fade_out_duration)


## 调节在播 BGM 的响度（线性 0~1，不重启曲目）；fade > 0 时渐变
func set_music_volume(volume: float, fade: float = 0.5) -> void:
	music_manager.set_track_volume(volume, fade)


func pause_music() -> void:
	music_manager.pause()


func resume_music() -> void:
	music_manager.resume()


func play_sfx(audio: AudioStream, from_position: float = 0.0, volume: float = 1.0, loop: bool = false) -> void:
	sfx_manager.play(audio, from_position, volume, loop)


## 按流身份匹配停止（ResourceManager 缓存保证同引用同实例）；fade <= 0 硬停
func stop_sfx(audio: AudioStream, fade: float = 0.3) -> void:
	sfx_manager.stop(audio, fade)


func stop_all_sfx(fade: float = 0.3) -> void:
	sfx_manager.stop_all(fade)


func play_voice(audio: AudioStream, from_position: float = 0.0, volume: float = 1.0) -> void:
	voice_manager.play(audio, from_position, volume)


## fade <= 0 硬停
func stop_voice(fade: float = 0.1) -> void:
	voice_manager.stop(fade)


## 设置总线音量（线性 0~1）
func set_volume(bus: Bus, volume_linear: float) -> void:
	set_volume_db(bus, linear_to_db(volume_linear))


## 设置总线音量（dB）
func set_volume_db(bus: Bus, volume_db: float) -> void:
	var bus_index := _bus_index(bus)
	if bus_index == -1:
		return
	AudioServer.set_bus_volume_db(bus_index, volume_db)


## 获取总线音量（线性 0~1）
func get_volume(bus: Bus) -> float:
	return db_to_linear(get_volume_db(bus))


## 获取总线音量（dB）
func get_volume_db(bus: Bus) -> float:
	var bus_index := _bus_index(bus)
	if bus_index == -1:
		return 0.0
	return AudioServer.get_bus_volume_db(bus_index)


## 按总线名现场解析索引（无状态，每次调用现场查询，无 autoload 顺序依赖）
func _bus_index(bus: Bus) -> int:
	return AudioServer.get_bus_index(BUS_NAMES[bus])
