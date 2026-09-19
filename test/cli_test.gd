extends SceneTree

## BGalS 编译 CLI 工具链测试：GraphDumper 条件中缀还原/参数映射/图结构与 spec 导出。
## 用法：godot --headless --path . -s test/cli_test.gd

var _ok := true


func _init() -> void:
	_test_cond_to_infix()
	_test_params_to_dict()
	_test_build_linear()
	_test_build_option_group()
	_test_build_cond_chain()
	_test_build_jump_terminal()
	_test_build_prev_post()
	_test_build_dangling()
	_test_build_anchors()
	_test_build_golden_scene1()
	_test_build_spec()
	_test_scan_txt_only()

	print("CLI_TEST_DONE ok=", _ok)
	quit(0 if _ok else 1)


func _assert(cond: bool, msg: String) -> bool:
	if not cond:
		_ok = false
		print("FAIL: ", msg)
	return cond


func _build(lines: Array) -> Dictionary:
	var diags: Array[Dictionary] = []
	var seq := DialogueImporter.parse_script(PackedStringArray(lines), "test", diags)
	_assert(diags.is_empty(), "测试脚本应零诊断: %s" % [diags])
	return GraphDumper.build(seq, "test")


func _count_kind(nodes: Array, kind: String) -> int:
	var n := 0
	for node in nodes:
		if node["kind"] == kind:
			n += 1
	return n


func _edges_of(edges: Array, kind: String) -> Array:
	var out: Array = []
	for e in edges:
		if e["kind"] == kind:
			out.append(e)
	return out


func _node_by_id(nodes: Array, id: String) -> Dictionary:
	for node in nodes:
		if node["id"] == id:
			return node
	return {}


# --- _cond_to_infix ---

func _cond(tokens: Array) -> String:
	return GraphDumper._cond_to_infix(tokens)


func _test_cond_to_infix() -> void:
	var PV := Instruction.CondTag.PUSH_VAR
	var PN := Instruction.CondTag.PUSH_NUM
	var CMP := Instruction.CondTag.CMP
	var NOT := Instruction.CondTag.NOT
	var AND := Instruction.CondTag.AND
	var OR := Instruction.CondTag.OR

	# 单条件
	_assert(_cond([[PV, "a"], [PN, 1.0], [CMP, ">="]]) == "a >= 1",
		"单条件应为「a >= 1」，实际「%s」" % _cond([[PV, "a"], [PN, 1.0], [CMP, ">="]]))
	# and/or 混合优先级（and 优先，不加括号）
	var mixed := _cond([[PV, "a"], [PN, 1.0], [CMP, ">="], [PV, "b"], [PN, 2.0], [CMP, "<"], [AND],
		[PV, "c"], [PN, 0.0], [CMP, "=="], [OR]])
	_assert(mixed == "a >= 1 and b < 2 or c == 0", "and/or 混合应为左结合不补括号，实际「%s」" % mixed)
	# 括号优先级（or 作为 and 的右子须补括号）
	var paren := _cond([[PV, "a"], [PN, 1.0], [CMP, ">="], [PV, "b"], [PN, 2.0], [CMP, "<"],
		[PV, "c"], [PN, 0.0], [CMP, "=="], [OR], [AND]])
	_assert(paren == "a >= 1 and (b < 2 or c == 0)", "右子优先级不足应补括号，实际「%s」" % paren)
	# not：原子不补，非原子必补
	_assert(_cond([[PV, "a"], [NOT]]) == "not a", "not 原子应不补括号，实际「%s」" % _cond([[PV, "a"], [NOT]]))
	var not_paren := _cond([[PV, "a"], [PV, "b"], [OR], [NOT]])
	_assert(not_paren == "not (a or b)", "not 非原子应补括号，实际「%s」" % not_paren)
	# 整数去小数；非整数保留
	_assert(_cond([[PV, "a"], [PN, 2.0], [CMP, "=="]]) == "a == 2", "整数应去小数，实际「%s」" % _cond([[PV, "a"], [PN, 2.0], [CMP, "=="]]))
	_assert(_cond([[PV, "a"], [PN, 1.5], [CMP, "<"]]) == "a < 1.5", "非整数应保留，实际「%s」" % _cond([[PV, "a"], [PN, 1.5], [CMP, "<"]]))
	# 变量与变量比较
	_assert(_cond([[PV, "a"], [PV, "b"], [CMP, "!="]]) == "a != b", "变量比较失败")
	# 裸变量真值
	_assert(_cond([[PV, "flag"]]) == "flag", "裸变量失败")
	# 畸形 tokens → 空串
	_assert(_cond([[PV, "a"], [AND]]) == "", "栈下溢应返回空串")
	_assert(_cond([[PV, "a"], [PV, "b"]]) == "", "栈残留应返回空串")


