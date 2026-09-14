class_name SFXAudioPlayerManager extends Node
const LOG_TAG := "SFX"


@export var player_num: int = 6
@export var cur_player_index: int = 0
@export var players: Array[AudioStreamPlayer] = []

var _bus_name: String


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_bus(bus_name: String):
	self._bus_name = bus_name
	for player in players:
		player.bus = bus_name
	GalLogger.info(LOG_TAG, "音效管理器已设置总线为: " + bus_name)


func play(audio: AudioStream, offset: float = 0):
	var next_player_index = (cur_player_index + 1) % player_num
	var next_player = players[next_player_index]

	# 在播放前，获取 SFX 总线的当前音量并应用到播放器上
	var bus_index = AudioServer.get_bus_index(_bus_name)
	if bus_index != -1:
		next_player.volume_db = AudioServer.get_bus_volume_db(bus_index)
	else:
		# 如果总线不存在，则默认使用 0dB
		next_player.volume_db = 0.0
		GalLogger.warn(LOG_TAG, "在音效管理器中找不到总线: '%s'" % _bus_name)

	next_player.stream = audio
	next_player.play(offset)
	
	cur_player_index = next_player_index
