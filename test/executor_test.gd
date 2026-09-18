extends SceneTree

## BGalS v2 执行语义测试：headless 驱动真实 StoryManager/Autoload 环境，
## 逐 handler 断言行为正确性（变量/条件/选项/跳转/等待/立绘/挂载/转场/三态时机/渲染）。
## 用法：godot --headless --path . -s test/executor_test.gd
## 注意：-s 模式下 autoload 标识符编译期不可用（preload story_manager.gd 会因它引用
## Global 等而连带编译失败），一律经 root.get_node 引用；Synchronizer.Mode 经 SYNC.Mode 实例动态访问。

var _ok := true
var _failures: Array[String] = []

var SM  # StoryManager（Variant 以支持动态调用）
var G  # Global
var SC  # SceneManager
var SYNC  # Synchronizer（Variant 以支持动态调用；模式枚举用 Synchronizer.Mode）


func _initialize() -> void:
	SM = root.get_node("StoryManager")
	G = root.get_node("Global")
	SC = root.get_node("SceneManager")
	SYNC = root.get_node("Synchronizer")
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
	await _test_condition()
	await _test_option()
	await _test_choice_replay()
	_test_jump_begin()
	await _test_wait()
	await _test_char()
	_test_scene()
	_test_trans_no_controller()
	_test_sync()
	await _test_anchor_wait()
	await _test_three_timings()
	_test_renderer()
	await _test_audio()

	print("EXECUTOR_TEST_DONE ok=", _ok, " failures=", _failures)
	quit(0 if _ok else 1)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_ok = false
		_failures.append(msg)
		print("FAIL: ", msg)


## 构造线性事件序列并装载为当前剧本（条件结构请用 _load_text——v2.3 起跳转目标由编译期回填）
func _load_seq(items: Array[GalEventItem]) -> void:
	var s := GalEventItemSequence.new()
	s.compiler = DialogueImporter.COMPILER_VERSION
	for it in items:
		s.seq.append(it)
	SM.cur_script_name = "test_seq"
	SM.cur_script = s
	SM.idx = 0
	SM._execution_stack.clear()
	SYNC.preempt(SYNC.PRIO_RESET)  # 清挂起但不动模式（模式由用例自管）


## 经真实编译器构造并装载剧本（测试脚本应零诊断）
func _load_text(lines: Array) -> void:
	var diags: Array[Dictionary] = []
	var compiled := DialogueImporter.parse_script(PackedStringArray(lines), "test_text", diags)
	_assert(diags.is_empty(), "测试脚本应零诊断: %s" % [diags])
	SM.cur_script_name = "test_text"
	SM.cur_script = compiled
	SM.idx = 0
	SM._execution_stack.clear()
	SYNC.preempt(SYNC.PRIO_RESET)  # 清挂起但不动模式（模式由用例自管）


## 当前剧本可见选项的分支体起始索引（条件经运行时求值过滤，与 _option_begin 同口径）
func _visible_option_indices() -> Array[int]:
	var out: Array[int] = []
	for i in range(SM.cur_script.seq.size()):
		var it = SM.cur_script.seq[i]
		if it is Instruction and it.head == Instruction.Head.OPTION:
			var tokens: Array = it.params[1]
			if tokens.is_empty() or SM._eval_condition(tokens):
				out.append(i + 1)
	return out


func _ins(head: Instruction.Head, args: Array[String] = []) -> Instruction:
	return Instruction.from_strings(head, args)


func _post(head: Instruction.Head, args: Array[String] = []) -> PostInstruction:
	return PostInstruction.from_strings(head, args)


func _prev(head: Instruction.Head, args: Array[String] = []) -> PrevInstruction:
	return PrevInstruction.from_strings(head, args)


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


