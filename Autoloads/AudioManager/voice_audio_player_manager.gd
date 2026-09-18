class_name VoiceAudioPlayerManager extends Node
const LOG_TAG := "Voice"


@export var player: AudioStreamPlayer

signal voice_finished

## 进行中的淡出 Tween（重播时须终止，防止旧回调掐断新语音）
var _fade_tween: Tween

## 停止中标志（淡出窗口内 playing 仍为 true；AUTO 等语音播完的判定须排除此状态）
var _stopping := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_bus(bus_name: String):
	player.bus = bus_name
	GalLogger.info(LOG_TAG, "语音管理器已设置总线为: " + bus_name)


func play(audio: AudioStream, from_position: float = 0.0, volume: float = 1.0) -> void:
	_kill_fade_tween()
	_stopping = false
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
	_stopping = true
	_fade_tween = create_tween()
	_fade_tween.tween_property(player, "volume_db", -80.0, fade)
	_fade_tween.tween_callback(_on_stop_fade_finished)


## 是否在发声（淡出停止中视为不在播；stop 不触发 finished 信号，AUTO 等待不能依赖 playing 单判）
func is_playing() -> bool:
	return player.playing and not _stopping


func _kill_fade_tween() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


func _on_stop_fade_finished() -> void:
	_stopping = false
	player.stop()


func _on_voice_player_finished() -> void:
	voice_finished.emit()
