extends SceneTree

## BGalS v2 执行语义测试：headless 驱动真实 StoryManager/Autoload 环境，
## 逐 handler 断言行为正确性（变量/条件/选项/跳转/等待/立绘/挂载/转场/三态时机/渲染）。
## 用法：godot --headless --path . -s test/executor_test.gd
## 注意：-s 模式下 autoload 标识符编译期不可用（preload story_manager.gd 会因它引用
## Global 等而连带编译失败），一律经 root.get_node 引用；ManagerMode 枚举硬编码。

var _ok := true
var _failures: Array[String] = []

var SM  # StoryManager（Variant 以支持动态调用）
var G  # Global
var SC  # SceneManager
# StoryManager.ManagerMode: INTERACT=0, AUTO=1, SKIP=2, STOP=3（脚本无法 preload，硬编码）
const MODE_INTERACT := 0
const MODE_SKIP := 2


func _initialize() -> void:
	SM = root.get_node("StoryManager")
	G = root.get_node("Global")
	SC = root.get_node("SceneManager")
	call_deferred("_run")


func _run() -> void:
	# 等 autoload _ready 全部跑完（StoryManager 预加载 UI/Gal2D 引用）
	await process_frame
	await process_frame

	# 挂载对话 UI 与 Gal2D：池中节点不在场景树，无法 create_tween（打字机/动画依赖）
	SC.mount({
		"ui": {"对话UI": G.scenes["对话UI"], "GalUI": G.scenes["GalUI"]},
		"world2d": {"Gal2D": G.scenes["Gal2D"]},
	})
	await process_frame

	_test_var()
	_test_condition()
	_test_option()
	_test_jump_begin()
	await _test_wait()
	await _test_char()
	_test_scene()
	_test_trans_no_controller()
	await _test_three_timings()
	_test_renderer()

	print("EXECUTOR_TEST_DONE ok=", _ok, " failures=", _failures)
	quit(0 if _ok else 1)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_ok = false
		_failures.append(msg)
		print("FAIL: ", msg)


## 构造线性事件序列并装载为当前剧本
func _load_seq(items: Array[GalEventItem]) -> void:
	var s := GalEventItemSequence.new()
	s.compiler = DialogueImporter.COMPILER_VERSION
	for it in items:
		s.seq.append(it)
	SM.cur_script_name = "test_seq"
	SM.cur_script = s
	SM._build_jump_table()
	SM.idx = 0
	SM._execution_stack.clear()
	SM.current_option_end_idx = -1


func _ins(head: Instruction.Head, args: Array[String] = []) -> Instruction:
	return Instruction.new(head, args)


func _post(head: Instruction.Head, args: Array[String] = []) -> PostInstruction:
	return PostInstruction.new(head, args)


func _prev(head: Instruction.Head, args: Array[String] = []) -> PrevInstruction:
	return PrevInstruction.new(head, args)


func _dlg(text: String = "测试") -> DialogueItem:
	return DialogueItem.new("测试者", text)


# --- 用例 ---

func _test_var() -> void:
	G.vars.clear()
	_load_seq([
		_ins(Instruction.Head.VAR_SET, ["a", "3"]),
		_ins(Instruction.Head.VAR_ADD, ["a", "2"]),
		_ins(Instruction.Head.VAR_SUB, ["a", "1"]),
		_ins(Instruction.Head.VAR_MUL, ["a", "4"]),
		_ins(Instruction.Head.VAR_DIV, ["a", "0"]),   # 除零防护：值不变
		_ins(Instruction.Head.VAR_DIV, ["a", "2"]),
		_ins(Instruction.Head.VAR_SET, ["b", "a"]),   # 变量右值
		_ins(Instruction.Head.VAR_ADD, ["c", "undef"]),  # 未定义变量按 0
	])
	SM.run_script()
	_assert(G.vars.get("a", -1.0) == 8.0, "var 四则运算链 a 应为 8，实际 %s" % G.vars.get("a"))
	_assert(G.vars.get("b", -1.0) == 8.0, "var 变量右值 b 应为 8，实际 %s" % G.vars.get("b"))
	_assert(G.vars.get("c", -1.0) == 0.0, "var 未定义右值应按 0，实际 %s" % G.vars.get("c"))

	# random 种子确定性：同种子两次结果一致
	G.rng.seed = 12345
	_load_seq([_ins(Instruction.Head.VAR_RANDOM, ["r", "0", "100"])])
	SM.run_script()
	var first: float = G.vars["r"]
	G.rng.seed = 12345
	_load_seq([_ins(Instruction.Head.VAR_RANDOM, ["r", "0", "100"])])
	SM.run_script()
	_assert(G.vars["r"] == first, "var random 同种子应同值：%s vs %s" % [first, G.vars["r"]])


