class_name SFXAudioPlayerManager extends Node
const LOG_TAG := "SFX"


@export var players: Array[AudioStreamPlayer] = []

var cur_player_index: int = 0

## 各播放器当前承载的流引用（sfx stop 按流身份匹配的元数据）
var _streams: Dictionary = {}
## 各播放器当前流的循环标志（全忙抢占策略用）
var _loops: Dictionary = {}
## 各播放器进行中的淡出 Tween（重用时须终止，防止旧回调掐断新播放）
var _fade_tweens: Dictionary = {}


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_bus(bus_name: String):
	for player in players:
		player.bus = bus_name
	GalLogger.info(LOG_TAG, "音效管理器已设置总线为: " + bus_name)


func play(audio: AudioStream, from_position: float = 0.0, volume: float = 1.0, loop: bool = false) -> void:
	var player := _pick_player()
	cur_player_index = players.find(player)
	_kill_fade_tween(player)

	# 流内循环；缓存流是共享资源，逐次显式设置保证确定性（见 Utils.set_stream_loop）
	Utils.set_stream_loop(audio, loop)
	player.stop()
	# 播放器 volume_db 只承载曲目自身音量（线性），总线音量由总线单独衰减
	player.volume_db = linear_to_db(volume)
	player.stream = audio
	_streams[player] = audio
	_loops[player] = loop
	player.play(from_position)


## 按流身份匹配停止：tween 淡出到 -80dB 后停止；fade <= 0 硬停
func stop(audio: AudioStream, fade: float = 0.3) -> void:
	for player in players:
		if player.playing and _streams.get(player) == audio:
			_fade_out_and_stop(player, fade)


## 停止全部 SFX
func stop_all(fade: float = 0.3) -> void:
	for player in players:
		if player.playing:
			_fade_out_and_stop(player, fade)


## 按流身份匹配调节在播音效响度（线性 0~1，不中断播放；环境音渐强渐弱用）
## 淡出停止中的播放器身份已被 _fade_out_and_stop 擦除，天然不被匹配（无 music 侧的 F2 类问题）
func set_volume(audio: AudioStream, volume: float, fade: float = 0.3) -> void:
	for player in players:
		if player.playing and _streams.get(player) == audio:
			_kill_fade_tween(player)
			var target := linear_to_db(volume)
			if fade <= 0.0:
				player.volume_db = target
				continue
			var tween := create_tween()
			tween.tween_property(player, "volume_db", target, fade)
			_fade_tweens[player] = tween


## 分配播放器：空闲优先；全忙时按轮询序（最老优先）先抢非循环的，最后才抢循环中的
func _pick_player() -> AudioStreamPlayer:
	for player in players:
		if not player.playing:
			return player
	for i in players.size():
		var idx := (cur_player_index + 1 + i) % players.size()
		if not _loops.get(players[idx], false):
			return players[idx]
	return players[(cur_player_index + 1) % players.size()]


func _fade_out_and_stop(player: AudioStreamPlayer, fade: float) -> void:
	_streams.erase(player)
	_loops.erase(player)
	_kill_fade_tween(player)
	if fade <= 0.0:
		player.stop()
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", -80.0, fade)
	tween.tween_callback(player.stop)
	_fade_tweens[player] = tween


func _kill_fade_tween(player: AudioStreamPlayer) -> void:
	var tween: Tween = _fade_tweens.get(player)
	if tween and tween.is_valid():
		tween.kill()
	_fade_tweens.erase(player)
