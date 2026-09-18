extends Node
const LOG_TAG := "StoryManager"


@export var dialogue_ui: DialogueUI
@export var gal_ui: GalUI
@export var option_ui: OptionUI
@export var gal_world2d: GalWorld2d

enum IterateMode {
	DEFAULT,  ## 默认模式，执行碰到下一个对话停下（输出对话）
	POST_COMMAND,  ## 后指令模式，执行碰到非后指令停下
}

enum ManagerMode {
	INTERACT,
	AUTO,
	SKIP,
	STOP,
}

var manager_mode: ManagerMode = ManagerMode.INTERACT
var iterate_mode: IterateMode = IterateMode.DEFAULT
var idx := 0
var log_idx := 0

# 当前选项块的结束位置（OPTION_END 索引），-1 表示不在选项中
var current_option_end_idx: int = -1

# --- 逻辑流控制 ---
# key: 指令索引
# value: 跳转目标索引
var _jump_table: Dictionary = {}

# 逻辑层级执行状态栈，元素为是否已有分支执行
var _execution_stack: Array[bool] = []

var next_script: String
var cur_script_name: String = ""
var cur_script: GalEventItemSequence

# manager_mode 变化时发出的信号
signal manager_mode_changed(new_mode: ManagerMode)

# --- 推进控制 ---
# 解释器主循环 run_script 是同步的（无 await）：
# 执行到对白/选项/跳转/等待即返回，推进由信号与定时器驱动（见 _arm_advance_trigger）
var _waiting := false  ## 停在对白停止点（后指令已消费完），等待推进触发
var _switching := false  ## next_story 转场进行中，屏蔽输入与推进
var _option_waiting := false  ## 选项 UI 打开中
var _char_waiting := false  ## char wait:true 挂起中（等 sequence_finished）
var _wait_waiting := false  ## wait 指令挂起中（等定时器）
var _trans_waiting := false  ## trans wait:true 挂起中（等 transition_finished）
var _replay_end := -1  ## 读档 SKIP 重放的终点索引，-1 表示不在重放
var _replay_vars_snapshot: Dictionary = {}  ## 重放结束后兜底覆盖的 vars 快照

# --- 指令处理函数注册表 ---
var _instruction_handlers: Dictionary = {}


func _ready() -> void:
	SceneManager.pre_load({
		"ui": {
			"对话UI": Global.scenes["对话UI"],
			"GalUI": Global.scenes["GalUI"],
			"选择UI": Global.scenes["选择UI"],
		},
		"world2d": {"Gal2D": Global.scenes["Gal2D"]},
	})
	dialogue_ui = SceneManager.get_scene("ui", "pool", "对话UI")
	gal_ui =  SceneManager.get_scene("ui", "pool", "GalUI")
	option_ui = SceneManager.get_scene("ui", "pool", "选择UI")
	gal_world2d = SceneManager.get_scene("world2d", "pool", "Gal2D")
	next_script = Global.config["begin_script"]
	
	dialogue_ui.forward.connect(on_forward)
	dialogue_ui.fast_forward.connect(on_fast_forward)
	dialogue_ui.dialogue_finished.connect(_on_dialogue_finished)
	gal_ui.skip_button_pressed.connect(on_change_skip)
	gal_ui.auto_button_pressed.connect(on_change_auto)
	
	# 初始化指令处理函数注册表
	_instruction_handlers = {
		Instruction.Head.MUSIC_PLAY: 		_music_play,
		Instruction.Head.MUSIC_PAUSE: 		_music_pause,
		Instruction.Head.MUSIC_RESUME: 		_music_resume,
		Instruction.Head.MUSIC_STOP: 		_music_stop,
		Instruction.Head.MUSIC_VOLUME: 		_music_volume,
		Instruction.Head.VOICE_PLAY: 		_voice_play,
		Instruction.Head.VOICE_STOP: 		_voice_stop,
		Instruction.Head.SFX_PLAY: 			_sfx_play,
		Instruction.Head.SFX_STOP: 			_sfx_stop,
		Instruction.Head.SET_BACKGROUND: 	_set_background,
		Instruction.Head.CHAR_SETUP: 		_char_setup,
		Instruction.Head.CHAR_SHOW_FADE: 	_char_show_fade,
		Instruction.Head.CHAR_HIDE_FADE: 	_char_hide_fade,
		Instruction.Head.CHAR_MOVE_TO: 		_char_move_to,
		Instruction.Head.CHAR_WAIT: 		_char_wait,
		Instruction.Head.CHAR_CHANGE_TEXTURE: _char_change_texture,
		Instruction.Head.OPTION: 			_option_begin,
		Instruction.Head.OPTION_END: 		_option_end,
		Instruction.Head.VAR_SET: 			_var_set,
		Instruction.Head.VAR_ADD: 			_var_add,
		Instruction.Head.VAR_SUB: 			_var_sub,
		Instruction.Head.VAR_MUL: 			_var_mul,
		Instruction.Head.VAR_DIV: 			_var_div,
		Instruction.Head.VAR_RANDOM: 		_var_random,
		Instruction.Head.SET_BEGIN_SCRIPT: 	_set_begin_script,
		Instruction.Head.JUMP_SCRIPT:	 	_jump_script,
		Instruction.Head.JUMP_MAIN_MENU: 	_jump_main_menu,
		Instruction.Head.IF: 				_if_condition,
		Instruction.Head.ELSE_IF: 			_else_if_condition,
		Instruction.Head.ELSE: 				_else_condition,
		Instruction.Head.END_IF: 			_end_if_condition,
		Instruction.Head.WAIT: 				_wait,
		Instruction.Head.SCENE_MOUNT: 		_scene_mount,
		Instruction.Head.SCENE_UNMOUNT: 	_scene_unmount,
		Instruction.Head.TRANSITION_IN: 	_trans_in,
		Instruction.Head.TRANSITION_OUT: 	_trans_out,
	}

	dialogue_ui.anchor_triggered.connect(func(ins: Instruction): execute(ins))