func _test_condition() -> void:
	G.vars.clear()
	G.vars["a"] = 5.0
	# if 真进分支；执行后栈必须归空（R9 缺陷 1 回归锁）
	_load_seq([
		_ins(Instruction.Head.IF, ["a", ">=", "5"]),
		_ins(Instruction.Head.VAR_SET, ["hit", "1"]),
		_ins(Instruction.Head.ELSE),
		_ins(Instruction.Head.VAR_SET, ["hit", "2"]),
		_ins(Instruction.Head.END_IF),
	])
	SM.run_script()
	_assert(G.vars.get("hit", 0.0) == 1.0, "if 真应进分支")
	_assert(SM._execution_stack.is_empty(), "if 结束后执行栈应为空（泄漏回归），实际 %s" % [SM._execution_stack])

	# 假 → else；且变量右值比较
	_load_seq([
		_ins(Instruction.Head.IF, ["a", "<", "5"]),
		_ins(Instruction.Head.VAR_SET, ["hit", "1"]),
		_ins(Instruction.Head.ELSE_IF, ["a", "==", "b_missing"]),  # b_missing=0，5==0 假
		_ins(Instruction.Head.VAR_SET, ["hit", "2"]),
		_ins(Instruction.Head.ELSE),
		_ins(Instruction.Head.VAR_SET, ["hit", "3"]),
		_ins(Instruction.Head.END_IF),
	])
	SM.run_script()
	_assert(G.vars.get("hit", 0.0) == 3.0, "if/elif 全假应进 else")
	_assert(SM._execution_stack.is_empty(), "elif 链结束后执行栈应为空")

	# 嵌套 if：外层真、内层假（走内层 else）
	_load_seq([
		_ins(Instruction.Head.IF, ["a", ">", "0"]),
		_ins(Instruction.Head.IF, ["a", "<", "0"]),
		_ins(Instruction.Head.VAR_SET, ["hit", "9"]),
		_ins(Instruction.Head.ELSE),
		_ins(Instruction.Head.VAR_SET, ["hit", "7"]),
		_ins(Instruction.Head.END_IF),
		_ins(Instruction.Head.END_IF),
	])
	SM.run_script()
	_assert(G.vars.get("hit", 0.0) == 7.0, "嵌套 if 应走内层 else")
	_assert(SM._execution_stack.is_empty(), "嵌套 if 结束后执行栈应为空")


func _test_option() -> void:
	G.vars.clear()
	G.vars["a"] = 1.0
	# 条件过滤：B 条件假被过滤，只剩 A/C；选第 2 项应路由到 C 分支
	_load_seq([
		_ins(Instruction.Head.OPTION, ["甲"]),
		_ins(Instruction.Head.VAR_SET, ["pick", "1"]),
		_ins(Instruction.Head.OPTION, ["乙", "a", ">", "5"]),
		_ins(Instruction.Head.VAR_SET, ["pick", "2"]),
		_ins(Instruction.Head.OPTION, ["丙", "a", "<=", "1"]),
		_ins(Instruction.Head.VAR_SET, ["pick", "3"]),
		_ins(Instruction.Head.OPTION_END),
		_ins(Instruction.Head.VAR_SET, ["after", "1"]),
	])
	SM.run_script()  # 停在选项（返回 true）
	_assert(SM._option_waiting, "选项应挂起等待")
	# 过滤后剩 2 个选项，选索引 1（丙）
	var indices: Array[int] = [1, 5]  # 各 OPTION 的下一行
	SM._on_option_made(1, indices)
	_assert(G.vars.get("pick", 0.0) == 3.0, "条件过滤后选第 2 项应路由丙，实际 %s" % G.vars.get("pick"))
	_assert(G.vars.get("after", 0.0) == 1.0, "分支结束后应执行到 OPTION_END 之后")

	# 空选项组：全部条件假 → 跳过整组不弹 UI
	G.vars.clear()
	_load_seq([
		_ins(Instruction.Head.OPTION, ["甲", "x", ">", "1"]),
		_ins(Instruction.Head.VAR_SET, ["bad", "1"]),
		_ins(Instruction.Head.OPTION_END),
		_ins(Instruction.Head.VAR_SET, ["after", "1"]),
	])
	SM.run_script()
	_assert(not SM._option_waiting, "空选项组不应挂起")
	_assert(G.vars.get("after", 0.0) == 1.0, "空选项组应跳过整组继续")


