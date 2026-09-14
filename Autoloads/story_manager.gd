extends Node
const LOG_TAG := "StoryManager"


@export var dialogue_ui: DialogueUI
@export var gal_ui: GalUI
@export var option_ui: OptionUI
@export var gal_world2d: GalWorld2d

enum IterateMode {
	INITIALIZATION,  ## 只执行前置指令，遇到第一个对话转入 DEFAULT 并展示
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
var iterate_mode: IterateMode = IterateMode.INITIALIZATION
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
# 执行到对白/选项/跳转即返回，推进由信号与定时器驱动（见 _arm_advance_trigger）
var _waiting := false  ## 停在对白停止点（后指令已消费完），等待推进触发
var _switching := false  ## next_story 转场进行中，屏蔽输入与推进
var _option_waiting := false  ## 选项 UI 打开中
var _replay_end := -1  ## 读档 SKIP 重放的终点索引，-1 表示不在重放

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
		Instruction.Head.VOICE_PLAY: 		_voice_play,
		Instruction.Head.SFX_PLAY: 			_sfx_play,
		Instruction.Head.SET_BACKGROUND: 	_set_background,
		Instruction.Head.VOICE_EVENT: 		_voice_event,
		Instruction.Head.CHARACTER: 		_char_begin,
		Instruction.Head.CHAR_PLAY: 		_char_play,
		Instruction.Head.OPTION: 			_option_begin,
		Instruction.Head.OPTION_END: 		_option_end,
		Instruction.Head.SET_BEGIN_SCRIPT: 	_set_begin_script,
		Instruction.Head.JUMP_SCRIPT:	 	_jump_script,
		Instruction.Head.JUMP_MAIN_MENU: 	_jump_main_menu,
		Instruction.Head.IF: 				_if_condition,
		Instruction.Head.ELSE_IF: 			_else_if_condition,
		Instruction.Head.ELSE: 				_else_condition,
		Instruction.Head.END_IF: 			_end_if_condition,
	}


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


## 同步执行剧本直到本回合停止点（对白/选项/跳转/末尾）。无 await：
## 对白停止后的推进由 _arm_advance_trigger 按 manager_mode 布置
func run_script(mode: IterateMode = IterateMode.DEFAULT) -> void:
	if cur_script == null:
		return
	iterate_mode = mode
	_waiting = false
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


## 执行单个条目，返回 true 表示本回合停止（对白展示/外部接管/模式结束）
func _step(item: GalEventItem) -> bool:
	match iterate_mode:
		IterateMode.INITIALIZATION:
			if item is PrevInstruction:
				idx += 1
				return execute(item)
			iterate_mode = IterateMode.DEFAULT
			return false
		IterateMode.DEFAULT:
			if item is DialogueItem:
				_show_dialogue(item)
				idx += 1
				iterate_mode = IterateMode.POST_COMMAND
				return true  # 对白停止点：等打字完成
			idx += 1
			return execute(item)
		IterateMode.POST_COMMAND:
			if item is PostInstruction:
				idx += 1
				return execute(item)
			iterate_mode = IterateMode.DEFAULT
			return true
	return false


## 打字完成（自然结束或被跳过）：消费后指令，然后按模式安排下一次推进
func _on_dialogue_finished() -> void:
	while idx < cur_script.seq.size() and cur_script.seq[idx] is PostInstruction:
		var item := cur_script.seq[idx]
		if log_idx != idx:
			GalLogger.debug(LOG_TAG, "执行: %s" % item)
			log_idx = idx
		idx += 1
		if execute(item):
			return  # 选项/跳转接管推进，不再布置触发器
	iterate_mode = IterateMode.DEFAULT
	_waiting = true

	# 读档重放到达存档点：交还玩家（_waiting 已在上方设置，保证模式切换能重新布置触发器）
	if _replay_end >= 0 and idx >= _replay_end:
		_replay_end = -1
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
	
	if dialogue_ui.visible:
		dialogue_ui.fade_out()
	AudioManager.stop_music()
	AudioManager.stop_voice()
	await SceneManager.transition("fade_out", 1)
	SceneManager.umount_all(["ui", "world2d"], free)
	ResourceManager.clear_all_cache()
	
	# reset
	idx = 0
	current_option_end_idx = -1 # 切换脚本时，必须强制重置选项状态
	_execution_stack.clear() # 重置逻辑流控制状态
	dialogue_ui.clear_display()
	gal_world2d.set_background_texture(null)
	
	SceneManager.mount({
		"ui": {
			"对话UI": Global.scenes["对话UI"],
			"GalUI": Global.scenes["GalUI"],
		},
		"world2d": {"Gal2D": Global.scenes["Gal2D"]}
	})
	
	load_script(next_script)
	run_script(IterateMode.INITIALIZATION)
	
	await SceneManager.transition("fade_in", 1)
	_switching = false


