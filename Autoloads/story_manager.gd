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

var iterate_mode: IterateMode = IterateMode.DEFAULT
var idx := 0
var log_idx := 0

# --- 逻辑流控制 ---
# 逻辑层级执行状态栈，元素为是否已有分支执行
#（分支跳转目标在编译期烧进指令参数，运行时无跳转表——见 DialogueImporter._resolve_condition_targets）
var _execution_stack: Array[bool] = []

var next_script: String
var cur_script_name: String = ""
var cur_script: GalEventItemSequence

# --- 推进控制 ---
# 解释器主循环 run_script 是同步的（无 await）。挂起登记/模式机/计时器/抢占全部收编于 Synchronizer；
# 本类只保留回合结构状态：_waiting（停在对白停止点）、_suspended（停在阻塞挂起）、_turn_stopped（本回合已停）。
var _waiting := false  ## 停在对白停止点（后指令已消费完），等待推进触发
var _switching := false  ## next_story 转场进行中，屏蔽输入与推进
var _suspended := false  ## 停在 Synchronizer 阻塞挂起上（holds_cleared 续跑）
var _turn_stopped := false  ## 本回合已停止（对白展示/结构停止）；run_script 判停用
var _option_hold := Synchronizer.INVALID  ## 选项挂起凭证（INVALID = 无选项等待）
var _option_indices: Array[int] = []  ## 当前选项组可见分支起点（供 _on_option_made 路由）
var _replay_end := -1  ## 读档 SKIP 重放的终点索引，-1 表示不在重放
var _replay_vars_snapshot: Dictionary = {}  ## 重放结束后兜底覆盖的 vars 快照
var _choice_log: Array[int] = []  ## 选项选择序列（各组选定分支的 body_start，按经过顺序；随存档入档）
var _choice_cursor := 0  ## 重放中已消费的选择条数

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

	# 同步器收编：自动推进放行 / 挂起清空续跑与重布 / 模式切换重布触发器
	Synchronizer.advance_requested.connect(_on_advance_requested)
	Synchronizer.holds_cleared.connect(_on_holds_cleared)
	Synchronizer.mode_changed.connect(_on_mode_changed)
	
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
		Instruction.Head.SFX_VOLUME: 		_sfx_volume,
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
	match Synchronizer.mode:
		Synchronizer.Mode.STOP:
			return  # STOP 模式下屏蔽一切外部输入
		Synchronizer.Mode.INTERACT:
			_advance()
		_:
			# AUTO/SKIP 中点击：回到 INTERACT 并跳完当前打字
			Synchronizer.mode = Synchronizer.Mode.INTERACT
			dialogue_ui.skip_typing()


func on_fast_forward() -> void:
	match Synchronizer.mode:
		Synchronizer.Mode.STOP:
			return  # STOP 模式下屏蔽一切外部输入
		Synchronizer.Mode.INTERACT:
			_advance()
			dialogue_ui.skip_typing()  # 快进：推进后立即跳完新对白
		_:
			Synchronizer.mode = Synchronizer.Mode.INTERACT
			dialogue_ui.skip_typing()


func on_change_skip() -> void:
	# STOP 模式下屏蔽一切外部输入
	if Synchronizer.mode == Synchronizer.Mode.STOP:
		return
	if Synchronizer.mode == Synchronizer.Mode.SKIP:
		Synchronizer.mode = Synchronizer.Mode.INTERACT
	else:
		Synchronizer.mode = Synchronizer.Mode.SKIP
		# 进入跳过：按优先级抢占清理回合内挂起（角色直达终态、等待/语音终止、转场后台播完、选项保留）
		Synchronizer.preempt(Synchronizer.PRIO_SKIP_ENTER)
		if _suspended:
			# 抢占期间 holds_cleared 被抑制，此处手动续跑（SKIP 将自驱动连续推进）
			_suspended = false
			run_script()
		else:
			dialogue_ui.skip_typing()  # 跳完当前打字；finished 信号会驱动后指令与续跑