func _test_jump_begin() -> void:
	# begin 写配置
	_load_seq([_ins(Instruction.Head.SET_BEGIN_SCRIPT, ["demo_scene2"])])
	SM.run_script()
	_assert(G.config["begin_script"] == "demo_scene2", "begin 应写入 begin_script 配置")
	G.config["begin_script"] = "demo_scene1"  # 还原

	# jump main_menu 收编：指令自身返回 true（接管推进）
	_load_seq([_ins(Instruction.Head.JUMP_MAIN_MENU)])
	SM.run_script()
	# 回主菜单后 cur_script_name 不变（不加载新剧本），无崩溃即通过
	_assert(true, "jump main_menu 执行无崩溃")

	# jump main_menu 会卸载对话UI/Gal2D（回池），后续用例需要它们重新挂载
	SC.mount({
		"ui": {"对话UI": G.scenes["对话UI"]},
		"world2d": {"Gal2D": G.scenes["Gal2D"]},
	})


func _test_wait() -> void:
	# 非 SKIP：挂起并停住，timer 触发后续跑
	_load_seq([
		_ins(Instruction.Head.WAIT, ["0.3"]),
		_ins(Instruction.Head.VAR_SET, ["w", "1"]),
	])
	SM._set_manager_mode(MODE_INTERACT)
	SM.run_script()
	_assert(SM._wait_waiting, "wait 应挂起")
	_assert(not G.vars.has("w"), "wait 挂起期间后续指令不应执行")
	await create_timer(0.6).timeout
	_assert(not SM._wait_waiting and G.vars.get("w", 0.0) == 1.0, "wait 定时器触发后应继续执行")

	# SKIP 短路：不挂起直接过
	_load_seq([
		_ins(Instruction.Head.WAIT, ["5.0"]),
		_ins(Instruction.Head.VAR_SET, ["w2", "1"]),
	])
	SM._set_manager_mode(MODE_SKIP)
	SM.run_script()
	_assert(not SM._wait_waiting and G.vars.get("w2", 0.0) == 1.0, "SKIP 中 wait 应短路")
	SM._set_manager_mode(MODE_INTERACT)


func _test_char() -> void:
	var c: Character = SM.gal_world2d.characters[0]
	c.reset([], true)

	# setup 入队并自动播放（setup 是瞬时步，同步完成）
	_load_seq([
		_ins(Instruction.Head.CHAR_SETUP, ["0", "demo_char_a", "0.5", "1.0"]),
		_ins(Instruction.Head.VAR_SET, ["after_setup", "1"]),
	])
	SM.run_script()
	_assert(c.sprite2d.texture != null, "char setup 后纹理应已设置")
	_assert(G.vars.get("after_setup", 0.0) == 1.0, "setup 为异步步但不挂起剧情")

	# wait:true 挂起 → sequence_finished 恢复
	_load_seq([
		_ins(Instruction.Head.CHAR_SHOW_FADE, ["0", "0.2", "true"]),
		_ins(Instruction.Head.VAR_SET, ["after_show", "1"]),
	])
	SM.run_script()
	_assert(SM._char_waiting, "char wait:true 应挂起")
	_assert(G.vars.get("after_show", 0.0) == 0.0, "挂起期间后续不执行")
	await create_timer(0.5).timeout
	_assert(not SM._char_waiting and G.vars.get("after_show", 0.0) == 1.0,
		"sequence_finished 后应恢复执行")

	# SKIP 短路：wait:true 不挂起
	_load_seq([
		_ins(Instruction.Head.CHAR_HIDE_FADE, ["0", "0.5", "true"]),
		_ins(Instruction.Head.VAR_SET, ["after_hide", "1"]),
	])
	SM._set_manager_mode(MODE_SKIP)
	SM.run_script()
	_assert(not SM._char_waiting and G.vars.get("after_hide", 0.0) == 1.0,
		"SKIP 中 char wait:true 应短路")
	SM._set_manager_mode(MODE_INTERACT)
	c.reset([], true)