func on_forward() -> void:
	match manager_mode:
		ManagerMode.STOP:
			return  # STOP 模式下屏蔽一切外部输入
		ManagerMode.INTERACT:
			_advance()
		_:
			# AUTO/SKIP 中点击：回到 INTERACT 并跳完当前打字
			_set_manager_mode(ManagerMode.INTERACT)
			dialogue_ui.skip_typing()


func on_fast_forward() -> void:
	match manager_mode:
		ManagerMode.STOP:
			return  # STOP 模式下屏蔽一切外部输入
		ManagerMode.INTERACT:
			_advance()
			dialogue_ui.skip_typing()  # 快进：推进后立即跳完新对白
		_:
			_set_manager_mode(ManagerMode.INTERACT)
			dialogue_ui.skip_typing()


func on_change_skip() -> void:
	# STOP 模式下屏蔽一切外部输入
	if manager_mode == ManagerMode.STOP:
		return
	if manager_mode == ManagerMode.SKIP:
		_set_manager_mode(ManagerMode.INTERACT)
	else:
		_set_manager_mode(ManagerMode.SKIP)
		dialogue_ui.skip_typing()  # 跳完当前打字；finished 信号会驱动后指令与续跑


func on_change_auto() -> void:
	# STOP 模式下屏蔽一切外部输入
	if manager_mode == ManagerMode.STOP:
		return
	if manager_mode == ManagerMode.AUTO:
		_set_manager_mode(ManagerMode.INTERACT)
	else:
		_set_manager_mode(ManagerMode.AUTO)


func load_script(script_name: String):
	cur_script_name = script_name
	cur_script = ResourceManager.load("script", script_name) as GalEventItemSequence
	_build_jump_table()


func _build_jump_table() -> void:
	_jump_table.clear()
	var temp_stack: Array[Array] = [] # [指令类型, 索引]
	
	for i in range(cur_script.seq.size()):
		var item = cur_script.seq[i]
		if item is Instruction:
			match item.head:
				Instruction.Head.IF:
					# 记录 IF 位置
					temp_stack.append([Instruction.Head.IF, i])
					
				Instruction.Head.ELSE_IF, Instruction.Head.ELSE:
					# 接到同一层级的下一个分支
					if temp_stack.is_empty():
						GalLogger.error(LOG_TAG, "第 %d 行发现孤立的 ELSE/ELSE_IF" % i)
						continue
					
					var last = temp_stack.back()
					_jump_table[last[1]] = i  # 上一分支失败时跳到这里
					last[1] = i               # 当前分支起点
					
				Instruction.Head.END_IF:
					if temp_stack.is_empty():
						GalLogger.error(LOG_TAG, "第 %d 行发现孤立的 END_IF" % i)
						continue
						
					var last = temp_stack.pop_back()
					# 当前分支失败时跳到 END_IF
					_jump_table[last[1]] = i


## 推进一个回合：打字中则跳完（dialogue_finished 驱动后指令与续跑），否则执行到下一停止点
func _advance() -> void:
	if _switching:
		return
	if dialogue_ui.skip_typing():
		return
	run_script()