func on_change_auto() -> void:
	# STOP 模式下屏蔽一切外部输入
	if Synchronizer.mode == Synchronizer.Mode.STOP:
		return
	if Synchronizer.mode == Synchronizer.Mode.AUTO:
		Synchronizer.mode = Synchronizer.Mode.INTERACT
	else:
		Synchronizer.mode = Synchronizer.Mode.AUTO


func load_script(script_name: String):
	cur_script_name = script_name
	cur_script = ResourceManager.load("script", script_name) as GalEventItemSequence


## 推进一个回合：打字中则跳完（dialogue_finished 驱动后指令与续跑），否则经同步器门闸推进
func _advance(from_input := true) -> void:
	if _switching:
		return
	if dialogue_ui.skip_typing():
		return
	if Synchronizer.request_advance(from_input):
		run_script()


## 自动推进放行（AUTO/SKIP 计时到点且门闸畅通）
func _on_advance_requested() -> void:
	if _waiting:
		_advance(false)


## 挂起全清：被阻塞挂起停住则续跑；停在对白停止点则按当前模式重布触发器（如 AUTO 等语音结束）
func _on_holds_cleared() -> void:
	if _suspended:
		_suspended = false
		run_script()
	elif _waiting and not _switching:
		_arm_advance_trigger()


## 模式切换：同步器已作废旧预约计时；等待中按新模式重布触发器
func _on_mode_changed(_mode: Synchronizer.Mode) -> void:
	if _waiting and not _switching:
		_arm_advance_trigger()


## 同步执行剧本直到本回合停止点。无 await。
## 回合停止条件（结构性判停，不经返回值传播）：对白展示 / 同步器存在阻塞挂起 / 换幕中
func run_script(mode: IterateMode = IterateMode.DEFAULT) -> void:
	if cur_script == null:
		return
	iterate_mode = mode
	_waiting = false  # 回合结构旗标：本次推进后由 _on_dialogue_finished 重新置位
	# 回合边界：停旧语音 + 角色视觉结算（不兼管挂起簿记——挂起生命周期由同步器门闸/抢占管理）
	AudioManager.stop_voice()
	for c in gal_world2d.characters:
		c.skip_all()
	_turn_stopped = false
	while idx < cur_script.seq.size():
		var cur_item := cur_script.seq[idx]
		if log_idx != idx:
			GalLogger.debug(LOG_TAG, "执行: %s" % cur_item)
			log_idx = idx
		_step(cur_item)
		if _turn_stopped or Synchronizer.has_blocking() or _switching:
			break
	# 挂起态 = 停在阻塞挂起且本回合未因对白/结构停止（对白回合的挂起只门闸自动推进，不驱动续跑）
	_suspended = not _turn_stopped and Synchronizer.has_blocking()


## 独立指令判定（排除式：is 是子类型判定，直接 is Instruction 会吞掉子类）
func _is_independent(item: GalEventItem) -> bool:
	return item is Instruction and item is not PrevInstruction and item is not PostInstruction


## 执行单个条目；回合是否停止由 run_script 循环判停（_turn_stopped/阻塞挂起/换幕），不经返回值传播
func _step(item: GalEventItem) -> void:
	match iterate_mode:
		IterateMode.DEFAULT:
			if item is DialogueItem:
				idx += 1  # 先推进索引：SKIP 下 _show_dialogue 内 skip_typing 会同步重入 dialogue_finished，idx 须已是「下一未执行项」口径（重放终点判定依赖）
				_show_dialogue(item)
				iterate_mode = IterateMode.POST_COMMAND
				_turn_stopped = true  # 对白停止点：等打字完成
			else:
				idx += 1
				execute(item)
		IterateMode.POST_COMMAND:
			# 打字完成窗口：消费后指令与独立指令，遇前指令或对话停
			if item is PostInstruction or _is_independent(item):
				idx += 1
				execute(item)
			else:
				iterate_mode = IterateMode.DEFAULT
				_turn_stopped = true


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
		execute(item)
		if Synchronizer.has_blocking() or _switching:
			# 挂起/选项/换幕接管推进：不再布置触发器（挂起由 holds_cleared 续跑）
			_suspended = Synchronizer.has_blocking()
			return
	iterate_mode = IterateMode.DEFAULT
	_waiting = true

	# 读档重放到达存档点：交还玩家（_waiting 已在上方设置，保证模式切换能重新布置触发器）
	if _replay_end >= 0 and idx >= _replay_end:
		_replay_end = -1
		# 确定性重放结束后以快照兜底覆盖（一致时无效果，分叉时保 vars 正确）
		if not _replay_vars_snapshot.is_empty():
			Global.vars = _replay_vars_snapshot.duplicate()
			_replay_vars_snapshot = {}
		# 选项序列截掉存档点之后的陈旧未来（玩家此后可能走不同分支，新选择在尾部追加）
		_choice_log.resize(_choice_cursor)
		Synchronizer.mode = Synchronizer.Mode.INTERACT
		return

	_arm_advance_trigger()


