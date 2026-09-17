extends SceneTree

## 冒烟测试：校验演示剧本编译产物的内容结构（BGalS v2）+ 路径策略 + bool→float 传参行为
## 用法：godot --headless --path . -s test/smoke_test.gd

var _ok := true

func _init() -> void:
	# --- demo_scene1 结构断言 ---
	var seq1 = ResourceLoader.load("res://GalSs/demo_scene1.tres")
	if seq1 == null or seq1.seq.is_empty():
		print("FAIL: demo_scene1 无法加载或为空")
		_ok = false
	else:
		var s: Array = seq1.seq
		_assert(s[0] is Instruction and s[0].head == Instruction.Head.SET_BACKGROUND,
			"scene1 首条应为 SET_BACKGROUND")
		_assert(s[-1] is Instruction and s[-1].head == Instruction.Head.JUMP_MAIN_MENU,
			"scene1 末条应为 JUMP_MAIN_MENU")

		# 选项组拍平：OPTION → ... → OPTION → ... → OPTION_END
		var option_count := 0
		var has_option_end := false
		var has_conditional_option := false
		var has_var := false
		var has_if_chain := false
		for item in s:
			if item is Instruction:
				match item.head:
					Instruction.Head.OPTION:
						option_count += 1
						if (item.params[1] as String) == "affection":
							has_conditional_option = true
					Instruction.Head.OPTION_END:
						has_option_end = true
					Instruction.Head.VAR_SET:
						has_var = true
					Instruction.Head.END_IF:
						has_if_chain = true
		_assert(option_count == 2 and has_option_end, "scene1 选项组应为 2 选项 + OPTION_END")
		_assert(has_conditional_option, "scene1 应含条件选项（cond_key=affection）")
		_assert(has_var, "scene1 应含 VAR_SET")
		_assert(has_if_chain, "scene1 应含 if 链收尾 END_IF")

		# 三态指令齐备：独立（基类）/ 前 / 后
		var has_free := false
		var has_prev := false
		var has_post := false
		for item in s:
			if item is PrevInstruction:
				has_prev = true
			elif item is PostInstruction:
				has_post = true
			elif item is Instruction:
				has_free = true
		_assert(has_free and has_prev and has_post, "scene1 应含独立/前/后三类指令")

	# --- demo_scene2 结构断言 ---
	var seq2 = ResourceLoader.load("res://GalSs/demo_scene2.tres")
	if seq2 == null or seq2.seq.is_empty():
		print("FAIL: demo_scene2 无法加载或为空")
		_ok = false
	else:
		var found_texture := false
		for item in seq2.seq:
			if item is Instruction and item.head == Instruction.Head.CHAR_CHANGE_TEXTURE:
				found_texture = item.params.size() == 2 and item.params[1] == "demo_char_a"
		_assert(found_texture, "scene2 CHAR_CHANGE_TEXTURE 参数应为 [1, demo_char_a]")

	# --- demo_scene3 结构断言（scene/trans/wait/char wait:true） ---
	var seq3 = ResourceLoader.load("res://GalSs/demo_scene3.tres")
	if seq3 == null or seq3.seq.is_empty():
		print("FAIL: demo_scene3 无法加载或为空")
		_ok = false
	else:
		var has_mount := false
		var has_unmount := false
		var has_trans := false
		var has_wait := false
		var has_char_wait_true := false
		for item in seq3.seq:
			if item is Instruction:
				match item.head:
					Instruction.Head.SCENE_MOUNT:
						has_mount = true
					Instruction.Head.SCENE_UNMOUNT:
						has_unmount = true
					Instruction.Head.TRANSITION_OUT, Instruction.Head.TRANSITION_IN:
						has_trans = true
					Instruction.Head.WAIT:
						has_wait = true
					Instruction.Head.CHAR_SHOW_FADE, Instruction.Head.CHAR_MOVE_TO:
						if item.params[-1] == true:
							has_char_wait_true = true
		_assert(has_mount and has_unmount and has_trans and has_wait and has_char_wait_true,
			"scene3 应含 scene mount/unmount、trans、wait、char wait:true")

	# 对应 story_manager._music_play 里 play_music(stream, pos, loop) 的调用方式
	_type_check(true)

# -s 模式下 autoload 与全局类要到主循环初始化后才可用，路径断言须放在这里
func _initialize() -> void:
	# 路径策略：编辑器/CI 下一律解析到项目根（导出行为见 docs/路径策略设计.md）
	var project_root := ProjectSettings.globalize_path("res://")
	if PathManager.game_root() != project_root:
		print("FAIL: game_root = ", PathManager.game_root())
		_ok = false
	if PathManager.writable_root() != project_root:
		print("FAIL: writable_root = ", PathManager.writable_root())
		_ok = false
	var cfg_paths := PathManager.config_read_paths()
	if cfg_paths.size() != 1 or cfg_paths[0] != "res://config.json":
		print("FAIL: config_read_paths = ", cfg_paths)
		_ok = false
	print("SMOKE_TEST_DONE ok=", _ok)
	quit(0 if _ok else 1)

func _assert(cond: bool, msg: String) -> bool:
	if not cond:
		print("FAIL: ", msg)
		_ok = false
	return cond

func _type_check(x: float) -> void:
	print("bool->float 传参未报错，x = ", x)