## 同步执行剧本直到本回合停止点（对白/选项/跳转/等待）。无 await：
## 对白停止后的推进由 _arm_advance_trigger 按 manager_mode 布置
func run_script(mode: IterateMode = IterateMode.DEFAULT) -> void:
	if cur_script == null:
		return
	iterate_mode = mode
	# 挂起守卫统一复位：本次推进后由新遇到的指令重新置位
	_waiting = false
	_char_waiting = false
	_wait_waiting = false
	_trans_waiting = false
	AudioManager.stop_voice()
	for c in gal_world2d.characters:
		c.skip_all()
	while idx < cur_script.seq.size():
		var cur_item := cur_script.seq[idx]
		if log_idx != idx:
			GalLogger.debug(LOG_TAG, "执行: %s" % cur_item)
			log_idx = idx
		if _step(cur_item):
			break


## 独立指令判定（排除式：is 是子类型判定，直接 is Instruction 会吞掉子类）
func _is_independent(item: GalEventItem) -> bool:
	return item is Instruction and item is not PrevInstruction and item is not PostInstruction


## 执行单个条目，返回 true 表示本回合停止（对白展示/外部接管/模式结束）
func _step(item: GalEventItem) -> bool:
	match iterate_mode:
		IterateMode.DEFAULT:
			if item is DialogueItem:
				_show_dialogue(item)
				idx += 1
				iterate_mode = IterateMode.POST_COMMAND
				return true  # 对白停止点：等打字完成
			idx += 1
			return execute(item)
		IterateMode.POST_COMMAND:
			# 打字完成窗口：消费后指令与独立指令，遇前指令或对话停
			if item is PostInstruction or _is_independent(item):
				idx += 1
				return execute(item)
			iterate_mode = IterateMode.DEFAULT
			return true
	return false


## 打字完成（自然结束或被跳过）：消费后指令与独立指令，然后按模式安排下一次推进
func _on_dialogue_finished() -> void:
	while idx < cur_script.seq.size():
		var item := cur_script.seq[idx]
		if not (item is PostInstruction or _is_independent(item)):
			break
		if log_idx != idx:
			GalLogger.debug(LOG_TAG, "执行: %s" % item)
			log_idx = idx
		idx += 1
		if execute(item):
			return  # 选项/跳转/等待接管推进，不再布置触发器
	iterate_mode = IterateMode.DEFAULT
	_waiting = true

	# 读档重放到达存档点：交还玩家（_waiting 已在上方设置，保证模式切换能重新布置触发器）
	if _replay_end >= 0 and idx >= _replay_end:
		_replay_end = -1
		# 确定性重放结束后以快照兜底覆盖（一致时无效果，分叉时保 vars 正确）
		if not _replay_vars_snapshot.is_empty():
			Global.vars = _replay_vars_snapshot.duplicate()
			_replay_vars_snapshot = {}
		_set_manager_mode(ManagerMode.INTERACT)
		return

	_arm_advance_trigger()


## 按当前模式布置推进触发器；INTERACT 等玩家输入，STOP 由外部接管
func _arm_advance_trigger() -> void:
	match manager_mode:
		ManagerMode.AUTO:
			_schedule_advance(Global.auto_wait_time)
		ManagerMode.SKIP:
			_schedule_advance(0.0)


## 预约一次推进；触发时若已切换模式或已被推进则丢弃（一次性定时器，随树暂停）
func _schedule_advance(delay: float) -> void:
	var armed_mode := manager_mode
	get_tree().create_timer(delay, false).timeout.connect(func():
		if _waiting and manager_mode == armed_mode:
			_advance()
	, CONNECT_ONE_SHOT)


func _set_manager_mode(mode: ManagerMode) -> void:
	if manager_mode == mode:
		return
	
	manager_mode = mode
	
	# 等待中切换模式：按新模式重新布置推进触发器（旧预约触发时会被守卫丢弃）
	if _waiting:
		_arm_advance_trigger()
	
	# 同步 UI（STOP 模式禁用自动/跳过）
	if gal_ui:
		gal_ui.auto_button.button_pressed = (mode == ManagerMode.AUTO)
		var disabled := (mode == ManagerMode.STOP)
		gal_ui.skip_button.disabled = disabled
		gal_ui.auto_button.disabled = disabled
	
	manager_mode_changed.emit(mode)


func execute(ins: Instruction) -> bool:
	var handler = _instruction_handlers.get(ins.head)
	if handler is Callable:
		return handler.call(ins)
	return false