## 按当前模式布置推进触发器；INTERACT 等玩家输入，STOP 由外部接管
func _arm_advance_trigger() -> void:
	match Synchronizer.mode:
		Synchronizer.Mode.AUTO:
			# 推进时机 = max(打字完成, 语音播完) + auto_wait_time：
			# 语音在播则只挂起 VOICE（不预约计时），voice_finished 释放后经 holds_cleared 重布本函数再计时；
			# voice stop 不触发 finished——「停止中」由 is_voice_playing 排除，残留凭证由点击/复位抢占清理
			if AudioManager.is_voice_playing():
				var hold := Synchronizer.acquire(&"voice")
				if hold != Synchronizer.INVALID:
					AudioManager.voice_finished.connect(func(): Synchronizer.release(hold), CONNECT_ONE_SHOT)
			else:
				Synchronizer.schedule(Global.auto_wait_time)
		Synchronizer.Mode.SKIP:
			Synchronizer.schedule(0.0)


## 执行指令。返回值的停止协议已废除：是否停止由 run_script 循环经结构条件判停
##（对白展示 / Synchronizer.has_blocking() / _switching），锚点旁路天然同语义
func execute(ins: Instruction) -> void:
	var handler = _instruction_handlers.get(ins.head)
	if handler is Callable:
		handler.call(ins)


func next_story(free: bool = false, fresh := false) -> void:
	_switching = true
	_waiting = false
	_suspended = false
	_option_hold = Synchronizer.INVALID
	Synchronizer.reset()  # 清全部挂起与预约计时 + 回 INTERACT
	if fresh:
		# 全新开局：选项选择序列清零（jump 换幕保持连续，读档由 load_game 覆写为存档记录）
		_choice_log.clear()
		_choice_cursor = 0

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


func _music_play(ins: Instruction) -> void:
	# 解包参数: [path: String, from: float, loop: bool, fade_in: float, fade_out: float, volume: float]
	var key: String = ins.params[0] as String
	var from_position: float = ins.params[1] as float
	var loop: bool = ins.params[2] as bool
	var fade_in: float = ins.params[3] as float
	var fade_out: float = ins.params[4] as float
	var volume: float = ins.params[5] as float

	var audio_stream = ResourceManager.load("audio", key)
	if audio_stream:
		AudioManager.play_music(audio_stream, from_position, fade_out, fade_in, loop, volume)
	else:
		GalLogger.error(LOG_TAG, "加载 BGM \"" + key + "\"失败")


func _music_pause(_ins: Instruction = null) -> void:
	# 无需参数
	AudioManager.pause_music()


func _music_resume(_ins: Instruction = null) -> void:
	# 无需参数
	AudioManager.resume_music()


func _music_stop(ins: Instruction = null) -> void:
	# 参数: [fade: float]
	var fade := 1.0
	if ins != null:
		fade = ins.params[0] as float
	AudioManager.stop_music(fade)
	return


