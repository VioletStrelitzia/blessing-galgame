class_name VoiceAudioPlayerManager extends Node
const LOG_TAG := "Voice"


@export var player: AudioEventManager

signal voice_finished

var _bus_name: String


func set_bus(bus_name: String):
	self._bus_name = bus_name
	player.bus = bus_name
	GalLogger.info(LOG_TAG, "语音管理器已设置总线为: " + bus_name)


func add_event(time: float, callback: Callable):
	player.add_event(time, callback)


func play(audio: AudioStream, from_position: float = 0):
	player.stop_and_clear_events(true)

	# 在播放前，获取 Voice 总线的当前音量并应用到播放器上
	var bus_index = AudioServer.get_bus_index(_bus_name)
	if bus_index != -1:
		player.volume_db = AudioServer.get_bus_volume_db(bus_index)
	else:
		# 如果总线不存在，则默认使用 0dB
		player.volume_db = 0.0
		GalLogger.warn(LOG_TAG, "在语音管理器中找不到总线: '%s'" % _bus_name)

	player.stream = audio
	player.play_with_sorted_events(from_position)


func pause() -> void:
	player.stream_paused = true


func resume() -> void:
	player.stream_paused = false


func stop(execute_all: bool = true):
	player.stop_and_clear_events(execute_all)


func _on_voice_player_finished() -> void:
	voice_finished.emit()
