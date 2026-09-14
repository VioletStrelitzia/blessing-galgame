class_name AudioEventManager extends AudioStreamPlayer
const LOG_TAG := "VoiceEvent"


## 事件列表，每个事件都是一个字典，包含 "time" 和 "callback"
var events: Array[Dictionary] = []
## 当前待处理事件的索引
var idx := 0


@warning_ignore("unused_parameter")
func _process(delta: float) -> void:
	if not playing:
		return

	# 获取精确的当前播放时间
	var cur_time = get_playback_position() + \
		AudioServer.get_time_since_last_mix() - \
		AudioServer.get_output_latency()

	# 循环检查所有已经到时间的事件
	while idx < events.size():
		var event = events[idx]
		if cur_time >= event.time:
			# 确保回调存在且可调用，增加健壮性
			if event.has("callback") and event.callback.is_valid():
				event.callback.call()
			idx += 1
		else:
			break


## 添加事件
func add_event(time: float, callback: Callable) -> void:
	if playing:
		GalLogger.warn(LOG_TAG, "不能在播放时动态添加事件")
	else:
		events.append({"time": time, "callback": callback})


## 播放音频，并在播放前对事件进行排序
func play_with_sorted_events(offset: float = 0) -> void:
	events.sort_custom(func(a, b): return a.time < b.time)
	idx = 0
	play(offset)


## 停止播放，并执行所有尚未执行的事件；无论是否在播放都会清空事件队列
func stop_and_clear_events(execute_all: bool = true) -> void:
	if playing:
		self.stop()
		if execute_all:
			for i in range(idx, events.size()):
				var event = events[i]
				if event.has("callback") and event.callback.is_valid():
					event.callback.call()
	clear_events()


## 清空所有事件并重置索引
func clear_events() -> void:
	events.clear()
	idx = 0