## music volume <0~1> [fade:秒]：调节在播音轨响度，不重启曲目
func _music_volume(ins: Instruction) -> void:
	# 参数: [volume: float, fade: float]
	AudioManager.set_music_volume(ins.params[0] as float, ins.params[1] as float)


func _voice_play(ins: Instruction) -> void:
	# 解包参数: [path: String, from: float, volume: float]
	var key: String = ins.params[0] as String
	var offset: float = ins.params[1] as float
	var volume: float = ins.params[2] as float
	
	var audio_stream = ResourceManager.load("audio", key)
	if audio_stream:
		AudioManager.play_voice(audio_stream, offset, volume)
	else:
		GalLogger.error(LOG_TAG, "加载语音\"" + key + "\"失败")


func _sfx_play(ins: Instruction) -> void:
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
	return


## voice stop [fade:秒]；推进对话时的自动停止走 AudioManager.stop_voice 默认参数
func _voice_stop(ins: Instruction) -> void:
	# 参数: [fade: float]
	AudioManager.stop_voice(ins.params[0] as float)
	return


## sfx stop [引用] [fade:秒]；引用省略 = 停止全部。播放中的引用必然已缓存，load 命中缓存不产生新加载
func _sfx_stop(ins: Instruction) -> void:
	# 参数: [ref: String, fade: float]
	var ref: String = ins.params[0]
	var fade: float = ins.params[1]
	if ref.is_empty():
		AudioManager.stop_all_sfx(fade)
		return
	var audio_stream = ResourceManager.load("audio", ref)
	if audio_stream:
		AudioManager.stop_sfx(audio_stream, fade)
	else:
		GalLogger.warn(LOG_TAG, "sfx stop 引用无法解析（可能从未播放）: " + ref)
	return


## sfx volume <引用> <0~1> [fade:秒]：按流身份匹配调节在播音效响度，不中断播放
func _sfx_volume(ins: Instruction) -> void:
	# 参数: [ref: String, volume: float, fade: float]
	var ref: String = ins.params[0]
	var audio_stream = ResourceManager.load("audio", ref)
	if audio_stream:
		AudioManager.set_sfx_volume(audio_stream, ins.params[1] as float, ins.params[2] as float)
	else:
		GalLogger.warn(LOG_TAG, "sfx volume 引用无法解析（可能从未播放）: " + ref)


func _set_background(ins: Instruction) -> void:
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
	return


# --- 角色动画（直挂实例：入队 + 空闲自动播放；wait:true 挂起剧情） ---

func _char_at(char_idx: int) -> Character:
	if char_idx < 0 or char_idx >= gal_world2d.characters.size():
		GalLogger.error(LOG_TAG, "角色实例索引越界: %d（上限 %d）" % [char_idx, gal_world2d.characters.size()])
		return null
	return gal_world2d.characters[char_idx]


## 入队并自动播放；wait:true 时挂起剧情直到该实例动画序列完成
##（SKIP/重放中 acquire 短路不挂起；点击打断 = FAST_FORWARD 处置 skip_all 直达终态）
func _char_enqueue(c: Character, step: Array, wait: bool) -> void:
	if c == null:
		return
	c.animation_list.append(step)
	c.play()
	if not wait:
		return
	var hold := Synchronizer.acquire(&"char", c, func(): c.skip_all())
	if hold == Synchronizer.INVALID:
		return
	# sequence_finished 一次性释放；skip_all 不发该信号（防假唤醒），抢占处置由同步器直接释放
	c.sequence_finished.connect(func(): Synchronizer.release(hold), CONNECT_ONE_SHOT)


func _char_setup(ins: Instruction) -> void:
	# 参数: [char_index: int, path: String, x: float, y: float]
	var c := _char_at(ins.params[0] as int)
	if c == null:
		return
	var tex = ResourceManager.load("texture", ins.params[1] as String)
	if tex == null:
		GalLogger.error(LOG_TAG, "加载立绘失败: " + (ins.params[1] as String))
		return
	return _char_enqueue(c, [
		Character.AnimationType.SETUP, tex, Vector2(ins.params[2] as float, ins.params[3] as float)
	], false)