# --- _params_to_dict ---

func _test_params_to_dict() -> void:
	# 默认值省略、非默认保留
	var music := Instruction.from_strings(Instruction.Head.MUSIC_PLAY, ["bgm"])
	var p := GraphDumper._params_to_dict(music.head, music.params)
	_assert(p == {"path": "bgm"}, "默认参数应全省略只留 path，实际 %s" % [p])
	music = Instruction.from_strings(Instruction.Head.MUSIC_PLAY, ["bgm", "0", "false"])
	p = GraphDumper._params_to_dict(music.head, music.params)
	_assert(p == {"path": "bgm", "loop": false}, "非默认 loop:false 应保留，实际 %s" % [p])

	# 结构下标跳过 + tokens → cond
	var opt := Instruction.new(Instruction.Head.OPTION)
	opt.params[0] = "文本"
	opt.params[1] = [[Instruction.CondTag.PUSH_VAR, "x"], [Instruction.CondTag.PUSH_NUM, 1.0], [Instruction.CondTag.CMP, ">="]]
	opt.params[2] = true
	opt.params[3] = 5
	opt.params[4] = 9
	opt.params[5] = 12
	p = GraphDumper._params_to_dict(opt.head, opt.params)
	_assert(p == {"text": "文本", "cond": "x >= 1"}, "结构下标应跳过、tokens 应转 cond，实际 %s" % [p])

	# 空 tokens = 恒真，省略 cond
	opt = Instruction.new(Instruction.Head.OPTION)
	opt.params[0] = "文本"
	p = GraphDumper._params_to_dict(opt.head, opt.params)
	_assert(p == {"text": "文本"}, "空 tokens 应省略 cond，实际 %s" % [p])


# --- build：线性 ---

func _test_build_linear() -> void:
	var g := _build(["引路人: 甲", "wait 1"])
	var nodes: Array = g["nodes"]
	var edges: Array = g["edges"]
	_assert(g["format"] == "bgals-graph/1" and g["compiler"] == DialogueImporter.COMPILER_VERSION and g["script"] == "test",
		"图顶层字段错误: %s" % [g.keys()])
	_assert(nodes.size() == 4, "线性图应为 4 节点（start/dlg/inst/end），实际 %d" % nodes.size())
	if nodes.size() == 4:
		_assert(nodes[0] == {"id": "start", "kind": "start"}, "首节点应为 start")
		_assert(nodes[1]["kind"] == "dialogue" and nodes[1]["character"] == "引路人" and nodes[1]["text"] == "甲", "对话节点错误: %s" % [nodes[1]])
		_assert(nodes[2]["kind"] == "inst" and nodes[2]["head"] == "WAIT" and nodes[2]["params"] == {"duration": 1.0},
			"指令节点错误: %s" % [nodes[2]])
		_assert(nodes[3] == {"id": "end", "kind": "end"}, "末节点应为 end")
	var seq_edges := _edges_of(edges, "seq")
	_assert(seq_edges.size() == 3, "线性图应有 3 条 seq 边，实际 %d" % seq_edges.size())
	if seq_edges.size() == 3:
		_assert(seq_edges[0]["from"] == "start" and seq_edges[0]["to"] == "n0"
			and seq_edges[1]["from"] == "n0" and seq_edges[1]["to"] == "n1"
			and seq_edges[2]["from"] == "n1" and seq_edges[2]["to"] == "end",
			"seq 边链错误: %s" % [seq_edges])


# --- build：选项组 ---