## 条件分支执行语义：经真实编译器构造（v2.3 起条件为编译期记号流 + 跳转目标回填，手工构造无法模拟）
## 分组：分支选择 / 复合条件 / 对话与选项交互 / SKIP 与防御
func _test_condition() -> void:
	G.vars.clear()
	G.vars["a"] = 5.0
	G.vars["b"] = 0.0

	# --- 分支选择 ---

	# if 真进分支；执行后栈必须归空（R9 缺陷 1 回归锁）
	_load_text([
		"if a >= 5",
		"    var hit = 1",
		"else",
		"    var hit = 2",
	])
	SM.run_script()
	_assert(G.vars.get("hit", 0.0) == 1.0, "if 真应进分支")
	_assert(SM._execution_stack.is_empty(), "if 结束后执行栈应为空（泄漏回归），实际 %s" % [SM._execution_stack])

	# 假 → else；变量右值比较（b_missing 未定义按 0）
	_load_text([
		"if a < 5",
		"    var hit = 1",
		"elif a == b_missing",
		"    var hit = 2",
		"else",
		"    var hit = 3",
	])
	SM.run_script()
	_assert(G.vars.get("hit", 0.0) == 3.0, "if/elif 全假应进 else")
	_assert(SM._execution_stack.is_empty(), "elif 链结束后执行栈应为空")

	# 嵌套 if：外层真、内层假（走内层 else）
	_load_text([
		"if a > 0",
		"    if a < 0",
		"        var hit = 9",
		"    else",
		"        var hit = 7",
	])
	SM.run_script()
	_assert(G.vars.get("hit", 0.0) == 7.0, "嵌套 if 应走内层 else")
	_assert(SM._execution_stack.is_empty(), "嵌套 if 结束后执行栈应为空")

	# 短路：if 真则后续 elif/else 不评估不执行
	_load_text([
		"if a >= 5",
		"    var hit = 1",
		"elif a >= 5",
		"    var hit = 2",
		"else",
		"    var hit = 3",
	])
	SM.run_script()
	_assert(G.vars.get("hit", 0.0) == 1.0, "if 真时 elif/else 不得执行（短路），实际 %s" % G.vars.get("hit"))
	_assert(SM._execution_stack.is_empty(), "短路后执行栈应为空")

	# elif 真则 else 跳过
	_load_text([
		"if a < 5",
		"    var hit = 1",
		"elif a == 5",
		"    var hit = 2",
		"else",
		"    var hit = 3",
	])
	SM.run_script()
	_assert(G.vars.get("hit", 0.0) == 2.0, "elif 真时 else 不得执行，实际 %s" % G.vars.get("hit"))
	_assert(SM._execution_stack.is_empty(), "elif 命中后执行栈应为空")

	# 外层假：内层整条链不得到达（编译期目标回填正确性）
	_load_text([
		"if a < 0",
		"    if a >= 5",
		"        var hit = 1",
		"    else",
		"        var hit = 2",
		"var hit = 3",
	])
	SM.run_script()
	_assert(G.vars.get("hit", 0.0) == 3.0, "外层假应跳过整个内层链，实际 %s" % G.vars.get("hit"))
	_assert(SM._execution_stack.is_empty(), "外层跳过后执行栈应为空")

	# --- 复合条件（and/or/not/括号/裸变量真值）---

	# and 优先于 or：a>=1(T) or b>=1(F) and b==9(F) → T or F = T
	_load_text([
		"if a >= 1 or b >= 1 and b == 9",
		"    var hit = 1",
		"else",
		"    var hit = 2",
	])
	SM.run_script()
	_assert(G.vars.get("hit", 0.0) == 1.0, "and 应优先于 or（T or F and F = T），实际 %s" % G.vars.get("hit"))

	# 括号覆盖优先级：(T or F) and F = F
	_load_text([
		"if (a >= 1 or b >= 1) and b == 9",
		"    var hit = 1",
		"else",
		"    var hit = 2",
	])
	SM.run_script()
	_assert(G.vars.get("hit", 0.0) == 2.0, "括号应改变优先级（(T or F) and F = F），实际 %s" % G.vars.get("hit"))

	# not 与括号嵌套：not (T and T) = F
	_load_text([
		"if not (a >= 5 and b == 0)",
		"    var hit = 1",
		"else",
		"    var hit = 2",
	])
	SM.run_script()
	_assert(G.vars.get("hit", 0.0) == 2.0, "not(真 and 真) 应为假，实际 %s" % G.vars.get("hit"))

	# 裸变量真值：非 0 为真
	_load_text(["if a", "    var hit = 1"])
	SM.run_script()
	_assert(G.vars.get("hit", 0.0) == 1.0, "裸变量 a=5 应为真")
	_load_text([
		"if b",
		"    var hit = 9",
		"else",
		"    var hit = 2",
	])
	SM.run_script()
	_assert(G.vars.get("hit", 0.0) == 2.0, "裸变量 b=0 应为假")
	_load_text(["if not b", "    var hit = 1"])
	SM.run_script()
	_assert(G.vars.get("hit", 0.0) == 1.0, "not b（b=0）应为真")

	# 变量与变量比较
	_load_text(["if a == a", "    var hit = 1"])
	SM.run_script()
	_assert(G.vars.get("hit", 0.0) == 1.0, "变量与自身应 ==")

	# --- 与对话回合的交互 ---

	# 分支内对话停止点：执行栈跨回合存活；else 分支对话不得显示
	_load_text([
		"if a >= 5",
		"    引路人: 真分支",
		"else",
		"    引路人: 假分支",
		"引路人: 结构后",
	])
	SM.run_script()  # 停在真分支对话
	_assert(SM.dialogue_ui.current_dialogue_content == "真分支",
		"应停在真分支对话，实际 %s" % SM.dialogue_ui.current_dialogue_content)
	_assert(SM._execution_stack.size() == 1, "对话停止点期间执行栈应保持一层，实际 %s" % [SM._execution_stack])
	SM.dialogue_ui.skip_typing()  # 打字完成窗口消费 ELSE/END_IF
	_assert(SM._execution_stack.is_empty(), "离开结构后执行栈应为空")
	SM._advance()  # 推进到结构后对话
	_assert(SM.dialogue_ui.current_dialogue_content == "结构后",
		"else 分支对话不得显示，实际 %s" % SM.dialogue_ui.current_dialogue_content)

	# 假分支对话不显示（else 命中）
	_load_text([
		"if a < 0",
		"    引路人: 假分支",
		"else",
		"    引路人: else分支",
	])
	SM.run_script()
	_assert(SM.dialogue_ui.current_dialogue_content == "else分支",
		"if 假应直接显示 else 分支对话，实际 %s" % SM.dialogue_ui.current_dialogue_content)

	# --- 与选项的交互 ---

	# 分支内选项组：条件真时选项照常弹出并可选
	_load_text([
		"if a >= 5",
		"    * 甲",
		"        var hit = 1",
		"    * 乙",
		"        var hit = 2",
		"    var after = 1",
	])
	SM.run_script()
	_assert(SYNC.has_kind(&"option"), "分支内选项组应挂起等待")
	SM._option_indices = _visible_option_indices()
	SM._on_option_made(0)
	_assert(G.vars.get("hit", 0.0) == 1.0 and G.vars.get("after", 0.0) == 1.0,
		"分支内选项选择后应走完分支体，实际 hit=%s after=%s" % [G.vars.get("hit"), G.vars.get("after")])
	_assert(SM._execution_stack.is_empty(), "分支内选项结束后执行栈应为空")

	# 选项块内 if 分流
	_load_text([
		"* 甲",
		"    if a >= 5",
		"        var hit = 1",
		"    else",
		"        var hit = 2",
		"* 乙",
		"    var hit = 3",
	])
	SM.run_script()
	_assert(SYNC.has_kind(&"option"), "选项组应挂起等待")
	SM._option_indices = _visible_option_indices()
	SM._on_option_made(0)  # 选甲 → 块内 if 真
	_assert(G.vars.get("hit", 0.0) == 1.0, "选项块内 if 真应走真分支，实际 %s" % G.vars.get("hit"))
	_assert(SM._execution_stack.is_empty(), "选项块内 if 结束后执行栈应为空")

	# --- SKIP 与防御 ---

	# SKIP 穿越分支：真路径对话照样流过，假分支不显示
	SYNC.mode = SYNC.Mode.SKIP  # SKIP
	_load_text([
		"if a >= 5",
		"    引路人: SKIP真",
		"else",
		"    引路人: SKIP假",
		"引路人: SKIP后",
	])
	SM.run_script()
	await create_timer(0.5).timeout  # SKIP 以 0 延时定时器连续推进
	_assert(SM.dialogue_ui.current_dialogue_content == "SKIP后",
		"SKIP 应穿越真分支停在结构后，实际 %s" % SM.dialogue_ui.current_dialogue_content)
	_assert(SM._execution_stack.is_empty(), "SKIP 穿越后执行栈应为空")
	SYNC.mode = SYNC.Mode.INTERACT  # 还原 INTERACT

	# 空栈守卫回归：孤立 ELSE/ELSE_IF/END_IF 不崩溃、不死循环、顺序继续
	#（编译期已拦截，此处锁运行期防御行为；产物损毁时顺序继续优于崩死）
	_load_seq([
		_ins(Instruction.Head.ELSE),
		_ins(Instruction.Head.END_IF),
		_ins(Instruction.Head.ELSE_IF),
		_ins(Instruction.Head.VAR_SET, ["hit", "9"]),
	])
	SM.run_script()
	_assert(SM._execution_stack.is_empty(), "孤立分支指令后执行栈应为空")
	_assert(G.vars.get("hit", 0.0) == 9.0, "守卫后应顺序继续执行")