func _music_play(ins: Instruction) -> bool:
	# 解包参数: [path: String, vol: float, loop: bool]
	var key: String = ins.params[0] as String
	var from_position: float = ins.params[1] as float
	var loop: bool = ins.params[2] as bool
	
	var audio_stream = ResourceManager.load("audio", key)
	if audio_stream:
		AudioManager.play_music(audio_stream, from_position, 1.0, 1.0, loop)
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


func _music_stop(_ins: Instruction = null) -> bool:
	# 无需参数
	AudioManager.stop_music()
	return false


func _voice_play(ins: Instruction) -> bool:
	# 解包参数: [path: String, offset: float]
	var key: String = ins.params[0] as String
	var offset: float = ins.params[1] as float
	
	var audio_stream = ResourceManager.load("audio", key)
	if audio_stream:
		AudioManager.play_voice(audio_stream, offset)
	else:
		GalLogger.error(LOG_TAG, "加载语音\"" + key + "\"失败")
	return false


func _sfx_play(ins: Instruction) -> bool:
	# 解包参数: [path: String, offset: float]
	var key: String = ins.params[0] as String
	var offset: float = ins.params[1] as float
	
	var audio_stream = ResourceManager.load("audio", key)
	if audio_stream:
		AudioManager.play_sfx(audio_stream, offset)
	else:
		GalLogger.error(LOG_TAG, "加载音效\"" + key + "\"失败")
	return false


func _set_background(ins: Instruction) -> bool:
	# 解包参数: [path: String]
	var key: String = ins.params[0] as String
	
	var background_tex = ResourceManager.load("texture", key)
	if background_tex:
		gal_world2d.background.texture = background_tex
	else:
		GalLogger.error(LOG_TAG, "加载背景失败: " + key)
	return false


func _voice_event(ins: Instruction) -> bool:
	# 解包参数: [time: float]
	var delay: float = ins.params[0] as float
	
	var next_item := cur_script.seq[idx]
	if next_item is not Instruction:
		GalLogger.error(LOG_TAG, "语音嵌入指令后未跟随一个指令")
	idx += 1
	AudioManager.voice_manager.add_event(delay, execute.bind(next_item))
	return false


func _char_begin(ins: Instruction) -> bool:
	# 解包参数: [char_index: int]
	var char_idx: int = ins.params[0] as int
	
	var char_animation_list := gal_world2d.characters[char_idx].animation_list
	while true:
		var item := cur_script.seq[idx]
		if item is Instruction:
			match item.head:
				Instruction.Head.CHAR_SETUP:
					_char_setup_internal(char_animation_list, item)
				Instruction.Head.CHAR_SHOW_FADE:
					_char_show_fade_internal(char_animation_list, item)
				Instruction.Head.CHAR_HIDE_FADE:
					_char_hide_fade_internal(char_animation_list, item)
				Instruction.Head.CHAR_MOVE_TO:
					_char_move_to_internal(char_animation_list, item)
				Instruction.Head.CHAR_WAIT:
					_char_wait_internal(char_animation_list, item)
				Instruction.Head.CHAR_CHANGE_TEXTURE:
					_char_change_texture_internal(char_animation_list, item)
				_:
					break
		idx += 1
	return false


func _char_setup_internal(char_animation_list:Array[Array], ins: Instruction) -> void:
	# 解包参数: [path: String, x: float, y: float]
	var tex: String = ins.params[0] as String
	var x: float = ins.params[1] as float
	var y: float = ins.params[2] as float
	
	char_animation_list.append([
		Character.AnimationType.SETUP,
		ResourceManager.load("texture", tex),
		Vector2(x, y)
	])


func _char_show_fade_internal(char_animation_list:Array[Array], ins: Instruction) -> void:
	# 解包参数: [duration: float]
	var duration: float = ins.params[0] as float
	
	char_animation_list.append([
		Character.AnimationType.SHOW_FADE,
		duration
	])


func _char_hide_fade_internal(char_animation_list:Array[Array], ins: Instruction) -> void:
	# 解包参数: [duration: float]
	var duration: float = ins.params[0] as float
	
	char_animation_list.append([
		Character.AnimationType.HIDE_FADE,
		duration
	])


func _char_move_to_internal(char_animation_list:Array[Array], ins: Instruction) -> void:
	# 解包参数: [x: float, y: float, duration: float]
	var x: float = ins.params[0] as float
	var y: float = ins.params[1] as float
	var duration: float = ins.params[2] as float
	
	char_animation_list.append([
		Character.AnimationType.MOVE_TO,
		Vector2(x, y),
		duration
	])