func _test_build_option_group() -> void:
	var g := _build(["* 甲", "    对话甲", "* 乙 if:x >= 1", "    对话乙", "旁白汇合"])
	var nodes: Array = g["nodes"]
	var edges: Array = g["edges"]
	_assert(_count_kind(nodes, "option_group") == 1, "应有 1 个选项组节点")
	var option_edges := _edges_of(edges, "option")
	_assert(option_edges.size() == 2, "应有 2 条 option 边，实际 %d" % option_edges.size())
	if option_edges.size() == 2:
		_assert(option_edges[0]["from"] == option_edges[1]["from"], "option 边应同源")
		_assert(option_edges[0]["text"] == "甲" and not option_edges[0].has("cond"),
			"无条件选项不应有 cond 键: %s" % [option_edges[0]])
		_assert(option_edges[1]["text"] == "乙" and option_edges[1].get("cond", "") == "x >= 1",
			"条件选项 cond 错误: %s" % [option_edges[1]])
		_assert(option_edges[0]["to"] != option_edges[1]["to"], "option 边应指向各自体入口")
	# 汇合：汇合对话节点应有两条 seq 入边（两个体出口）
	var merge := _node_by_id(nodes, "n3")
	_assert(merge.get("text", "") == "旁白汇合", "汇合节点应为「旁白汇合」，实际 %s" % [merge])
	var merge_in := 0
	for e in edges:
		if e["kind"] == "seq" and e["to"] == "n3":
			merge_in += 1
	_assert(merge_in == 2, "汇合节点应有 2 条 seq 入边，实际 %d" % merge_in)


# --- build：if/elif/else 链 ---

func _test_build_cond_chain() -> void:
	var g := _build(["if a >= 1", "    甲", "elif a >= 2", "    乙", "else", "    丙", "汇合"])
	var nodes: Array = g["nodes"]
	var edges: Array = g["edges"]
	_assert(_count_kind(nodes, "cond") == 1, "应有 1 个 cond 节点")
	var branch_edges := _edges_of(edges, "branch")
	_assert(branch_edges.size() == 3, "应有 3 条 branch 边，实际 %d" % branch_edges.size())
	if branch_edges.size() == 3:
		_assert(branch_edges[0].get("cond", "") == "a >= 1", "if 分支 cond 错误: %s" % [branch_edges[0]])
		_assert(branch_edges[1].get("cond", "") == "a >= 2", "elif 分支 cond 错误: %s" % [branch_edges[1]])
		_assert(not branch_edges[2].has("cond"), "else 分支不应有 cond 键: %s" % [branch_edges[2]])
	# 汇合：END_IF 后的对话应收 3 条 seq 入边
	var merge := _node_by_id(nodes, "n4")
	_assert(merge.get("text", "") == "汇合", "汇合节点应为「汇合」，实际 %s" % [merge])
	var merge_in := 0
	for e in edges:
		if e["kind"] == "seq" and e["to"] == "n4":
			merge_in += 1
	_assert(merge_in == 3, "汇合节点应有 3 条 seq 入边，实际 %d" % merge_in)


# --- build：jump 终端 ---

func _test_build_jump_terminal() -> void:
	var g := _build(["引路人: 甲", "jump main_menu"])
	var nodes: Array = g["nodes"]
	var edges: Array = g["edges"]
	_assert(_count_kind(nodes, "jump") == 1, "应有 1 个 jump 节点")
	var jump := _node_by_id(nodes, "n1")
	_assert(jump.get("kind", "") == "jump" and jump.get("target", "") == "main_menu", "jump 节点错误: %s" % [jump])
	for e in edges:
		_assert(e["from"] != "n1", "jump 为终端节点不应有出边: %s" % [e])
		_assert(e["to"] != "end", "jump 收尾的剧本 end 节点不应有入边: %s" % [e])


# --- build：prev/post 附着 ---

func _test_build_prev_post() -> void:
	var g := _build(["< wait 1", "引路人: 甲", "> wait 2"])
	var nodes: Array = g["nodes"]
	_assert(nodes.size() == 3, "prev/post 应落槽不产生节点，实际 %d 节点" % nodes.size())
	var dlg := _node_by_id(nodes, "n0")
	if _assert(dlg.get("kind", "") == "dialogue", "n0 应为对话节点: %s" % [dlg]):
		_assert(dlg["prev"].size() == 1 and dlg["prev"][0]["head"] == "WAIT" and dlg["prev"][0]["params"] == {"duration": 1.0},
			"prev 槽错误: %s" % [dlg["prev"]])
		_assert(dlg["post"].size() == 1 and dlg["post"][0]["head"] == "WAIT" and dlg["post"][0]["params"] == {"duration": 2.0},
			"post 槽错误: %s" % [dlg["post"]])


# --- build：孤立 prev/post 降级 ---