func next_story(free: bool = false) -> void:
	_switching = true
	_waiting = false
	_option_waiting = false
	_set_manager_mode(ManagerMode.INTERACT)

	# 新局新种子（load_game 路径会在转场后复位为存档种子）
	Global.rng.randomize()
	Global.rng_seed = Global.rng.seed

	if dialogue_ui.visible:
		dialogue_ui.fade_out()
	AudioManager.stop_music()
	AudioManager.stop_voice()
	# SFX 一并停掉：跳幕即重建现场，loop 环境音不跨幕泄漏（读档重放会重新执行到它）
	AudioManager.stop_all_sfx()
	await SceneManager.transition("fade_out", 1)
	SceneManager.umount_all(["ui", "world2d"], free)
	ResourceManager.clear_all_cache()

	# reset
	idx = 0
	current_option_end_idx = -1 # 切换脚本时，必须强制重置选项状态
	_execution_stack.clear() # 重置逻辑流控制状态
	dialogue_ui.clear_display()
	gal_world2d.set_background_texture(null)
	for c in gal_world2d.characters:
		c.reset([], true)  # 跳幕清理角色现场（v1 遗漏，读档路径原先是自行重置）

	SceneManager.mount({
		"ui": {
			"对话UI": Global.scenes["对话UI"],
			"GalUI": Global.scenes["GalUI"],
		},
		"world2d": {"Gal2D": Global.scenes["Gal2D"]}
	})

	load_script(next_script)
	run_script()

	await SceneManager.transition("fade_in", 1)
	_switching = false


func _music_play(ins: Instruction) -> bool:
	# 解包参数: [path: String, from: float, loop: bool, fade: float, volume: float]
	var key: String = ins.params[0] as String
	var from_position: float = ins.params[1] as float
	var loop: bool = ins.params[2] as bool
	var fade: float = ins.params[3] as float
	var volume: float = ins.params[4] as float

	var audio_stream = ResourceManager.load("audio", key)
	if audio_stream:
		AudioManager.play_music(audio_stream, from_position, fade, fade, loop, volume)
	else:
		GalLogger.error(LOG_TAG, "加载 BGM \"" + key + "\"失败")
	return false


func _music_pause(_ins: Instruction = null) -> bool:
	# 无需参数
	AudioManager.pause_music()
	return false


func _music_resume(_ins: Instruction = null) -> bool:
	# 无需参数
	AudioManager.resume_music()
	return false


func _music_stop(ins: Instruction = null) -> bool:
	# 参数: [fade: float]
	var fade := 1.0
	if ins != null:
		fade = ins.params[0] as float
	AudioManager.stop_music(fade)
	return false


## music volume <0~1> [fade:秒]：调节在播音轨响度，不重启曲目
func _music_volume(ins: Instruction) -> bool:
	# 参数: [volume: float, fade: float]
	AudioManager.set_music_volume(ins.params[0] as float, ins.params[1] as float)
	return false


func _voice_play(ins: Instruction) -> bool:
	# 解包参数: [path: String, from: float, volume: float]
	var key: String = ins.params[0] as String
	var offset: float = ins.params[1] as float
	var volume: float = ins.params[2] as float
	
	var audio_stream = ResourceManager.load("audio", key)
	if audio_stream:
		AudioManager.play_voice(audio_stream, offset, volume)
	else:
		GalLogger.error(LOG_TAG, "加载语音\"" + key + "\"失败")
	return false


func _sfx_play(ins: Instruction) -> bool:
	# 解包参数: [path: String, from: float, volume: float, loop: bool]
	var key: String = ins.params[0] as String
	var offset: float = ins.params[1] as float
	var volume: float = ins.params[2] as float
	var loop: bool = ins.params[3] as bool
	
	var audio_stream = ResourceManager.load("audio", key)
	if audio_stream:
		AudioManager.play_sfx(audio_stream, offset, volume, loop)
	else:
		GalLogger.error(LOG_TAG, "加载音效\"" + key + "\"失败")
	return false


## voice stop [fade:秒]；推进对话时的自动停止走 AudioManager.stop_voice 默认参数
func _voice_stop(ins: Instruction) -> bool:
	# 参数: [fade: float]
	AudioManager.stop_voice(ins.params[0] as float)
	return false