func _char_change_texture_internal(char_animation_list:Array[Array], ins: Instruction) -> void:
	# 解包参数: [path: String]
	var tex: String = ins.params[0] as String
	
	char_animation_list.append([
		Character.AnimationType.CHANGE_TEXTURE,
		ResourceManager.load("texture", tex)
	])


func _char_wait_internal(char_animation_list:Array[Array], ins: Instruction) -> void:
	# 解包参数: [duration: float]
	var duration: float = ins.params[0] as float
	
	char_animation_list.append([
		Character.AnimationType.WAIT,
		duration
	])


func _char_play(ins: Instruction) -> bool:
	# 解包参数: [char_index: int]
	var char_idx: int = ins.params[0] as int
	
	gal_world2d.characters[char_idx].play()
	return false


func _set_begin_script(ins: Instruction) -> bool:
	# 参数: [script_name: String]
	var begin_script: String = ins.params[0] as String
	
	Global.config["begin_script"] = begin_script
	return false


func _option_begin(ins: Instruction) -> bool:
	# 参数: [text: String]
	var option_text: String = ins.params[0] as String
	
	# 如果已经在本组选项中（current_option_end_idx 有效），并且还没走到 END，
	# 说明当前是在其他分支里再次遇到 OPTION，直接跳到本组选项尾部
	if current_option_end_idx != -1 and idx < current_option_end_idx:
		idx = current_option_end_idx
		# 此时 idx 指向 OPTION_END
		# run_script 下一次循环会处理 OPTION_END，从而重置状态并继续往下
		return false

	# 扫描本组选项
	var options_text: PackedStringArray = []
	var options_indices: Array[int] = []
	var scan_idx := idx 
	
	# 记录第一个选项
	options_text.append(option_text)
	options_indices.append(scan_idx)
	
	while scan_idx < cur_script.seq.size():
		var item := cur_script.seq[scan_idx]
		if item is Instruction:
			if item.head == Instruction.Head.OPTION_END:
				# 找到了当前这组选项的最终结束点，记录下来！
				current_option_end_idx = scan_idx 
				# 这里不 +1，因为我们要跳到 OPTION_END 本身，让它去执行重置逻辑
				break
			
			if item.head == Instruction.Head.OPTION:
				options_text.append(item.params[0])
				options_indices.append(scan_idx + 1)
		scan_idx += 1
	
	# 没找到 OPTION_END 时给出提示
	if current_option_end_idx == -1:
		GalLogger.warn(LOG_TAG, "未找到 OPTION_END，选项逻辑可能出错")
	
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
	SceneManager.mount_and_unmount({
		"ui": {"主菜单": Global.scenes["主菜单"]},
	}, {
		"ui": {"对话UI": Global.scenes["对话UI"]},
		"world2d": {"Gal2D": Global.scenes["Gal2D"]}
	}, 1, 1, false)
	return true


func _evaluate_condition(key: String, operator: String, value: float) -> bool:
	# 不存在的变量视为 0.0
	var var_value: float = Global.vars.get(key, 0.0)
	
	match operator:
		"==", "=":
			return var_value == value
		"!=", "<>":
			return var_value != value
		">":
			return var_value > value
		">=":
			return var_value >= value
		"<":
			return var_value < value
		"<=":
			return var_value <= value
		_:
			GalLogger.warn(LOG_TAG, "未知的比较运算符: " + operator + "，使用 == 作为默认值")
			return var_value == value


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
	idx = scan + 1


func _show_dialogue(dialogue_item: DialogueItem) -> void:
	if not dialogue_ui.visible:
		dialogue_ui.fade_in()
	dialogue_ui.show_dialogue(dialogue_item.character, dialogue_item.dialogue)
	if manager_mode == ManagerMode.SKIP:
		dialogue_ui.skip_typing()


func load_game(sg: SavedGame):
	if sg.script_name.is_empty():
		GalLogger.warn(LOG_TAG, "要先存档才能载入")
		return
	
	# 清理状态
	current_option_end_idx = -1
	_option_waiting = false
	_execution_stack = sg.execution_stack
	
	for c in gal_world2d.characters:
		c.reset([], true)
	Global.vars = sg.vars
	next_script = sg.script_name
	await next_story(false)  # 注意：next_story 内部会重置选项状态，执行顺序很重要
	
	# 以 SKIP 模式重放到存档点，重建背景/立绘/音乐等现场
	_replay_end = sg.idx
	_set_manager_mode(ManagerMode.SKIP)
	_advance()