func _char_show_fade(ins: Instruction) -> void:
	# 参数: [char_index: int, duration: float, wait: bool]
	var c := _char_at(ins.params[0] as int)
	return _char_enqueue(c, [Character.AnimationType.SHOW_FADE, ins.params[1] as float], ins.params[2] as bool)


func _char_hide_fade(ins: Instruction) -> void:
	var c := _char_at(ins.params[0] as int)
	return _char_enqueue(c, [Character.AnimationType.HIDE_FADE, ins.params[1] as float], ins.params[2] as bool)


func _char_move_to(ins: Instruction) -> void:
	# 参数: [char_index: int, x: float, y: float, duration: float, wait: bool]
	var c := _char_at(ins.params[0] as int)
	return _char_enqueue(c, [
		Character.AnimationType.MOVE_TO,
		Vector2(ins.params[1] as float, ins.params[2] as float),
		ins.params[3] as float,
	], ins.params[4] as bool)


func _char_change_texture(ins: Instruction) -> void:
	# 参数: [char_index: int, path: String]
	var c := _char_at(ins.params[0] as int)
	if c == null:
		return
	var tex = ResourceManager.load("texture", ins.params[1] as String)
	if tex == null:
		GalLogger.error(LOG_TAG, "加载立绘失败: " + (ins.params[1] as String))
		return
	return _char_enqueue(c, [Character.AnimationType.CHANGE_TEXTURE, tex], false)


func _char_wait(ins: Instruction) -> void:
	# 参数: [char_index: int, duration: float]（队列内等待，仅正秒）
	var c := _char_at(ins.params[0] as int)
	return _char_enqueue(c, [Character.AnimationType.WAIT, ins.params[1] as float], false)


# --- 变量 ---

## 解析右值：数字字面量直接转换，否则按变量名查表（未定义按 0.0）
func _resolve_value(s: String) -> float:
	if s.is_valid_float():
		return s.to_float()
	return Global.vars.get(s, 0.0)


func _var_set(ins: Instruction) -> void:
	Global.vars[ins.params[0]] = _resolve_value(ins.params[1])


func _var_add(ins: Instruction) -> void:
	var key: String = ins.params[0]
	Global.vars[key] = Global.vars.get(key, 0.0) + _resolve_value(ins.params[1])


func _var_sub(ins: Instruction) -> void:
	var key: String = ins.params[0]
	Global.vars[key] = Global.vars.get(key, 0.0) - _resolve_value(ins.params[1])


func _var_mul(ins: Instruction) -> void:
	var key: String = ins.params[0]
	Global.vars[key] = Global.vars.get(key, 0.0) * _resolve_value(ins.params[1])


func _var_div(ins: Instruction) -> void:
	var key: String = ins.params[0]
	var divisor := _resolve_value(ins.params[1])
	if is_zero_approx(divisor):
		GalLogger.warn(LOG_TAG, "var 除零，变量保持不变: " + key)
		return
	Global.vars[key] = Global.vars.get(key, 0.0) / divisor


func _var_random(ins: Instruction) -> void:
	# 参数: [key: String, min: float, max: float]；用 Global.rng 保证重放确定性
	Global.vars[ins.params[0]] = Global.rng.randf_range(ins.params[1] as float, ins.params[2] as float)
	return


## 剧情显式等待（SKIP/重放中 acquire 短路；点击打断 = KILL 处置计时器作废）
func _wait(ins: Instruction) -> void:
	var duration: float = ins.params[0] as float
	if duration <= 0.0:
		return
	Synchronizer.wait_seconds(duration)


# --- 场景挂载与转场（转发 SceneManager，不建平行系统） ---

func _scene_mount(ins: Instruction) -> void:
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


func _scene_unmount(ins: Instruction) -> void:
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


func _trans_in(ins: Instruction) -> void:
	_do_transition(ins)


func _trans_out(ins: Instruction) -> void:
	_do_transition(ins)