func _test_scene() -> void:
	# mount/unmount 池语义
	_load_seq([
		_ins(Instruction.Head.SCENE_MOUNT, ["ui", "测试场景", "res://Scenes/MessageUI/message_ui.tscn", "0", "fade"]),
	])
	SM.run_script()
	_assert(SC.get_scene("ui", "mounted", "测试场景") != null, "scene mount 后应在 mounted")

	_load_seq([
		_ins(Instruction.Head.SCENE_UNMOUNT, ["ui", "测试场景", "0", "fade", "false"]),
	])
	SM.run_script()
	_assert(SC.get_scene("ui", "mounted", "测试场景") == null, "scene unmount 后应移除")
	_assert(SC.get_scene("ui", "pool", "测试场景") != null, "free:false 应回池")

	# free:true 释放
	_load_seq([
		_ins(Instruction.Head.SCENE_MOUNT, ["ui", "测试场景", "res://Scenes/MessageUI/message_ui.tscn", "0", "fade"]),
		_ins(Instruction.Head.SCENE_UNMOUNT, ["ui", "测试场景", "0", "fade", "true"]),
	])
	SM.run_script()
	_assert(SC.get_scene("ui", "mounted", "测试场景") == null
		and SC.get_scene("ui", "pool", "测试场景") == null, "free:true 应释放")


func _test_trans_no_controller() -> void:
	# 无 transition_controller（headless）：wait:true 警告且不挂起
	_load_seq([
		_ins(Instruction.Head.TRANSITION_IN, ["0.1", "fade_in", "true"]),
		_ins(Instruction.Head.VAR_SET, ["after_trans", "1"]),
	])
	SM.run_script()
	_assert(not SM._trans_waiting, "无转场控制器时 trans wait:true 不应挂起")
	_assert(G.vars.get("after_trans", 0.0) == 1.0, "trans 不挂起应继续执行")


func _test_three_timings() -> void:
	# 三时机：对话 → > 后指令 → 独立指令 → < 前指令 → 对话
	G.vars.clear()
	_load_seq([
		_dlg("第一句"),
		_post(Instruction.Head.VAR_SET, ["mark_post", "1"]),
		_ins(Instruction.Head.VAR_SET, ["mark_free", "1"]),
		_prev(Instruction.Head.VAR_SET, ["mark_prev", "1"]),
		_dlg("第二句"),
	])
	SM._set_manager_mode(MODE_INTERACT)
	SM.run_script()  # 停在第一句
	_assert(G.vars.is_empty(), "打字中任何指令都不应执行")

	SM.dialogue_ui.skip_typing()  # 打字完成 → 消费后指令+独立指令
	await process_frame
	_assert(G.vars.get("mark_post", 0.0) == 1.0, "打字完成后后指令应立即执行")
	_assert(G.vars.get("mark_free", 0.0) == 1.0, "打字完成后独立指令应立即执行")
	_assert(G.vars.get("mark_prev", 0.0) == 0.0, "前指令必须等点击推进才执行")

	SM._advance()  # 模拟点击推进
	await process_frame
	_assert(G.vars.get("mark_prev", 0.0) == 1.0, "推进后前指令才执行")
	# 推进后停在第二句
	SM.dialogue_ui.skip_typing()
	await process_frame


func _test_renderer() -> void:
	# 锚点剥离与索引（索引 = 显示文本字符串位置）
	G.vars.clear()
	G.vars["affection"] = 3.0
	var r := DialogueRenderer.render("前半[sfx demo_bgm]后半{affection}", G.vars)
	_assert(r["text"] == "前半后半3", "渲染文本应为「前半后半3」，实际「%s」" % r["text"])
	_assert(r["anchors"].size() == 1 and r["anchors"][0]["index"] == 2
		and r["anchors"][0]["ins"].head == Instruction.Head.SFX_PLAY,
		"锚点应在索引 2 且为 SFX_PLAY，实际 %s" % [r["anchors"]])

	# 转义与 BBCode 保留
	r = DialogueRenderer.render("\\[sfx x][b]粗[/b]", G.vars)
	_assert(r["text"] == "[sfx x][b]粗[/b]" and r["anchors"].is_empty(),
		"转义与 BBCode 保留失败：%s" % r)

	# [pause] 特化为打字机停顿（WAIT 指令）
	r = DialogueRenderer.render("停[pause 0.5]一下", G.vars)
	_assert(r["anchors"].size() == 1 and r["anchors"][0]["ins"].head == Instruction.Head.WAIT,
		"[pause] 应特化为 WAIT 锚点")

	# 未定义插值按 0
	r = DialogueRenderer.render("值{undef_var}。", G.vars)
	_assert(r["text"] == "值0。", "未定义插值应按 0，实际「%s」" % r["text"])