## sfx stop [引用] [fade:秒]；引用省略 = 停止全部。播放中的引用必然已缓存，load 命中缓存不产生新加载
func _sfx_stop(ins: Instruction) -> bool:
	# 参数: [ref: String, fade: float]
	var ref: String = ins.params[0]
	var fade: float = ins.params[1]
	if ref.is_empty():
		AudioManager.stop_all_sfx(fade)
		return false
	var audio_stream = ResourceManager.load("audio", ref)
	if audio_stream:
		AudioManager.stop_sfx(audio_stream, fade)
	else:
		GalLogger.warn(LOG_TAG, "sfx stop 引用无法解析（可能从未播放）: " + ref)
	return false


func _set_background(ins: Instruction) -> bool:
	# 解包参数: [path: String, time: float]
	var key: String = ins.params[0] as String
	var time: float = ins.params[1] as float

	var background_tex = ResourceManager.load("texture", key)
	if background_tex:
		if time > 0.0:
			gal_world2d.transition_background(background_tex, time)
		else:
			gal_world2d.set_background_texture(background_tex)
	else:
		GalLogger.error(LOG_TAG, "加载背景失败: " + key)
	return false


# --- 角色动画（直挂实例：入队 + 空闲自动播放；wait:true 挂起剧情） ---

func _char_at(char_idx: int) -> Character:
	if char_idx < 0 or char_idx >= gal_world2d.characters.size():
		GalLogger.error(LOG_TAG, "角色实例索引越界: %d（上限 %d）" % [char_idx, gal_world2d.characters.size()])
		return null
	return gal_world2d.characters[char_idx]


## 入队并自动播放；wait:true 时挂起剧情直到该实例动画序列完成
func _char_enqueue(c: Character, step: Array, wait: bool) -> bool:
	if c == null:
		return false
	c.animation_list.append(step)
	c.play()
	# SKIP/重放中不真实等待（与 skip_all/skip_typing 同哲学）
	if wait and manager_mode != ManagerMode.SKIP and _replay_end < 0:
		_char_waiting = true
		c.sequence_finished.connect(_on_char_sequence_finished, CONNECT_ONE_SHOT)
		return true
	return false


func _on_char_sequence_finished() -> void:
	if not _char_waiting:
		return
	_char_waiting = false
	run_script()


func _char_setup(ins: Instruction) -> bool:
	# 参数: [char_index: int, path: String, x: float, y: float]
	var c := _char_at(ins.params[0] as int)
	if c == null:
		return false
	var tex = ResourceManager.load("texture", ins.params[1] as String)
	if tex == null:
		GalLogger.error(LOG_TAG, "加载立绘失败: " + (ins.params[1] as String))
		return false
	return _char_enqueue(c, [
		Character.AnimationType.SETUP, tex, Vector2(ins.params[2] as float, ins.params[3] as float)
	], false)


func _char_show_fade(ins: Instruction) -> bool:
	# 参数: [char_index: int, duration: float, wait: bool]
	var c := _char_at(ins.params[0] as int)
	return _char_enqueue(c, [Character.AnimationType.SHOW_FADE, ins.params[1] as float], ins.params[2] as bool)


func _char_hide_fade(ins: Instruction) -> bool:
	var c := _char_at(ins.params[0] as int)
	return _char_enqueue(c, [Character.AnimationType.HIDE_FADE, ins.params[1] as float], ins.params[2] as bool)


func _char_move_to(ins: Instruction) -> bool:
	# 参数: [char_index: int, x: float, y: float, duration: float, wait: bool]
	var c := _char_at(ins.params[0] as int)
	return _char_enqueue(c, [
		Character.AnimationType.MOVE_TO,
		Vector2(ins.params[1] as float, ins.params[2] as float),
		ins.params[3] as float,
	], ins.params[4] as bool)


func _char_change_texture(ins: Instruction) -> bool:
	# 参数: [char_index: int, path: String]
	var c := _char_at(ins.params[0] as int)
	if c == null:
		return false
	var tex = ResourceManager.load("texture", ins.params[1] as String)
	if tex == null:
		GalLogger.error(LOG_TAG, "加载立绘失败: " + (ins.params[1] as String))
		return false
	return _char_enqueue(c, [Character.AnimationType.CHANGE_TEXTURE, tex], false)


func _char_wait(ins: Instruction) -> bool:
	# 参数: [char_index: int, duration: float]（队列内等待，仅正秒）
	var c := _char_at(ins.params[0] as int)
	return _char_enqueue(c, [Character.AnimationType.WAIT, ins.params[1] as float], false)


# --- 变量 ---