## 参数: [duration, anim, wait]；wait:true 挂起剧情直到转场完成
##（SKIP/重放中完全不转场；点击打断 = RELEASE_ASYNC 处置，转场视觉后台播完）
func _do_transition(ins: Instruction) -> void:
	var duration: float = ins.params[0] as float
	var anim: String = ins.params[1] as String
	var wait: bool = ins.params[2] as bool

	# SKIP/重放中不真实转场（完全跳过，而非仅不等待——重放需快速重建现场）
	if Synchronizer.mode == Synchronizer.Mode.SKIP:
		return

	if not is_instance_valid(SceneManager.transition_controller):
		# 无转场控制器（如 headless 测试环境）：警告且绝不挂起，防死锁
		GalLogger.warn(LOG_TAG, "trans 指令无转场控制器可用，跳过: " + anim)
		return

	if wait:
		var hold := Synchronizer.acquire(&"trans")
		if hold != Synchronizer.INVALID:
			SceneManager.transition_controller.transition_finished.connect(
				func(): Synchronizer.release(hold), CONNECT_ONE_SHOT)
			SceneManager.transition(anim, duration)
			return
	SceneManager.transition(anim, duration)


func _set_begin_script(ins: Instruction) -> void:
	# 参数: [script_name: String]
	var begin_script: String = ins.params[0] as String
	
	Global.config["begin_script"] = begin_script


func _option_begin(ins: Instruction) -> void:
	# 参数: [text, tokens, is_head, body_start, next_option, group_end]（组结构编译期回填）
	# 非组头：只可能是在分支体内遇到兄弟 OPTION → 直跳组尾（防穿透，无运行时状态）
	if not (ins.params[2] as bool):
		idx = ins.params[5] as int
		return

	# 组头：沿 next_option 链收集可见项（条件运行时求值；分支起点直接用回填的 body_start）
	var options_text: PackedStringArray = []
	var options_indices: Array[int] = []
	var cursor := ins
	while true:
		if _option_condition_passed(cursor):
			# 选项文本与对话同口径：转义 + {var} 插值（无锚点时间轴，方括号原样保留）
			options_text.append(DialogueRenderer.render_plain(cursor.params[0], Global.vars))
			options_indices.append(cursor.params[3] as int)
		var next_idx := cursor.params[4] as int
		if next_idx < 0:
			break
		cursor = cur_script.seq[next_idx] as Instruction

	# 空选项组防护（条件过滤后无存活选项）：跳过整组，不弹 UI（不产生选择记录——玩家本就未经此组）
	if options_text.is_empty():
		GalLogger.warn(LOG_TAG, "选项组条件过滤后为空，跳过整组")
		idx = ins.params[5] as int
		return

	# 重放中：按存档记录自动选定（不弹 UI、不产生挂起——确定性重放的核心要求）
	if _replay_end >= 0:
		var target := -1
		if _choice_cursor < _choice_log.size():
			target = _choice_log[_choice_cursor]
		_choice_cursor += 1
		if not options_indices.has(target):
			GalLogger.warn(LOG_TAG, "重放选项记录不可用（内容漂移或旧档），退化到首个可见项")
			target = options_indices[0]
		idx = target
		return

	# 对话框淡出完成后再弹出选项（信号串联，不挂起协程）
	dialogue_ui.fade_out().finished.connect(func():
		SceneManager.mount({
			"ui": {"选择UI": Global.scenes["选择UI"]}
		})
		option_ui.show_options(options_text)
	, CONNECT_ONE_SHOT)
	Synchronizer.mode = Synchronizer.Mode.INTERACT

	# 选项挂起（SKIP 中也真实挂起——skip_immune）；玩家选择/取消时释放
	_option_hold = Synchronizer.acquire(&"option")
	_option_indices = options_indices
	# 常驻连接 + _option_hold 守卫幂等（一次性连接在取消路径下会积存残留，反复连接报错）
	if not option_ui.option_made.is_connected(_on_option_made):
		option_ui.option_made.connect(_on_option_made)
	if not option_ui.canceled.is_connected(_on_option_canceled):
		option_ui.canceled.connect(_on_option_canceled)