## 选项执行语义：条件过滤 / 路由 / 空组跳过（text-driven，与 _test_condition 同构造路径）
func _test_option() -> void:
	G.vars.clear()
	G.vars["a"] = 1.0
	# 条件过滤：乙条件假被过滤，只剩甲/丙；选可见第 2 项应路由到丙分支
	_load_text([
		"* 甲",
		"    var pick = 1",
		"* 乙 if:a > 5",
		"    var pick = 2",
		"* 丙 if:a <= 1",
		"    var pick = 3",
		"var after = 1",
	])
	SM.run_script()  # 停在选项（返回 true）
	_assert(SYNC.has_kind(&"option"), "选项应挂起等待")
	var indices := _visible_option_indices()
	_assert(indices.size() == 2, "条件过滤后应剩 2 个选项，实际 %d" % indices.size())
	SM._option_indices = indices
	SM._on_option_made(1)  # 选可见第 2 项（丙）
	_assert(G.vars.get("pick", 0.0) == 3.0, "条件过滤后选第 2 项应路由丙，实际 %s" % G.vars.get("pick"))
	_assert(G.vars.get("after", 0.0) == 1.0, "分支结束后应执行到 OPTION_END 之后")

	# 空选项组：全部条件假 → 跳过整组不弹 UI
	G.vars.clear()
	_load_text([
		"* 甲 if:x > 1",
		"    var bad = 1",
		"var after = 1",
	])
	SM.run_script()
	_assert(not SYNC.has_kind(&"option"), "空选项组不应挂起")
	_assert(G.vars.get("after", 0.0) == 1.0, "空选项组应跳过整组继续")

	# 选项文本 {var} 插值（与对话同口径，经 DialogueRenderer.render_plain）
	G.vars.clear()
	G.vars["gold"] = 50.0
	_load_text([
		"* 赎他（现有 {gold} 金币）",
		"    var pick = 1",
	])
	SM.run_script()
	await create_timer(0.6).timeout  # 选项 UI 在对话框淡出完成后弹出
	var btn_texts: Array = []
	for c in SM.option_ui.vbox.get_children():
		btn_texts.append(c.text)
	_assert(btn_texts == ["赎他（现有 50 金币）"], "选项文本应插值，实际 %s" % [btn_texts])
	SM._option_indices = _visible_option_indices()
	SM._on_option_made(0)