## 解析右值：数字字面量直接转换，否则按变量名查表（未定义按 0.0）
func _resolve_value(s: String) -> float:
	if s.is_valid_float():
		return s.to_float()
	return Global.vars.get(s, 0.0)


func _var_set(ins: Instruction) -> bool:
	Global.vars[ins.params[0]] = _resolve_value(ins.params[1])
	return false


func _var_add(ins: Instruction) -> bool:
	var key: String = ins.params[0]
	Global.vars[key] = Global.vars.get(key, 0.0) + _resolve_value(ins.params[1])
	return false


func _var_sub(ins: Instruction) -> bool:
	var key: String = ins.params[0]
	Global.vars[key] = Global.vars.get(key, 0.0) - _resolve_value(ins.params[1])
	return false


func _var_mul(ins: Instruction) -> bool:
	var key: String = ins.params[0]
	Global.vars[key] = Global.vars.get(key, 0.0) * _resolve_value(ins.params[1])
	return false


func _var_div(ins: Instruction) -> bool:
	var key: String = ins.params[0]
	var divisor := _resolve_value(ins.params[1])
	if is_zero_approx(divisor):
		GalLogger.warn(LOG_TAG, "var 除零，变量保持不变: " + key)
		return false
	Global.vars[key] = Global.vars.get(key, 0.0) / divisor
	return false


func _var_random(ins: Instruction) -> bool:
	# 参数: [key: String, min: float, max: float]；用 Global.rng 保证重放确定性
	Global.vars[ins.params[0]] = Global.rng.randf_range(ins.params[1] as float, ins.params[2] as float)
	return false


## 剧情显式等待；SKIP/重放中短路
func _wait(ins: Instruction) -> bool:
	var duration: float = ins.params[0] as float
	if duration <= 0.0 or manager_mode == ManagerMode.SKIP or _replay_end >= 0:
		return false
	_wait_waiting = true
	get_tree().create_timer(duration, false).timeout.connect(func():
		if _wait_waiting:
			_wait_waiting = false
			run_script()
	, CONNECT_ONE_SHOT)
	return true


# --- 场景挂载与转场（转发 SceneManager，不建平行系统） ---

func _scene_mount(ins: Instruction) -> bool:
	# 参数: [type, name, path, time, anim]
	var scene_type: String = ins.params[0]
	var scene_name: String = ins.params[1]
	var path: String = ins.params[2]
	var duration: float = ins.params[3]
	var anim: String = ins.params[4]
	if anim != "fade":
		GalLogger.warn(LOG_TAG, "scene mount 暂只支持 fade 动画，收到: " + anim)

	SceneManager.mount({scene_type: {scene_name: path}})

	# time > 0 时对挂载节点做淡入
	if duration > 0.0:
		var node := SceneManager.get_scene(scene_type, "mounted", scene_name)
		if node is CanvasItem:
			node.modulate.a = 0.0
			create_tween().tween_property(node, "modulate:a", 1.0, duration)
	return false


func _scene_unmount(ins: Instruction) -> bool:
	# 参数: [type, name, time, anim, free]
	var scene_type: String = ins.params[0]
	var scene_name: String = ins.params[1]
	var duration: float = ins.params[2]
	var anim: String = ins.params[3]
	var free: bool = ins.params[4]
	if anim != "fade":
		GalLogger.warn(LOG_TAG, "scene unmount 暂只支持 fade 动画，收到: " + anim)

	var node := SceneManager.get_scene(scene_type, "mounted", scene_name)
	if duration > 0.0 and node is CanvasItem:
		# 先淡出，完成后卸载
		var tween := create_tween()
		tween.tween_property(node, "modulate:a", 0.0, duration)
		tween.finished.connect(func():
			SceneManager.unmount({scene_type: {scene_name: ""}}, free)
		, CONNECT_ONE_SHOT)
	else:
		SceneManager.unmount({scene_type: {scene_name: ""}}, free)
	return false


func _trans_in(ins: Instruction) -> bool:
	return _do_transition(ins)


func _trans_out(ins: Instruction) -> bool:
	return _do_transition(ins)


## 参数: [duration, anim, wait]；wait:true 挂起剧情直到转场完成
func _do_transition(ins: Instruction) -> bool:
	var duration: float = ins.params[0] as float
	var anim: String = ins.params[1] as String
	var wait: bool = ins.params[2] as bool

	# SKIP/重放中不真实转场
	if manager_mode == ManagerMode.SKIP or _replay_end >= 0:
		return false

	if not is_instance_valid(SceneManager.transition_controller):
		# 无转场控制器（如 headless 测试环境）：警告且绝不挂起，防死锁
		GalLogger.warn(LOG_TAG, "trans 指令无转场控制器可用，跳过: " + anim)
		return false

	if wait:
		_trans_waiting = true
		SceneManager.transition_controller.transition_finished.connect(_on_trans_finished, CONNECT_ONE_SHOT)
		SceneManager.transition(anim, duration)
		return true
	SceneManager.transition(anim, duration)
	return false