## 选项条件：tokens 为空 = 无条件（恒真）
func _option_condition_passed(item: Instruction) -> bool:
	var tokens: Array = item.params[1]
	return tokens.is_empty() or _eval_condition(tokens)


func _on_option_made(option_index: int) -> void:
	if _option_hold == Synchronizer.INVALID:
		return
	var hold := _option_hold
	_option_hold = Synchronizer.INVALID
	# 跳转到选中的分支开始处
	idx = _option_indices[option_index]
	# 记录选择（确定性重放：读档后经同一选项组时按记录自动选定）
	_choice_log.append(_option_indices[option_index])
	Synchronizer.release(hold)  # holds_cleared 驱动续跑 run_script


func _on_option_canceled() -> void:
	if _option_hold == Synchronizer.INVALID:
		return
	var hold := _option_hold
	_option_hold = Synchronizer.INVALID
	_suspended = false  # 取消不续跑（读档等外部流程接管）
	Synchronizer.release(hold)
	GalLogger.info(LOG_TAG, "选择被中断")


func _option_end(_ins: Instruction = null) -> void:
	# 选项结构收尾标记（组结构已编译期回填进各 OPTION 参数，此处无事可做）
	pass


func _jump_script(ins: Instruction) -> void:
	# 解包参数: [script_name: String]
	var key: String = ins.params[0] as String
	
	next_script = key
	next_story()


func _jump_main_menu(_ins: Instruction = null) -> void:
	# 无需参数
	_waiting = false
	_suspended = false
	_option_hold = Synchronizer.INVALID
	Synchronizer.reset()  # 清全部挂起与预约计时 + 回 INTERACT
	
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


## 条件求值：后缀记号流栈机（编译期编码见 Instruction.CondTag；分支目标见 params）。
## 全函数：任意畸形输入最坏得到 false + 错误日志（编译期已保证良构，此为产物损毁护栏）
func _eval_condition(tokens: Array) -> bool:
	var stack: Array = []
	for token in tokens:
		match token[0]:
			Instruction.CondTag.PUSH_NUM:
				stack.append(token[1])
			Instruction.CondTag.PUSH_VAR:
				stack.append(Global.vars.get(token[1], 0.0))  # 不存在的变量视为 0.0
			Instruction.CondTag.CMP:
				if stack.size() < 2:
					return _cond_malformed(tokens)
				var rhs: float = stack.pop_back()
				var lhs: float = stack.pop_back()
				stack.append(_compare_values(lhs, token[1], rhs))
			Instruction.CondTag.NOT:
				if stack.is_empty():
					return _cond_malformed(tokens)
				stack.append(not _truthy(stack.pop_back()))
			Instruction.CondTag.AND:
				if stack.size() < 2:
					return _cond_malformed(tokens)
				var and_rhs: bool = _truthy(stack.pop_back())
				var and_lhs: bool = _truthy(stack.pop_back())
				stack.append(and_lhs and and_rhs)
			Instruction.CondTag.OR:
				if stack.size() < 2:
					return _cond_malformed(tokens)
				var or_rhs: bool = _truthy(stack.pop_back())
				var or_lhs: bool = _truthy(stack.pop_back())
				stack.append(or_lhs or or_rhs)
			_:
				return _cond_malformed(tokens)
	if stack.size() != 1:
		return _cond_malformed(tokens)
	return _truthy(stack[0])


## 真值口径：bool 原样；数字非 0 为真（裸变量条件如 if flag 的语义）
static func _truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is float or v is int:
		return v != 0.0
	return false


## 数值比较（==/!= 为浮点近似）
func _compare_values(lhs: float, op: String, rhs: float) -> bool:
	match op:
		"==":
			return is_equal_approx(lhs, rhs)
		"!=":
			return not is_equal_approx(lhs, rhs)
		">":
			return lhs > rhs
		">=":
			return lhs > rhs or is_equal_approx(lhs, rhs)
		"<":
			return lhs < rhs
		"<=":
			return lhs < rhs or is_equal_approx(lhs, rhs)
		_:
			GalLogger.error(LOG_TAG, "未知比较符（产物损毁？）按 false 处理: " + op)
			return false


