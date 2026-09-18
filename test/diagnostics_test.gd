extends SceneTree

## BGalS v2 编译期诊断测试：喂给解析器非法文本，断言行号级错误输出
## 用法：godot --headless --path . -s test/diagnostics_test.gd

func _init() -> void:
	var ok := true

	# 1. if 空块
	ok = _expect_error(
		["if affection >= 1", "对话没有缩进"],
		"空块") and ok

	# 2. 缩进深度非 4 的倍数
	ok = _expect_error(
		["* 选项", "  两格缩进"],
		"整数倍") and ok

	# 3. 缩进加深无块头
	ok = _expect_error(
		["旁白", "    突然缩进"],
		"块头") and ok

	# 4. 孤立 elif
	ok = _expect_error(
		["elif affection >= 1"],
		"孤立") and ok

	# 5. 保留字劫持：旁白以 wait 开头被判定为指令并报参数错误
	ok = _expect_error(
		["wait 一下"],
		"转义") and ok

	# 6. 选项嵌套
	ok = _expect_error(
		["* 外层", "    * 内层"],
		"嵌套") and ok

	# 7. else 后接 elif
	ok = _expect_error(
		["if a >= 1", "    甲", "else", "    乙", "elif a >= 2", "    丙"],
		"else 之后") and ok

	# 8. 锚点含流程指令（wait 是行级指令，不在锚点白名单——不算锚点，留给 BBCode；jump 同理）
	#    合法锚点不报错；pause 缺参数报错
	ok = _expect_error(
		["角色: 前半[pause ]后半"],
		"pause") and ok

	# 9. 合法文本零错误（含 BBCode、转义、锚点、插值）
	var diags: Array[Dictionary] = []
	var seq := DialogueImporter.parse_script(
		["角色: 你好 [b]加粗[/b] 世界 \\[sfx] {affection}", "角色: 音效[sfx demo_sfx]在此", "* 甲", "    对话甲"],
		"test", diags)
	ok = _assert(diags.is_empty(), "合法文本不应产生诊断: %s" % [diags]) and ok
	ok = _assert(seq.seq.size() == 5, "合法文本应产出 5 项（含选项组收尾 OPTION_END），实际 %d" % seq.seq.size()) and ok

	# 10. else 孤立的 if 配对缺失：endif 已废除，孤立的 else
	ok = _expect_error(["else"], "孤立") and ok

	# 11. </> 修饰结构语句 → 定向报错
	ok = _expect_error(["< if a >= 1"], "块结构语句") and ok
	ok = _expect_error(["> * 选项"], "块结构语句") and ok

	# 12. jump 后死代码 → 警告（每块一次）
	var dead_diags: Array[Dictionary] = []
	DialogueImporter.parse_script(PackedStringArray([
		"jump demo_scene2", "引路人: 这句永远看不到", "再一句也看不到"]), "test", dead_diags)
	var dead_warns := 0
	for d in dead_diags:
		if d["level"] == "warning" and (d["msg"] as String).contains("不可达"):
			dead_warns += 1
	ok = _assert(dead_warns == 1, "jump 后死代码应警告恰好一次，实际 %d" % dead_warns) and ok

	# 13. 未知参数键警告对 bg/music 同样生效（_parse_kv diags 传递补洞）
	var kv_diags: Array[Dictionary] = []
	DialogueImporter.parse_script(PackedStringArray(
		["bg room tiem:2", "music bgm lopo:true"]), "test", kv_diags)
	var kv_warns := 0
	for d in kv_diags:
		if d["level"] == "warning" and (d["msg"] as String).contains("未知参数键"):
			kv_warns += 1
	ok = _assert(kv_warns == 2, "bg/music 的未知键应各警告一次，实际 %d" % kv_warns) and ok

	# 14. 条件左值必须是变量名（字面量左值会被运行时按变量名查表得 0，静默走错分支）
	ok = _expect_error(["if 3 > 2", "    对话"], "左值") and ok

	# 15. 条件右值必须是数字或变量名
	ok = _expect_error(["if a >= 1x", "    对话"], "右值") and ok

	# 16. var 变量名必须是合法标识符；右值必须是数字或变量名
	ok = _expect_error(["var 1a = 3"], "标识符") and ok
	ok = _expect_error(["var a = 1x"], "右值") and ok

	# 17. 合法 var/条件零误报（变量右值、负数字面量）
	var ok_diags: Array[Dictionary] = []
	DialogueImporter.parse_script(PackedStringArray(
		["var a = b", "if a >= b", "    对话", "if c >= -1.5", "    对话"]), "test", ok_diags)
	ok = _assert(ok_diags.is_empty(), "合法 var/条件不应产生诊断: %s" % [ok_diags]) and ok

	# 18. char 实例索引编译期越界校验（行级与锚点同口径）
	var char_diags: Array[Dictionary] = []
	DialogueImporter.parse_script(PackedStringArray(
		["char 5 show", "角色: 文本[char 9 hide]"]), "test", char_diags, [], 2)
	var char_errs := 0
	for d in char_diags:
		if d["level"] == "error" and (d["msg"] as String).contains("越界"):
			char_errs += 1
	ok = _assert(char_errs == 2, "行级与锚点 char 越界应各报错一次，实际 %d" % char_errs) and ok

	# 19. jump/begin 目标校验：不在编译目录警告（模组可提供目标），已登记不警告
	var jump_diags: Array[Dictionary] = []
	DialogueImporter.parse_script(PackedStringArray(["jump ghost_script"]), "test", jump_diags, ["exists_script"])
	var jump_warns := 0
	for d in jump_diags:
		if d["level"] == "warning" and (d["msg"] as String).contains("ghost_script"):
			jump_warns += 1
	ok = _assert(jump_warns == 1, "jump 未知目标应警告恰好一次，实际 %d" % jump_warns) and ok

	var begin_diags: Array[Dictionary] = []
	DialogueImporter.parse_script(PackedStringArray(["begin exists_script"]), "test", begin_diags, ["exists_script"])
	ok = _assert(begin_diags.is_empty(), "begin 已登记目标不应产生诊断: %s" % [begin_diags]) and ok

	# 20. 音频指令数值校验补洞：music from/fade、sfx from 非法值报错
	ok = _expect_error(["music bgm from:abc"], "music from") and ok
	ok = _expect_error(["music bgm fade:abc"], "music fade") and ok
	ok = _expect_error(["sfx demo_sfx from:abc"], "sfx from") and ok

	# 21. volume 必须 0~1；合法值与 loop 零诊断
	ok = _expect_error(["music bgm volume:1.5"], "0~1") and ok
	ok = _expect_error(["sfx demo_sfx volume:-0.2"], "0~1") and ok
	var vol_diags: Array[Dictionary] = []
	DialogueImporter.parse_script(PackedStringArray(
		["music bgm volume:0.8", "sfx rain loop:true volume:0.5", "voice v1 volume:1"]), "test", vol_diags)
	ok = _assert(vol_diags.is_empty(), "合法 volume/loop 不应产生诊断: %s" % [vol_diags]) and ok

	# 22. sfx/voice stop 子动作：头部与默认参数断言
	var stop_diags: Array[Dictionary] = []
	var stop_seq := DialogueImporter.parse_script(PackedStringArray(
		["sfx stop rain fade:1", "sfx stop", "voice stop"]), "test", stop_diags)
	ok = _assert(stop_diags.is_empty(), "stop 子动作不应产生诊断: %s" % [stop_diags]) and ok
	var s := stop_seq.seq
	ok = _assert(s.size() == 3, "应产出 3 条指令，实际 %d" % s.size()) and ok
	if s.size() == 3:
		ok = _assert(s[0].head == Instruction.Head.SFX_STOP and s[0].params[0] == "rain" and s[0].params[1] == 1.0,
			"sfx stop rain fade:1 参数应为 [rain, 1.0]，实际 %s" % [s[0].params]) and ok
		ok = _assert(s[1].head == Instruction.Head.SFX_STOP and s[1].params[0] == "" and s[1].params[1] == 0.3,
			"sfx stop 应为空引用 + 默认 fade 0.3，实际 %s" % [s[1].params]) and ok
		ok = _assert(s[2].head == Instruction.Head.VOICE_STOP and s[2].params[0] == 0.1,
			"voice stop 默认 fade 0.1，实际 %s" % [s[2].params]) and ok

	# 23. voice stop 不接受引用参数
	ok = _expect_error(["voice stop v1"], "不接受引用") and ok

	# 24. 锚点内新参数与子动作可用
	var anchor_diags: Array[Dictionary] = []
	DialogueImporter.parse_script(PackedStringArray(
		["角色: 雨声起[sfx rain loop:true volume:0.4]，随后[music stop fade:2]收束。"]), "test", anchor_diags)
	ok = _assert(anchor_diags.is_empty(), "锚点新参数不应产生诊断: %s" % [anchor_diags]) and ok

	# 25. music volume 子动作：解析与校验
	var mv_diags: Array[Dictionary] = []
	var mv_seq := DialogueImporter.parse_script(PackedStringArray(
		["music bgm", "music volume 0.3 fade:0.2"]), "test", mv_diags)
	ok = _assert(mv_diags.is_empty(), "music volume 合法写法不应产生诊断: %s" % [mv_diags]) and ok
	ok = _assert(mv_seq.seq.size() == 2, "应产出 2 条指令，实际 %d" % mv_seq.seq.size()) and ok
	if mv_seq.seq.size() == 2:
		var mv1 := mv_seq.seq[1] as Instruction
		ok = _assert(mv1.head == Instruction.Head.MUSIC_VOLUME
			and mv1.params[0] == 0.3 and mv1.params[1] == 0.2,
			"music volume 参数应为 [0.3, 0.2]，实际 %s" % [mv1.params]) and ok
	ok = _expect_error(["music volume 1.5"], "0~1") and ok
	ok = _expect_error(["music volume"], "缺少音量") and ok

	# 26. 子动作与播放臂的多余位置参数报错
	ok = _expect_error(["music stop extra"], "位置参数") and ok
	ok = _expect_error(["music volume 0.3 extra"], "位置参数") and ok
	ok = _expect_error(["music bgm extra"], "位置参数") and ok
	ok = _expect_error(["sfx rain fade:1 extra"], "位置参数") and ok

	# 27. bool 参数校验（拼写错误不得静默落为 false）
	ok = _expect_error(["music bgm loop:treu"], "布尔值") and ok
	ok = _expect_error(["char 0 show wait:ture"], "布尔值") and ok
	ok = _expect_error(["trans in wait:x"], "布尔值") and ok

	# 28. fade_in/fade_out 拆分（v2.2）：fade 简写双侧同值，显式键覆盖对应侧
	var fade_diags: Array[Dictionary] = []
	var fade_seq := DialogueImporter.parse_script(PackedStringArray(
		["music bgm fade:1.5", "music bgm fade_in:0.2 fade_out:3", "music bgm fade:1 fade_out:2"]), "test", fade_diags)
	ok = _assert(fade_diags.is_empty(), "fade 拆分合法写法不应产生诊断: %s" % [fade_diags]) and ok
	var f := fade_seq.seq
	ok = _assert(f.size() == 3, "应产出 3 条指令，实际 %d" % f.size()) and ok
	if f.size() == 3:
		ok = _assert(f[0].params[3] == 1.5 and f[0].params[4] == 1.5,
			"fade:1.5 简写应双侧同值，实际 %s" % [f[0].params]) and ok
		ok = _assert(f[1].params[3] == 0.2 and f[1].params[4] == 3.0,
			"fade_in/fade_out 应各自落位，实际 %s" % [f[1].params]) and ok
		ok = _assert(f[2].params[3] == 1.0 and f[2].params[4] == 2.0,
			"显式 fade_out 应覆盖 fade 简写对应侧，实际 %s" % [f[2].params]) and ok
	ok = _expect_error(["music bgm fade_in:abc"], "music fade_in") and ok
	ok = _expect_error(["music bgm fade_out:abc"], "music fade_out") and ok

	# 29. sfx volume 子动作（v2.2）：解析与校验；voice 无此子动作
	var sv_diags: Array[Dictionary] = []
	var sv_seq := DialogueImporter.parse_script(PackedStringArray(
		["sfx volume rain 0.5 fade:0.1"]), "test", sv_diags)
	ok = _assert(sv_diags.is_empty(), "sfx volume 合法写法不应产生诊断: %s" % [sv_diags]) and ok
	ok = _assert(sv_seq.seq.size() == 1, "应产出 1 条指令，实际 %d" % sv_seq.seq.size()) and ok
	if sv_seq.seq.size() == 1:
		var sv0 := sv_seq.seq[0] as Instruction
		ok = _assert(sv0.head == Instruction.Head.SFX_VOLUME
			and sv0.params[0] == "rain" and sv0.params[1] == 0.5 and sv0.params[2] == 0.1,
			"sfx volume 参数应为 [rain, 0.5, 0.1]，实际 %s" % [sv0.params]) and ok
	ok = _expect_error(["sfx volume rain"], "两个位置参数") and ok
	ok = _expect_error(["sfx volume rain 1.5"], "0~1") and ok
	ok = _expect_error(["sfx volume rain 0.5 extra"], "两个位置参数") and ok
	ok = _expect_error(["voice volume 0.5"], "不支持 volume") and ok

	# 30. 条件表达式 malformed：无比较符/缺左值/双比较符/单等号/右值缺失（= 坠入右值）
	ok = _expect_error(["if a", "    对话"], "无法解析") and ok
	ok = _expect_error(["if >= 3", "    对话"], "无法解析") and ok
	ok = _expect_error(["if a >> 3", "    对话"], "右值") and ok
	ok = _expect_error(["if a = 3", "    对话"], "无法解析") and ok
	ok = _expect_error(["if a >=", "    对话"], "右值") and ok
	ok = _expect_error(["* 选项 if:3 > 2", "    对话"], "左值") and ok

	print("DIAGNOSTICS_TEST_DONE ok=", ok)
	quit(0 if ok else 1)


func _expect_error(lines: Array, keyword: String) -> bool:
	var diags: Array[Dictionary] = []
	var packed := PackedStringArray(lines)
	DialogueImporter.parse_script(packed, "test", diags)
	for d in diags:
		if d["level"] == "error" and (d["msg"] as String).contains(keyword):
			return true
	print("FAIL: 期望含「%s」的错误，实际诊断: %s" % [keyword, diags])
	return false


func _assert(cond: bool, msg: String) -> bool:
	if not cond:
		print("FAIL: ", msg)
	return cond