func _on_trans_finished() -> void:
	if not _trans_waiting:
		return
	_trans_waiting = false
	run_script()


func _set_begin_script(ins: Instruction) -> bool:
	# 参数: [script_name: String]
	var begin_script: String = ins.params[0] as String
	
	Global.config["begin_script"] = begin_script
	return false


func _option_begin(ins: Instruction) -> bool:
	# 参数: [text: String, cond_key/op/value: String]
	# 如果已经在本组选项中（current_option_end_idx 有效），并且还没走到 END，
	# 说明当前是在其他分支里再次遇到 OPTION，直接跳到本组选项尾部
	if current_option_end_idx != -1 and idx < current_option_end_idx:
		idx = current_option_end_idx
		# 此时 idx 指向 OPTION_END
		# run_script 下一次循环会处理 OPTION_END，从而重置状态并继续往下
		return false

	# 扫描本组选项（含当前 OPTION 自身；带条件的选项求值过滤）
	var options_text: PackedStringArray = []
	var options_indices: Array[int] = []
	var scan_idx := idx - 1  # handler 调用前 _step 已 idx += 1，回指当前 OPTION

	while scan_idx < cur_script.seq.size():
		var item := cur_script.seq[scan_idx]
		if item is Instruction:
			if item.head == Instruction.Head.OPTION_END:
				# 找到了当前这组选项的最终结束点，记录下来！
				current_option_end_idx = scan_idx
				# 这里不 +1，因为我们要跳到 OPTION_END 本身，让它去执行重置逻辑
				break

			if item.head == Instruction.Head.OPTION and _option_condition_passed(item):
				options_text.append(item.params[0])
				options_indices.append(scan_idx + 1)
		scan_idx += 1

	# 没找到 OPTION_END 时给出提示
	if current_option_end_idx == -1:
		GalLogger.warn(LOG_TAG, "未找到 OPTION_END，选项逻辑可能出错")

	# 空选项组防护（条件过滤后无存活选项）：跳过整组，不弹 UI
	if options_text.is_empty():
		GalLogger.warn(LOG_TAG, "选项组条件过滤后为空，跳过整组")
		if current_option_end_idx != -1:
			idx = current_option_end_idx
		return false

	# 对话框淡出完成后再弹出选项（信号串联，不挂起协程）
	dialogue_ui.fade_out().finished.connect(func():
		SceneManager.mount({
			"ui": {"选择UI": Global.scenes["选择UI"]}
		})
		option_ui.show_options(options_text)
	, CONNECT_ONE_SHOT)
	_set_manager_mode(ManagerMode.INTERACT)

	# 等待玩家选择 / 取消（取消来自读档等外部流程）
	_option_waiting = true
	option_ui.option_made.connect(_on_option_made.bind(options_indices), CONNECT_ONE_SHOT)
	option_ui.canceled.connect(_on_option_canceled, CONNECT_ONE_SHOT)
	return true  # 选项 UI 接管推进


## 选项条件三槽：cond_key 为空视为无条件
func _option_condition_passed(item: Instruction) -> bool:
	var cond_key: String = item.params[1]
	if cond_key.is_empty():
		return true
	return _evaluate_condition(cond_key, item.params[2], item.params[3])


func _on_option_made(option_index: int, options_indices: Array[int]) -> void:
	if not _option_waiting:
		return
	_option_waiting = false
	# 跳转到选中的分支开始处
	idx = options_indices[option_index]
	run_script()


func _on_option_canceled() -> void:
	if not _option_waiting:
		return
	_option_waiting = false
	GalLogger.info(LOG_TAG, "选择被中断")


func _option_end(_ins: Instruction = null) -> bool:
	# 选项结构结束，清除记录
	current_option_end_idx = -1
	return false


func _jump_script(ins: Instruction) -> bool:
	# 解包参数: [script_name: String]
	var key: String = ins.params[0] as String
	
	next_script = key
	next_story()
	return true