func _cond_malformed(tokens: Array) -> bool:
	GalLogger.error(LOG_TAG, "条件记号流畸形（产物损毁？）按 false 处理: %s" % [tokens])
	return false


## 空栈守卫：ELSE_IF/ELSE/END_IF 在执行栈为空时被调用说明产物结构失衡
##（编译期已保证配对，正常不可达）。报错留痕并顺序继续
func _guard_stack_nonempty(what: String, ins: Instruction) -> bool:
	if not _execution_stack.is_empty():
		return true
	GalLogger.error(LOG_TAG, "%s 执行栈为空（条件结构失衡），忽略: %s" % [what, ins])
	return false


func _if_condition(ins: Instruction) -> void:
	# 参数: [tokens: Array, next_target: int]（next_target = 下一分支头或 END_IF，编译期回填）
	_execution_stack.append(false)
	if _eval_condition(ins.params[0]):
		_execution_stack[-1] = true
	else:
		idx = ins.params[1]


func _else_if_condition(ins: Instruction) -> void:
	# 参数: [tokens: Array, next_target: int, end_target: int]
	if not _guard_stack_nonempty("ELSE_IF", ins):
		return
	# 前分支已执行：直接到 END_IF 弹栈（R9 缺陷 1：落点是 END_IF 本身）
	if _execution_stack[-1] == true:
		idx = ins.params[2]
		return
	if _eval_condition(ins.params[0]):
		_execution_stack[-1] = true
	else:
		idx = ins.params[1]


func _else_condition(ins: Instruction) -> void:
	# 参数: [end_target: int]
	if not _guard_stack_nonempty("ELSE", ins):
		return
	if _execution_stack[-1] == true:
		idx = ins.params[0]
		return
	_execution_stack[-1] = true


func _end_if_condition(_ins) -> void:
	if not _guard_stack_nonempty("END_IF", _ins):
		return
	_execution_stack.pop_back()


func _show_dialogue(dialogue_item: DialogueItem) -> void:
	if not dialogue_ui.visible:
		dialogue_ui.fade_in()
	# 渲染：转义处理 + {var} 插值 + 锚点剥离（锚点索引 = 显示文本字符串索引）
	var rendered := DialogueRenderer.render(dialogue_item.dialogue, Global.vars)
	dialogue_ui.show_dialogue(dialogue_item.character, rendered["text"], rendered["anchors"])
	if Synchronizer.mode == Synchronizer.Mode.SKIP:
		dialogue_ui.skip_typing()


func load_game(sg: SavedGame):
	if sg.script_name.is_empty():
		GalLogger.warn(LOG_TAG, "要先存档才能载入")
		return

	# 清理状态（挂起簿记由 next_story 内的 Synchronizer.reset() 统一清）
	_option_hold = Synchronizer.INVALID
	_suspended = false
	# execution_stack 不再入档/恢复（R9 缺陷 3：死字段，重放会重建）

	for c in gal_world2d.characters:
		c.reset([], true)
	next_script = sg.script_name
	await next_story(false)  # 注意：next_story 内部会重置选项状态并 randomize 新种子，执行顺序很重要

	# 重放准备：复位随机种子（使 var random 序列重现）、vars 从空累积、选项序列换存档记录
	Global.rng.seed = sg.rng_seed
	Global.rng_seed = sg.rng_seed
	Global.vars.clear()
	_replay_vars_snapshot = sg.vars.duplicate()
	_choice_log = sg.choice_log.duplicate()
	_choice_cursor = 0

	# 以 SKIP 模式重放到存档点，重建背景/立绘/音乐等现场
	_replay_end = sg.idx
	Synchronizer.mode = Synchronizer.Mode.SKIP
	_advance()