func _test_build_dangling() -> void:
	# 文件尾孤立 prev → dangling 独立指令节点
	var g := _build(["引路人: 甲", "< wait 1"])
	var tail := _node_by_id(g["nodes"], "n1")
	_assert(tail.get("kind", "") == "inst" and tail.get("head", "") == "WAIT" and tail.get("dangling", false) == true,
		"文件尾 prev 应降级为 dangling 指令节点: %s" % [tail])
	# 文件首孤立 post → dangling（编译器另有 warning，此处只验图形态）
	var diags: Array[Dictionary] = []
	var seq := DialogueImporter.parse_script(PackedStringArray(["> wait 1", "引路人: 甲"]), "test", diags)
	g = GraphDumper.build(seq, "test")
	var head_node := _node_by_id(g["nodes"], "n0")
	_assert(head_node.get("kind", "") == "inst" and head_node.get("dangling", false) == true,
		"文件首 post 应降级为 dangling 指令节点: %s" % [head_node])


# --- build：对话锚点提取 ---

func _test_build_anchors() -> void:
	var g := _build(["引路人: 台词[sfx rain]尾{var1}"])
	var dlg := _node_by_id(g["nodes"], "n0")
	if _assert(dlg.get("kind", "") == "dialogue", "n0 应为对话节点: %s" % [dlg]):
		_assert(dlg["text"] == "台词[sfx rain]尾{var1}", "text 应为原文: %s" % [dlg["text"]])
		_assert(dlg["display_text"] == "台词尾{var1}", "display_text 应剥锚点且不插值: %s" % [dlg["display_text"]])
		var anchors: Array = dlg["anchors"]
		_assert(anchors.size() == 1 and anchors[0]["index"] == 2 and anchors[0]["head"] == "SFX_PLAY"
			and anchors[0]["params"] == {"path": "rain"}, "锚点提取错误: %s" % [anchors])


# --- build：demo_scene1 金样 ---

func _test_build_golden_scene1() -> void:
	var file := FileAccess.open("res://scripts/demo/scene1.txt", FileAccess.READ)
	if not _assert(file != null, "无法打开 demo_scene1.txt"):
		return
	var text := file.get_as_text()
	file.close()
	var diags: Array[Dictionary] = []
	var seq := DialogueImporter.parse_script(text.split("\n"), "res://scripts/demo/scene1.txt", diags)
	_assert(diags.is_empty(), "demo_scene1 应零诊断: %s" % [diags])
	var g := GraphDumper.build(seq, "demo_scene1")
	var nodes: Array = g["nodes"]
	var edges: Array = g["edges"]

	_assert(_count_kind(nodes, "start") == 1 and _count_kind(nodes, "end") == 1, "应有 start/end 各一")
	_assert(_count_kind(nodes, "dialogue") == 13, "scene1 应有 13 个对话节点，实际 %d" % _count_kind(nodes, "dialogue"))
	_assert(_count_kind(nodes, "inst") == 6, "scene1 应有 6 个独立指令节点，实际 %d" % _count_kind(nodes, "inst"))
	_assert(_count_kind(nodes, "option_group") == 1 and _count_kind(nodes, "cond") == 1 and _count_kind(nodes, "jump") == 2,
		"scene1 应有 1 选项组 + 1 条件链 + 2 跳转，实际 %d/%d/%d" % [
			_count_kind(nodes, "option_group"), _count_kind(nodes, "cond"), _count_kind(nodes, "jump")])
	_assert(nodes.size() == 25, "scene1 应有 25 个节点，实际 %d" % nodes.size())

	# 关键边：选项组两条 option 边（其一有条件）、条件链两条 branch 边、jump 终端
	var option_edges := _edges_of(edges, "option")
	_assert(option_edges.size() == 2, "scene1 应有 2 条 option 边，实际 %d" % option_edges.size())
	if option_edges.size() == 2:
		_assert(option_edges[0]["text"] == "前往第二幕" and not option_edges[0].has("cond"),
			"选项一错误: %s" % [option_edges[0]])
		_assert(option_edges[1]["text"] == "留在这里" and option_edges[1].get("cond", "") == "affection >= 1",
			"选项二错误: %s" % [option_edges[1]])
	var branch_edges := _edges_of(edges, "branch")
	_assert(branch_edges.size() == 2, "scene1 应有 2 条 branch 边，实际 %d" % branch_edges.size())
	if branch_edges.size() == 2:
		_assert(branch_edges[0].get("cond", "") == "affection >= 1 and affection < 100",
			"if 分支 cond 错误: %s" % [branch_edges[0]])
		_assert(not branch_edges[1].has("cond"), "else 分支不应有 cond: %s" % [branch_edges[1]])
	var jump_main := _node_by_id(nodes, "n22")
	_assert(jump_main.get("kind", "") == "jump" and jump_main.get("target", "") == "main_menu",
		"末尾 jump main_menu 错误: %s" % [jump_main])
	# prev/post 落槽：「注意看」post 挂 bg 夜图，「立绘可以移动」prev 挂 char move
	var dlg_notice := _node_by_id(nodes, "n7")
	_assert(dlg_notice.get("post", []).size() == 1 and dlg_notice["post"][0]["head"] == "SET_BACKGROUND",
		"「注意看」post 应为 SET_BACKGROUND: %s" % [dlg_notice.get("post", [])])
	var dlg_move := _node_by_id(nodes, "n8")
	_assert(dlg_move.get("prev", []).size() == 1 and dlg_move["prev"][0]["head"] == "CHAR_MOVE_TO",
		"「立绘可以移动」prev 应为 CHAR_MOVE_TO: %s" % [dlg_move.get("prev", [])])
	_assert(dlg_move.get("anchors", []).size() == 1 and dlg_move["anchors"][0]["head"] == "CHAR_CHANGE_TEXTURE",
		"「立绘可以移动」锚点应为 CHAR_CHANGE_TEXTURE: %s" % [dlg_move.get("anchors", [])])
	# 插值原文保留
	var dlg_aff := _node_by_id(nodes, "n10")
	_assert((dlg_aff.get("display_text", "") as String).contains("{affection}"),
		"display_text 应保留 {affection} 字面: %s" % [dlg_aff.get("display_text", "")])
	# 边完整性：所有 from/to 都是已声明节点
	var ids := {}
	for node in nodes:
		ids[node["id"]] = true
	var dangling_edge := false
	for e in edges:
		if not ids.has(e["from"]) or not ids.has(e["to"]):
			dangling_edge = true
	_assert(not dangling_edge, "存在指向未声明节点的边: %s" % [edges])


