class_name MusicAudioPlayerManager extends Node

@export var player_num: int = 2
@export var cur_player_index: int = 0
@export var players: Array[AudioStreamPlayer] = []

## 新增：用于存储此管理器控制的总线名称
var _bus_name: String


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_bus(bus_name: String):
	# 存储总线名称以供后续查询
	self._bus_name = bus_name
	for player in players:
		player.bus = bus_name
	GalLogger.info("音乐管理器已设置总线为: " + bus_name)


func play(
	audio: AudioStream,
	from_position: float = 0,
	fade_out_duration: float = 2.0,
	fade_in_duration: float = 2.0,
	loop: bool = true
):
	var cur_player = players[cur_player_index]
	
	# 如果请求播放的音乐和当前正在播放的相同，则不执行任何操作
	if cur_player.stream == audio and cur_player.playing:
		return

	var empty_player_index = 1 - cur_player_index
	var empty_player = players[empty_player_index]
	
	# 调用修改后的淡入函数，它将自动获取目标音量
	_fade_in_and_play(empty_player, audio, from_position, fade_in_duration, loop)
	
	# 如果当前有音乐在播放，则将其淡出
	if cur_player.playing:
		_fade_out_and_stop(cur_player, fade_out_duration)
	
	# 切换当前播放器索引
	cur_player_index = empty_player_index


# --- 以下函数保持不变 ---

func pause() -> void:
	players[cur_player_index].stream_paused = true


func resume() -> void:
	players[cur_player_index].stream_paused = false


func stop(fade_out_duration: float = 2.0):
	var cur_player = players[cur_player_index]
	if not cur_player.playing:
		return
	_fade_out_and_stop(cur_player, fade_out_duration)


func fade_quiet(
	duration: float = 1,
	end_db: float = -20 # 可以提供一个默认的“安静”值
):
	var tween = create_tween()
	tween.tween_property(players[cur_player_index], "volume_db", end_db, duration)


# =======================================================
#               !!! 核心修改区域 !!!
# =======================================================

## 音乐的淡入和播放逻辑
func _fade_in_and_play(
	player: AudioStreamPlayer,
	audio: AudioStream,
	from_position: float,
	duration: float,
	loop: bool = true
):
	# 1. 动态获取目标音量 (即 "Music" 总线的当前音量)
	var target_db: float = 0.0 # 提供一个默认值以防万一
	var bus_index = AudioServer.get_bus_index(_bus_name)
	
	if bus_index != -1:
		target_db = AudioServer.get_bus_volume_db(bus_index)
	else:
		GalLogger.warn("在音乐管理器中找不到总线: '%s'，将使用默认音量 0 dB" % _bus_name)

	# 2. 设置循环逻辑
	if loop and not player.finished.is_connected(player.play):
		player.finished.connect(player.play)
	
	player.stream = audio
	var tween = create_tween()
	
	# 3. (关键!) 在播放前，立即将音量设置为-80dB(静音)，防止声音突然爆出
	player.volume_db = -80.0
	player.play(from_position)
	
	# 4. 创建动画，将播放器音量从-80dB平滑过渡到动态获取的总线音量
	tween.tween_property(player, "volume_db", target_db, duration)


## 音乐的淡出和停止逻辑
func _fade_out_and_stop(
	player: AudioStreamPlayer,
	duration: float,
	end_db: float = -80.0 # 优化：淡出至-80dB以确保完全静音
):
	# 如果连接了循环，先断开
	if player.finished.is_connected(player.play):
		player.finished.disconnect(player.play)
		
	var tween = create_tween()
	tween.tween_property(player, "volume_db", end_db, duration)
	tween.tween_callback(player.stop)