## 选项选择序列与确定性重放（存档 v3）：选择入序列；重放自动选定记录分支、不弹 UI 不挂起
func _test_choice_replay() -> void:
	G.vars.clear()
	# 选择序列按周目累积，本用例自成一周目：清空序列与游标
	SM._choice_log.clear()
	SM._choice_cursor = 0
	_load_text([
		"* 甲",
		"    var pick = 1",
		"* 乙",
		"    var pick = 2",
		"旁白: 结尾",
	])
	SM.run_script()
	_assert(SYNC.has_kind(&"option"), "选项组应挂起等待")
	SM._option_indices = _visible_option_indices()
	SM._on_option_made(1)  # 选乙
	_assert(G.vars.get("pick", 0.0) == 2.0, "首次游玩应走乙分支")
	_assert(SM._choice_log.size() == 1, "选择应记入序列，实际 %s" % [SM._choice_log])

	# 模拟读档重放：同剧本从头 SKIP 重放，选项组自动选定记录分支（不弹 UI、不挂起）
	G.vars.clear()
	SM.idx = 0
	SM._execution_stack.clear()
	SM._replay_end = 6  # 剧本尾（seq 共 6 项；终点判定在对话停止点）
	SYNC.mode = SYNC.Mode.SKIP
	SM.run_script()
	await create_timer(0.5).timeout
	_assert(G.vars.get("pick", 0.0) == 2.0, "重放应自动走记录的乙分支，实际 %s" % G.vars.get("pick"))
	_assert(not SYNC.has_kind(&"option"), "重放中选项组不得挂起弹 UI")
	_assert(SM._replay_end == -1, "重放到点应结束（_replay_end 复位）")
	SYNC.mode = SYNC.Mode.INTERACT


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
	SYNC.mode = SYNC.Mode.INTERACT
	SM.run_script()
	_assert(SYNC.has_kind(&"wait"), "wait 应挂起")
	_assert(not G.vars.has("w"), "wait 挂起期间后续指令不应执行")
	await create_timer(0.6).timeout
	_assert(not SYNC.has_kind(&"wait") and G.vars.get("w", 0.0) == 1.0, "wait 定时器触发后应继续执行")

	# SKIP 短路：不挂起直接过
	_load_seq([
		_ins(Instruction.Head.WAIT, ["5.0"]),
		_ins(Instruction.Head.VAR_SET, ["w2", "1"]),
	])
	SYNC.mode = SYNC.Mode.SKIP
	SM.run_script()
	_assert(not SYNC.has_kind(&"wait") and G.vars.get("w2", 0.0) == 1.0, "SKIP 中 wait 应短路")
	SYNC.mode = SYNC.Mode.INTERACT


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
	_assert(SYNC.has_kind(&"char"), "char wait:true 应挂起")
	_assert(G.vars.get("after_show", 0.0) == 0.0, "挂起期间后续不执行")
	await create_timer(0.5).timeout
	_assert(not SYNC.has_kind(&"char") and G.vars.get("after_show", 0.0) == 1.0,
		"sequence_finished 后应恢复执行")

	# SKIP 短路：wait:true 不挂起
	_load_seq([
		_ins(Instruction.Head.CHAR_HIDE_FADE, ["0", "0.5", "true"]),
		_ins(Instruction.Head.VAR_SET, ["after_hide", "1"]),
	])
	SYNC.mode = SYNC.Mode.SKIP
	SM.run_script()
	_assert(not SYNC.has_kind(&"char") and G.vars.get("after_hide", 0.0) == 1.0,
		"SKIP 中 char wait:true 应短路")
	SYNC.mode = SYNC.Mode.INTERACT
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
	_assert(not SYNC.has_kind(&"trans"), "无转场控制器时 trans wait:true 不应挂起")
	_assert(G.vars.get("after_trans", 0.0) == 1.0, "trans 不挂起应继续执行")


## 同步器专项：注册表/短路/优先级抢占/处置回调/依赖级联/跃迁单次发射
func _test_sync() -> void:
	SYNC.preempt(SYNC.PRIO_RESET)
	SYNC.mode = SYNC.Mode.INTERACT

	# acquire/release 基本语义
	var id0: int = SYNC.acquire(&"wait")
	_assert(id0 != -1 and SYNC.has_kind(&"wait"), "acquire 后应有 wait 挂起")
	SYNC.release(id0)
	_assert(not SYNC.has_kind(&"wait"), "release 后挂起应清空")

	# SKIP 短路（非免疫类别不产生挂起；option 为 skip_immune）
	SYNC.mode = SYNC.Mode.SKIP
	_assert(SYNC.acquire(&"wait") == -1, "SKIP 中 wait 应短路返回 INVALID")
	_assert(SYNC.acquire(&"option") != -1, "SKIP 中 option（skip_immune）仍应真实挂起")
	SYNC.preempt(SYNC.PRIO_RESET)
	SYNC.mode = SYNC.Mode.INTERACT

	# 优先级抢占：option（阈值 PRIO_RESET）在点击下存活，wait 被 KILL
	SYNC.acquire(&"option")
	SYNC.acquire(&"wait")
	SYNC.preempt(SYNC.PRIO_CLICK)
	_assert(SYNC.has_kind(&"option") and not SYNC.has_kind(&"wait"),
		"点击抢占应 KILL wait 而保留 option（阈值保护）")
	SYNC.preempt(SYNC.PRIO_RESET)
	_assert(not SYNC.has_kind(&"option"), "RESET 应清掉 option")

	# FAST_FORWARD 处置回调（on_fast_forward 被调用并释放）
	var ff := [false]
	SYNC.acquire(&"char", null, func(): ff[0] = true)
	SYNC.preempt(SYNC.PRIO_CLICK)
	_assert(ff[0] and not SYNC.has_kind(&"char"), "CHAR 抢占应回调 on_fast_forward 并释放")

	# 依赖图预留：B 依赖 A；A 释放后 B 级联清空，门闸随之放开
	var id_a: int = SYNC.acquire(&"wait")
	var deps: Array[int] = [id_a]
	SYNC.acquire(&"wait", null, Callable(), Callable(), deps)
	_assert(not SYNC.is_clear(), "依赖未清空前门闸应被堵")
	SYNC.release(id_a)
	_assert(SYNC.is_clear(), "A 释放后依赖它的 B 应级联清空")

	# holds_cleared 只在跃迁时发射一次
	var fired := [0]
	var cb := func(): fired[0] += 1
	SYNC.holds_cleared.connect(cb)
	var w1: int = SYNC.acquire(&"wait")
	var w2: int = SYNC.acquire(&"wait")
	SYNC.release(w1)
	_assert(fired[0] == 0, "仍有挂起时不应发射 holds_cleared")
	SYNC.release(w2)
	_assert(fired[0] == 1, "全部清空应发射恰好一次")
	SYNC.holds_cleared.disconnect(cb)


