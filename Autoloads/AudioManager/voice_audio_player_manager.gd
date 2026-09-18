class_name VoiceAudioPlayerManager extends Node
const LOG_TAG := "Voice"


@export var player: AudioStreamPlayer

signal voice_finished

## 进行中的淡出 Tween（重播时须终止，防止旧回调掐断新语音）
var _fade_tween: Tween


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_bus(bus_name: String):
	player.bus = bus_name
	GalLogger.info(LOG_TAG, "语音管理器已设置总线为: " + bus_name)


func play(audio: AudioStream, from_position: float = 0.0, volume: float = 1.0) -> void:
	_kill_fade_tween()
	player.stop()
	# 语音永不循环：共享缓存流可能被先前 sfx/music 的 loop:true 污染，逐次显式复位
	Utils.set_stream_loop(audio, false)
	# 播放器 volume_db 只承载曲目自身音量（线性），总线音量由总线单独衰减
	player.volume_db = linear_to_db(volume)
	player.stream = audio
	player.play(from_position)


## tween 淡出到 -80dB 后停止；fade <= 0 硬停
func stop(fade: float = 0.1) -> void:
	if not player.playing:
		return
	_kill_fade_tween()
	if fade <= 0.0:
		player.stop()
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(player, "volume_db", -80.0, fade)
	_fade_tween.tween_callback(player.stop)


func _kill_fade_tween() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


func _on_voice_player_finished() -> void:
	voice_finished.emit()
