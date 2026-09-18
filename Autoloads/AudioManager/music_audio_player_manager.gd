class_name MusicAudioPlayerManager extends Node
const LOG_TAG := "Music"


@export var players: Array[AudioStreamPlayer] = []

var cur_player_index: int = 0

## 各播放器进行中的淡入/淡出 Tween（复用播放器时须终止，防止旧 tween 劫持音量或回调掐断新播放）
var _fade_tweens: Dictionary = {}
## 正在淡出收尾的播放器（playing 在淡出尾巴里仍为 true；同曲守卫据此放行「stop 后同曲重开」）
var _fading_out: Dictionary = {}


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_bus(bus_name: String):
	for player in players:
		player.bus = bus_name
	GalLogger.info(LOG_TAG, "音乐管理器已设置总线为: " + bus_name)


func play(
	audio: AudioStream,
	from_position: float = 0.0,
	fade_out_duration: float = 1.0,
	fade_in_duration: float = 1.0,
	loop: bool = true,
	volume: float = 1.0
) -> void:
	var cur_player = players[cur_player_index]

	# 同曲守卫：同曲在播且不在淡出收尾中时不执行任何操作
	#（淡出尾巴里 playing 仍为 true，守卫若命中会吞掉「stop 后同曲重开」——读档/跳幕同 BGM 场景）
	if cur_player.stream == audio and cur_player.playing and not _fading_out.has(cur_player):
		return

	var empty_player_index = (cur_player_index + 1) % players.size()
	var empty_player = players[empty_player_index]

	_fade_in_and_play(empty_player, audio, from_position, fade_in_duration, loop, volume)

	# 如果当前有音乐在播放（含暂停中的轨——stream_paused 置位后 playing 读数为 false），则将其淡出
	if cur_player.playing or cur_player.stream_paused:
		_fade_out_and_stop(cur_player, fade_out_duration)

	# 切换当前播放器索引
	cur_player_index = empty_player_index


func pause() -> void:
	# 作用于全部正在发声的播放器（交叉淡变中途两台都可能在响）
	for player in players:
		if player.playing:
			player.stream_paused = true


func resume() -> void:
	# 恢复以 stream_paused 标志为准（playing 与暂停的组合语义依引擎实现有歧义，标志最可靠）
	for player in players:
		if player.stream_paused:
			player.stream_paused = false


## 调节在播音轨的响度（不重启曲目）；fade > 0 时渐变
func set_track_volume(volume: float, fade: float = 0.5) -> void:
	var cur_player = players[cur_player_index]
	# 正在淡出收尾的轨不调（否则会掐死 music stop 的淡出 tween，让该停的轨永播）
	if _fading_out.has(cur_player):
		return
	# 已停轨不调；暂停中的轨允许调（音量照常落盘）
	if not cur_player.playing and not cur_player.stream_paused:
		return
	_kill_fade_tween(cur_player)
	var target := linear_to_db(volume)
	if fade <= 0.0:
		cur_player.volume_db = target
		return
	var tween = create_tween()
	tween.tween_property(cur_player, "volume_db", target, fade)
	_fade_tweens[cur_player] = tween


func stop(fade_out_duration: float = 1.0) -> void:
	var cur_player = players[cur_player_index]
	# 暂停中的轨 playing 读数为 false，但同样需要可停（否则变僵尸占住播放器）
	if not cur_player.playing and not cur_player.stream_paused:
		return
	_fade_out_and_stop(cur_player, fade_out_duration)


## 音乐的淡入和播放逻辑
func _fade_in_and_play(
	player: AudioStreamPlayer,
	audio: AudioStream,
	from_position: float,
	duration: float,
	loop: bool,
	volume: float
) -> void:
	# 流内循环；缓存流是共享资源，逐次显式设置保证确定性（见 Utils.set_stream_loop）
	Utils.set_stream_loop(audio, loop)
	_kill_fade_tween(player)
	_fading_out.erase(player)
	player.stream = audio
	# 防御：若该播放器上次是在暂停状态下被停止，stream_paused 会残留导致新播放无声
	player.stream_paused = false

	# 播放前置静音防止声音突然爆出；淡入终点为曲目自身音量，
	# 播放器 volume_db 不再快照总线音量（消除双重衰减）
	player.volume_db = -80.0
	player.play(from_position)
	var tween = create_tween()
	tween.tween_property(player, "volume_db", linear_to_db(volume), duration)
	_fade_tweens[player] = tween


## 音乐的淡出和停止逻辑
func _fade_out_and_stop(
	player: AudioStreamPlayer,
	duration: float,
	end_db: float = -80.0 # 淡出至 -80dB 以确保完全静音
) -> void:
	_kill_fade_tween(player)
	# 暂停轨淡出前先复位暂停（淡出可闻；且不留暂停残留被 resume 误复活）
	player.stream_paused = false
	if duration <= 0.0:
		player.stop()  # fade <= 0 硬停，与 sfx/voice 同口径
		return
	_fading_out[player] = true
	var tween = create_tween()
	tween.tween_property(player, "volume_db", end_db, duration)
	tween.tween_callback(_on_fade_out_finished.bind(player))
	_fade_tweens[player] = tween


func _on_fade_out_finished(player: AudioStreamPlayer) -> void:
	player.stop()
	# 簿记自洽：自然结束的淡出在此闭环（被 kill 的 tween 不会触发本回调）
	_fading_out.erase(player)
	_fade_tweens.erase(player)


func _kill_fade_tween(player: AudioStreamPlayer) -> void:
	var tween: Tween = _fade_tweens.get(player)
	if tween and tween.is_valid():
		tween.kill()
	_fade_tweens.erase(player)