## 锚点 wait:true（同步器转正）：打字中途触发的 char 挂起阻塞 AUTO 自动推进；点击打断直达终态
func _test_anchor_wait() -> void:
	var c: Character = SM.gal_world2d.characters[0]
	c.reset([], true)
	var saved_wait: float = G.auto_wait_time
	G.auto_wait_time = 0.2

	# AUTO：锚点挂起阻塞自动推进，动画完成后经重布推进
	_load_text([
		"演[char 0 show time:0.5 wait:true]出",
		"下一句",
	])
	SYNC.mode = SYNC.Mode.AUTO
	SM.run_script()  # 开始打字；锚点在显示文本第 2 位，随即触发
	await create_timer(0.4).timeout
	_assert(SYNC.has_kind(&"char"), "锚点 char wait:true 应产生挂起")
	var idx1: int = SM.idx
	await create_timer(0.2).timeout  # 动画未完，AUTO 预约被门闸拦截
	_assert(SM.idx == idx1, "锚点挂起期间 AUTO 不得推进")
	await create_timer(1.2).timeout  # 动画完成（0.5s）→ 释放 → 重布 0.2s 后推进
	_assert(SM.idx > idx1, "动画完成后 AUTO 应推进")

	# 点击打断（房规）：挂起被 FAST_FORWARD 处置后放行
	_load_text([
		"演[char 0 hide time:2.0 wait:true]出",
		"再下一句",
	])
	SYNC.mode = SYNC.Mode.INTERACT
	SM.run_script()
	await create_timer(0.3).timeout
	_assert(SYNC.has_kind(&"char"), "锚点挂起应已产生")
	SM.dialogue_ui.skip_typing()  # 点击的第一语义：先跳完打字
	SM._advance()  # 第二语义：preempt → skip_all 直达终态 + 放行
	_assert(not SYNC.has_kind(&"char"), "点击应打断锚点挂起（FAST_FORWARD 处置）")

	G.auto_wait_time = saved_wait
	SYNC.mode = SYNC.Mode.INTERACT
	c.reset([], true)


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
	SYNC.mode = SYNC.Mode.INTERACT
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

	# render_plain（选项等无锚点时间轴的 UI 文本）：转义 + 插值，方括号原样保留
	var plain := DialogueRenderer.render_plain("好感 {affection} \\{x} [sfx demo_bgm]", G.vars)
	_assert(plain == "好感 3 {x} [sfx demo_bgm]",
		"render_plain 应插值+转义且保留方括号，实际「%s」" % plain)