func _jump_main_menu(_ins: Instruction = null) -> bool:
	# 无需参数
	_set_manager_mode(ManagerMode.INTERACT)
	current_option_end_idx = -1 # 回到主菜单时清理状态
	
	if dialogue_ui.visible:
		dialogue_ui.fade_out()
	AudioManager.stop_music()
	AudioManager.stop_voice()
	AudioManager.stop_all_sfx()  # 回主菜单即重建现场，loop 环境音不泄漏（主菜单 BGM 由主菜单自起）
	SceneManager.mount_and_unmount({
		"ui": {"主菜单": Global.scenes["主菜单"]},
	}, {
		"ui": {"对话UI": Global.scenes["对话UI"]},
		"world2d": {"Gal2D": Global.scenes["Gal2D"]}
	}, 1, 1, false)
	return true


func _evaluate_condition(key: String, operator: String, value: String) -> bool:
	# 不存在的变量视为 0.0；右值支持数字字面量或变量名
	var var_value: float = Global.vars.get(key, 0.0)
	var rhs := _resolve_value(value)

	match operator:
		"==":
			return is_equal_approx(var_value, rhs)
		"!=":
			return not is_equal_approx(var_value, rhs)
		">":
			return var_value > rhs
		">=":
			return var_value > rhs or is_equal_approx(var_value, rhs)
		"<":
			return var_value < rhs
		"<=":
			return var_value < rhs or is_equal_approx(var_value, rhs)
		_:
			GalLogger.warn(LOG_TAG, "未知的比较运算符: " + operator + "，使用 == 作为默认值")
			return is_equal_approx(var_value, rhs)


func _get_jump_target(current_idx: int) -> int:
	return _jump_table.get(current_idx, current_idx + 1)


func _if_condition(ins: Instruction) -> bool:
	var key = ins.params[0]
	var op = ins.params[1]
	var val = ins.params[2]
	
	_execution_stack.append(false)
	
	if _evaluate_condition(key, op, val):
		_execution_stack[-1] = true
		return false
	else:
		idx = _get_jump_target(idx - 1) 
		return false


func _else_if_condition(ins: Instruction) -> bool:
	if _execution_stack[-1] == true:
		_jump_to_end_of_structure()
		return false

	# 前面的分支都没执行，检查当前条件
	var key = ins.params[0]
	var op = ins.params[1]
	var val = ins.params[2]
	
	if _evaluate_condition(key, op, val):
		_execution_stack[-1] = true
		return false
	else:
		idx = _get_jump_target(idx - 1)
		return false


func _else_condition(_ins) -> bool:
	if _execution_stack[-1] == true:
		_jump_to_end_of_structure()
		return false
		
	_execution_stack[-1] = true
	return false


func _end_if_condition(_ins) -> bool:
	_execution_stack.pop_back()
	return false


func _jump_to_end_of_structure() -> void:
	var scan = idx - 1
	while _jump_table.has(scan):
		scan = _jump_table[scan]
	# 落点为 END_IF 本身（而非其后），让 _end_if_condition 正常弹栈——修复执行栈泄漏（R9 缺陷 1）
	idx = scan


func _show_dialogue(dialogue_item: DialogueItem) -> void:
	if not dialogue_ui.visible:
		dialogue_ui.fade_in()
	# 渲染：转义处理 + {var} 插值 + 锚点剥离（锚点索引 = 显示文本字符串索引）
	var rendered := DialogueRenderer.render(dialogue_item.dialogue, Global.vars)
	dialogue_ui.show_dialogue(dialogue_item.character, rendered["text"], rendered["anchors"])
	if manager_mode == ManagerMode.SKIP:
		dialogue_ui.skip_typing()


func load_game(sg: SavedGame):
	if sg.script_name.is_empty():
		GalLogger.warn(LOG_TAG, "要先存档才能载入")
		return

	# 清理状态
	current_option_end_idx = -1
	_option_waiting = false
	# execution_stack 不再入档/恢复（R9 缺陷 3：死字段，重放会重建）

	for c in gal_world2d.characters:
		c.reset([], true)
	next_script = sg.script_name
	await next_story(false)  # 注意：next_story 内部会重置选项状态并 randomize 新种子，执行顺序很重要

	# 重放准备：复位随机种子（使 var random 序列重现）、vars 从空累积
	Global.rng.seed = sg.rng_seed
	Global.rng_seed = sg.rng_seed
	Global.vars.clear()
	_replay_vars_snapshot = sg.vars.duplicate()

	# 以 SKIP 模式重放到存档点，重建背景/立绘/音乐等现场
	_replay_end = sg.idx
	_set_manager_mode(ManagerMode.SKIP)
	_advance()
