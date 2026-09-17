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