# --- build_spec ---

func _test_build_spec() -> void:
	var spec := GraphDumper.build_spec()
	_assert(spec["compiler"] == DialogueImporter.COMPILER_VERSION, "spec compiler 错误")
	_assert((spec["heads"] as Array).size() == 38, "heads 应为 38 项，实际 %d" % (spec["heads"] as Array).size())
	_assert((spec["cond_tags"] as Array).size() == 6, "cond_tags 应为 6 项")
	_assert(not (spec["reserved_keys"] as Array).is_empty(), "reserved_keys 不应为空")
	_assert(not (spec["anchor_whitelist"] as Array).is_empty(), "anchor_whitelist 不应为空")
	_assert(spec["indent_unit"] == 4, "indent_unit 应为 4")
	var spec_map: Dictionary = spec["spec"]
	var music_spec: Array = spec_map["MUSIC_PLAY"]
	_assert(music_spec[0]["name"] == "path" and music_spec[0]["role"] == "audio" and music_spec[0]["structural"] == false,
		"MUSIC_PLAY 首参应为 path/audio/非结构: %s" % [music_spec[0]])
	var option_spec: Array = spec_map["OPTION"]
	_assert(option_spec[0]["structural"] == false and option_spec[1]["structural"] == false
		and option_spec[2]["structural"] == true and option_spec[3]["structural"] == true
		and option_spec[4]["structural"] == true and option_spec[5]["structural"] == true,
		"OPTION 的 2-5 应标 structural: %s" % [option_spec])
	_assert((spec_map["IF"] as Array)[1]["structural"] == true
		and (spec_map["ELSE_IF"] as Array)[1]["structural"] == true
		and (spec_map["ELSE_IF"] as Array)[2]["structural"] == true
		and (spec_map["ELSE"] as Array)[0]["structural"] == true,
		"IF/ELSE_IF/ELSE 的跳转下标应标 structural")
	_assert(spec_map.has("OPTION_END") and (spec_map["OPTION_END"] as Array).is_empty(),
		"OPTION_END 无参数应输出空数组")


## 目录扫描只认 .txt：编辑器 sidecar（.graph.json）等邻接文件不得入编译
func _test_scan_txt_only() -> void:
	var dir := "user://cli_test_scan"
	DirAccess.make_dir_recursive_absolute(dir)
	for name in ["alpha.txt", "alpha.graph.json", "notes.md"]:
		var f := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
		f.store_string("# t\n")
		f.close()
	var names := DialogueImporter.scan_script_names(dir)
	_assert(names.size() == 1 and names[0] == "alpha", "扫描应只含 alpha.txt，实际: %s" % [names])
	for name in ["alpha.txt", "alpha.graph.json", "notes.md"]:
		DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)