## 音频指令执行语义：headless 无声驱动下只断言状态位（playing/volume_db/loop 标志），不断言听感
## AudioManager 无 class_name，-s 下只能 root.get_node 动态调用；Bus 枚举硬编码（MASTER=0, MUSIC=1, SFX=2, VOICE=3）
func _test_audio() -> void:
	var AM = root.get_node("AudioManager")
	var music_mgr = AM.music_manager
	var sfx_mgr = AM.sfx_manager
	var voice_mgr = AM.voice_manager
	var music_bus := AudioServer.get_bus_index("Music")
	var saved_db := AudioServer.get_bus_volume_db(music_bus)
	# jump main_menu 用例会在主菜单起 BGM，先清场
	AM.stop_music(0.0)
	AM.stop_all_sfx(0.0)
	AM.stop_voice(0.0)
	await process_frame
	await process_frame

	# 双重衰减回归：总线 -6dB 时播放器 volume_db 应 tween 到曲目响度 0dB，不背总线快照
	AudioServer.set_bus_volume_db(music_bus, -6.0)
	_load_seq([_ins(Instruction.Head.MUSIC_PLAY, ["demo_bgm", "0", "true", "0", "0", "1.0"])])
	SM.run_script()
	await process_frame
	await process_frame
	var cur: AudioStreamPlayer = music_mgr.players[music_mgr.cur_player_index]
	_assert(cur.playing, "music play 后当前播放器应在播")
	_assert(absf(cur.volume_db) < 0.01,
		"双重衰减回归：播放器 volume_db 应为 0dB（不背总线 -6 快照），实际 %s" % cur.volume_db)

	# volume 参数落盘：0.5 → linear_to_db(0.5)
	AM.stop_music(0.0)
	await process_frame
	await process_frame
	_load_seq([_ins(Instruction.Head.MUSIC_PLAY, ["demo_bgm", "0", "true", "0", "0", "0.5"])])
	SM.run_script()
	await process_frame
	await process_frame
	cur = music_mgr.players[music_mgr.cur_player_index]
	_assert(absf(cur.volume_db - linear_to_db(0.5)) < 0.01,
		"music volume:0.5 应落盘为 %.2f dB，实际 %s" % [linear_to_db(0.5), cur.volume_db])

	# pause/resume 作用于全部在播音轨；stop 后全停
	AM.pause_music()
	var any_unpaused := false
	for p in music_mgr.players:
		if p.playing and not p.stream_paused:
			any_unpaused = true
	_assert(not any_unpaused, "music pause 应暂停所有在播音轨")
	AM.resume_music()
	_assert(cur.playing and not cur.stream_paused, "music resume 后应恢复播放")
	AM.stop_music(0.0)
	await process_frame
	await process_frame
	var any_music := false
	for p in music_mgr.players:
		if p.playing:
			any_music = true
	_assert(not any_music, "music stop 后应无在播音轨")

	# sfx 空闲优先：连播两条各占一台播放器
	_load_seq([_ins(Instruction.Head.SFX_PLAY, ["demo_bgm", "0", "1.0", "false"]),
		_ins(Instruction.Head.SFX_PLAY, ["demo_bgm", "0", "1.0", "false"])])
	SM.run_script()
	var playing_sfx := 0
	for p in sfx_mgr.players:
		if p.playing:
			playing_sfx += 1
	_assert(playing_sfx == 2, "两条 sfx 应各占一台播放器，实际 %d" % playing_sfx)

	# sfx stop 指定引用：按流身份匹配停止（两台都是 demo_bgm，应全停）
	_load_seq([_ins(Instruction.Head.SFX_STOP, ["demo_bgm", "0"])])
	SM.run_script()
	await process_frame
	await process_frame
	playing_sfx = 0
	for p in sfx_mgr.players:
		if p.playing:
			playing_sfx += 1
	_assert(playing_sfx == 0, "sfx stop demo_bgm 后应全停，实际 %d" % playing_sfx)

	# sfx loop:true 设置流内循环标志
	_load_seq([_ins(Instruction.Head.SFX_PLAY, ["demo_bgm", "0", "1.0", "true"])])
	SM.run_script()
	var wav := ResourceLoader.load("res://Resources/audio/demo_bgm.wav") as AudioStreamWAV
	_assert(wav != null and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"sfx loop:true 应设置流内循环标志")
	AM.stop_all_sfx(0.0)

	# voice：play 在播 + volume 落盘；voice stop 停止
	_load_seq([_ins(Instruction.Head.VOICE_PLAY, ["demo_bgm", "0", "0.5"])])
	SM.run_script()
	_assert(voice_mgr.player.playing, "voice play 后应在播")
	_assert(absf(voice_mgr.player.volume_db - linear_to_db(0.5)) < 0.01,
		"voice volume:0.5 应落盘，实际 %s" % voice_mgr.player.volume_db)
	_load_seq([_ins(Instruction.Head.VOICE_STOP, ["0"])])
	SM.run_script()
	await process_frame
	await process_frame
	_assert(not voice_mgr.player.playing, "voice stop 后应停止")

	# --- 评审修复回归 ---

	# 同曲守卫不得吞掉「淡出中的同曲重开」（读档/跳幕同 BGM 场景）
	AM.stop_music(0.0)
	await process_frame
	await process_frame
	var s_cached = root.get_node("ResourceManager").load("audio", "demo_bgm")
	AM.play_music(s_cached, 0, 0, 0, true, 1.0)
	await process_frame
	await process_frame
	AM.stop_music(1.0)  # 1 秒淡出窗口内
	AM.play_music(s_cached, 0, 0, 0, true, 1.0)  # 同曲立即重开
	await create_timer(1.5).timeout
	var still_playing := false
	for p in music_mgr.players:
		if p.playing:
			still_playing = true
	_assert(still_playing, "淡出窗口内同曲重开不应被守卫吞掉（A2 回归）")

	# 快速连切 A→B→C：C 的音量不得被残留淡入 tween 劫持（播放器复用 tween 防护）
	AM.stop_music(0.0)
	await process_frame
	await process_frame
	var s_b = ResourceLoader.load("res://Resources/audio/demo_bgm.wav", "", ResourceLoader.CACHE_MODE_IGNORE)
	var s_c = ResourceLoader.load("res://Resources/audio/demo_bgm.wav", "", ResourceLoader.CACHE_MODE_IGNORE)
	AM.play_music(s_cached, 0, 1.0, 2.0, true, 0.2)  # A：2 秒淡入向 0.2
	await process_frame
	AM.play_music(s_b, 0, 0, 0, true, 1.0)  # B
	await process_frame
	AM.play_music(s_c, 0, 0, 0, true, 1.0)  # C（轮转回 A 的播放器）
	await create_timer(0.5).timeout
	cur = music_mgr.players[music_mgr.cur_player_index]
	_assert(absf(cur.volume_db) < 0.01,
		"连切后当前音轨音量应为 0dB（不被残留 tween 劫持），实际 %s" % cur.volume_db)
	AM.stop_music(0.0)
	await process_frame
	await process_frame

	# music volume 子动作：不重启曲目直接调响度
	_load_seq([_ins(Instruction.Head.MUSIC_PLAY, ["demo_bgm", "0", "true", "0", "0", "1.0"])])
	SM.run_script()
	await process_frame
	await process_frame
	_load_seq([_ins(Instruction.Head.MUSIC_VOLUME, ["0.3", "0"])])
	SM.run_script()
	await process_frame
	await process_frame
	cur = music_mgr.players[music_mgr.cur_player_index]
	_assert(absf(cur.volume_db - linear_to_db(0.3)) < 0.01,
		"music volume 0.3 应落盘，实际 %s" % cur.volume_db)
	AM.stop_music(0.0)

	# sfx stop 按流身份匹配：只停指定引用，不误停其他实例
	var s_fresh = ResourceLoader.load("res://Resources/audio/demo_bgm.wav", "", ResourceLoader.CACHE_MODE_IGNORE)
	_load_seq([_ins(Instruction.Head.SFX_PLAY, ["demo_bgm", "0", "1.0", "false"])])  # 缓存实例
	SM.run_script()
	AM.play_sfx(s_fresh, 0, 1.0, false)  # 独立实例
	_load_seq([_ins(Instruction.Head.SFX_STOP, ["demo_bgm", "0"])])
	SM.run_script()
	await process_frame
	await process_frame
	var cached_playing := false
	var fresh_playing := false
	for p in sfx_mgr.players:
		if p.playing and p.stream == s_cached:
			cached_playing = true
		if p.playing and p.stream == s_fresh:
			fresh_playing = true
	_assert(not cached_playing and fresh_playing,
		"sfx stop 应只停匹配引用（缓存实例停、独立实例仍在播）")
	AM.stop_all_sfx(0.0)
	await process_frame
	await process_frame

	# sfx stop 渐变路径（fade>0，DSL 通路）：先淡出后停止
	_load_seq([_ins(Instruction.Head.SFX_PLAY, ["demo_bgm", "0", "1.0", "false"])])
	SM.run_script()
	_load_seq([_ins(Instruction.Head.SFX_STOP, ["demo_bgm", "0.2"])])
	SM.run_script()
	await process_frame
	var fading := false
	for p in sfx_mgr.players:
		if p.playing:
			fading = true
	_assert(fading, "sfx stop fade:0.2 后应处于淡出中（尚未停止）")
	await create_timer(0.4).timeout
	var any_sfx := false
	for p in sfx_mgr.players:
		if p.playing:
			any_sfx = true
	_assert(not any_sfx, "sfx 淡出结束后应全部停止")

	# voice 复位共享流的 loop 污染
	_load_seq([_ins(Instruction.Head.SFX_PLAY, ["demo_bgm", "0", "1.0", "true"])])
	SM.run_script()
	AM.stop_all_sfx(0.0)
	_load_seq([_ins(Instruction.Head.VOICE_PLAY, ["demo_bgm", "0", "1.0"])])
	SM.run_script()
	var wav2 := ResourceLoader.load("res://Resources/audio/demo_bgm.wav") as AudioStreamWAV
	_assert(wav2.loop_mode == AudioStreamWAV.LOOP_DISABLED,
		"voice 播放应复位流内循环标志（不受先前 sfx loop:true 污染）")
	AM.stop_voice(0.0)

	# F1 回归：pause → 换曲 → resume 不得双 BGM 同响（旧暂停轨须被换曲停掉）
	AM.play_music(s_cached, 0, 0, 0, true, 1.0)
	await process_frame
	await process_frame
	AM.pause_music()
	AM.play_music(s_b, 0, 0, 0, true, 1.0)  # 换曲（旧暂停轨随之停止）
	await process_frame
	await process_frame
	AM.resume_music()
	await process_frame
	var sounding := 0
	for p in music_mgr.players:
		if p.playing and not p.stream_paused:
			sounding += 1
	_assert(sounding == 1, "pause→换曲→resume 后应只有 1 条音轨发声，实际 %d" % sounding)

	# F2 回归：music stop 淡出窗口内的 music volume 不得掐死停止
	AM.stop_music(1.0)  # 停上一用例的 BGM（1 秒淡出窗口）
	_load_seq([_ins(Instruction.Head.MUSIC_VOLUME, ["0.3", "0"])])
	SM.run_script()
	await create_timer(1.3).timeout
	var any_music2 := false
	for p in music_mgr.players:
		if p.playing:
			any_music2 = true
	_assert(not any_music2, "music volume 不得掐死进行中的 music stop（F2 回归）")

	# fade_in/fade_out 拆分（v2.2）：快出慢进——旧轨按 fade_out 慢淡出，新轨按 fade_in 快到位
	AM.play_music(s_cached, 0, 0, 0, true, 1.0)
	await process_frame
	await process_frame
	AM.play_music(s_b, 0, 1.2, 0.1, true, 1.0)  # 旧轨 1.2 秒淡出，新轨 0.1 秒淡入
	await create_timer(0.4).timeout
	cur = music_mgr.players[music_mgr.cur_player_index]
	_assert(absf(cur.volume_db) < 0.01,
		"fade_in:0.1 后新轨应已到位 0dB，实际 %s" % cur.volume_db)
	var old_fading := false
	for p in music_mgr.players:
		if p != cur and p.playing and p.volume_db > -80.0:
			old_fading = true
	_assert(old_fading, "fade_out:1.2 的旧轨应仍在淡出中（未停止）")
	await create_timer(1.0).timeout  # 等旧轨淡出收尾，避免残留 tween 污染后续用例

	# DSL 通路参数槽位：fade_in 立即 + volume:0.6 落盘（槽位错位则 volume 落为默认 1.0）
	_load_seq([_ins(Instruction.Head.MUSIC_PLAY, ["demo_bgm", "0", "true", "0", "3.0", "0.6"])])
	SM.run_script()
	await process_frame
	await process_frame
	cur = music_mgr.players[music_mgr.cur_player_index]
	_assert(absf(cur.volume_db - linear_to_db(0.6)) < 0.01,
		"music fade_in:0 volume:0.6 应落盘（槽位校验），实际 %s" % cur.volume_db)
	AM.stop_music(0.0)
	await process_frame
	await process_frame

	# DSL 通路真实双 BGM 交叉淡变（demo_bgm → demo_bgm_2，快出慢进）
	_load_seq([_ins(Instruction.Head.MUSIC_PLAY, ["demo_bgm", "0", "true", "0", "0", "1.0"])])
	SM.run_script()
	await process_frame
	await process_frame
	var s2 = root.get_node("ResourceManager").load("audio", "demo_bgm_2")
	_load_seq([_ins(Instruction.Head.MUSIC_PLAY, ["demo_bgm_2", "0", "true", "0.1", "1.0", "1.0"])])
	SM.run_script()
	await create_timer(0.3).timeout
	cur = music_mgr.players[music_mgr.cur_player_index]
	_assert(cur.stream == s2 and absf(cur.volume_db) < 0.01,
		"新轨 demo_bgm_2 fade_in:0.1 应已到位 0dB，实际 %s" % cur.volume_db)
	var old_alive := false
	for p in music_mgr.players:
		if p != cur and p.playing and p.stream == s_cached:
			old_alive = true
	_assert(old_alive, "旧轨 demo_bgm 应在 fade_out:1.0 淡出中（双轨同时在播 = 真交叉淡变）")
	AM.stop_music(0.0)
	await create_timer(0.9).timeout  # 等旧轨淡出收尾，避免残留 tween 污染后续用例

	# sfx volume（v2.2）：按流身份调在播音效响度；淡出停止中的轨不被匹配
	_load_seq([_ins(Instruction.Head.SFX_PLAY, ["demo_bgm", "0", "1.0", "true"])])
	SM.run_script()
	await process_frame
	_load_seq([_ins(Instruction.Head.SFX_VOLUME, ["demo_bgm", "0.3", "0"])])
	SM.run_script()
	await process_frame
	var sfx_p: AudioStreamPlayer = null
	for p in sfx_mgr.players:
		if p.playing:
			sfx_p = p
	_assert(sfx_p != null and absf(sfx_p.volume_db - linear_to_db(0.3)) < 0.01,
		"sfx volume 0.3 应落盘，实际 %s" % (sfx_p.volume_db if sfx_p else "无在播"))
	_load_seq([_ins(Instruction.Head.SFX_VOLUME, ["demo_bgm", "1.0", "0.2"])])
	SM.run_script()
	await create_timer(0.4).timeout
	_assert(sfx_p.playing and absf(sfx_p.volume_db) < 0.01,
		"sfx volume fade:0.2 渐变后应回到 0dB 且不中断播放，实际 %s" % sfx_p.volume_db)
	_load_seq([_ins(Instruction.Head.SFX_STOP, ["demo_bgm", "0.3"])])
	SM.run_script()
	_load_seq([_ins(Instruction.Head.SFX_VOLUME, ["demo_bgm", "0.9", "0"])])
	SM.run_script()
	await create_timer(0.5).timeout
	_assert(not sfx_p.playing, "sfx stop 淡出中的轨不应被 sfx volume 匹配（身份已擦除）")

	# AUTO 等语音播完（v2.2）：推进时机 = max(打字完成, 语音播完) + auto_wait_time
	var saved_wait: float = G.auto_wait_time
	G.auto_wait_time = 0.3
	_load_seq([_prev(Instruction.Head.VOICE_PLAY, ["demo_bgm", "2.0", "1.0"]), _dlg("第一句"), _dlg("第二句")])
	SYNC.mode = SYNC.Mode.AUTO  # AUTO
	SM.run_script()  # 前指令起播语音（余 ~4 秒）→ 停在第一句
	SM.dialogue_ui.skip_typing()  # 打字完成 → 布置触发器（语音在播 → 等 voice_finished）
	var idx_after_arm: int = SM.idx
	await create_timer(1.0).timeout  # 远超 auto_wait_time，但语音远未播完
	_assert(SM.idx == idx_after_arm, "语音在播时 AUTO 不得按 auto_wait_time 提前推进")
	AM.play_voice(s_cached, 5.7, 1.0)  # 换余 ~0.3 秒的语音，自然播完触发 voice_finished
	await create_timer(0.5).timeout
	_assert(SM.idx == idx_after_arm, "voice_finished 后未满 auto_wait_time 不应推进")
	await create_timer(0.6).timeout
	_assert(SM.idx != idx_after_arm, "voice_finished + auto_wait_time 后应推进")
	SYNC.mode = SYNC.Mode.INTERACT  # 还原 INTERACT
	G.auto_wait_time = saved_wait
	AM.stop_voice(0.0)

	# 门面音量读写按名称解析总线（与设置 UI 同路径）
	AM.set_volume_db(1, -9.0)
	_assert(absf(AudioServer.get_bus_volume_db(music_bus) + 9.0) < 0.01,
		"set_volume_db(MUSIC) 应写入 Music 总线，实际 %s" % AudioServer.get_bus_volume_db(music_bus))
	AM.set_volume_db(1, saved_db)
