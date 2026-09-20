class_name GraphDumper

## GalEventItemSequence → 图 JSON（bgals-graph/1）与指令规格导出（前端零硬编码）。
## 纯静态、不引用 autoload，供 tool/bgals_cli.gd 与测试共用。
## 走查模型：pending 前驱存边存根（{from, kind, ...}），新节点创建时补全 to 落表；
## 结构回填字段（OPTION[2..5]/IF[1]/ELSE_IF[1..2]/ELSE[0]）在此消解为图结构，不进节点参数。

const FORMAT := "bgals-graph/1"


## 产物 → 图 JSON：{"format", "compiler", "script", "nodes", "edges"}
static func build(sequence: GalEventItemSequence, script_name: String) -> Dictionary:
	var w := {
		"items": sequence.seq,
		"nodes": [] as Array[Dictionary],
		"edges": [] as Array[Dictionary],
		"pending": [] as Array,        # 待接入的边存根（seq/option/branch）
		"next_id": 0,
		"prev_dlg": -1,                # 上一个 dialogue 节点的 nodes 下标（post 附着用）
		"cached_prev": [] as Array,    # 缓存的 PrevInstruction（附着到下一个 dialogue）
	}
	w["nodes"].append({"id": "start", "kind": "start"})
	w["pending"].append({"from": "start", "kind": "seq"})
	_walk(w, 0, sequence.seq.size())
	# 文件尾孤立的前指令（无对话可附着）降级为独立指令节点
	for ins in w["cached_prev"]:
		_make_inst_node(w, ins, true)
	w["nodes"].append({"id": "end", "kind": "end"})
	_drain_pending(w, "end")
	return {
		"format": FORMAT,
		"compiler": DialogueImporter.COMPILER_VERSION,
		"script": script_name,
		"nodes": w["nodes"],
		"edges": w["edges"],
	}


## 指令规格导出：heads/参数 spec/条件记号/锚点白名单/保留字/缩进单位，前端表单与高亮全部由本输出驱动
static func build_spec() -> Dictionary:
	var spec_out := {}
	var structural_of: Dictionary = Instruction._STRUCTURAL_PARAMS
	for head in Instruction.Head.values():
		var params_out: Array = []
		var entries: Array = Instruction._SPEC.get(head, [])
		var structural: Array = structural_of.get(head, [])
		for i in entries.size():
			var entry: Array = entries[i]
			params_out.append({
				"name": entry[0],
				"type": Instruction._T.keys()[entry[1]],
				"default": entry[2],
				"role": entry[3],
				"structural": i in structural,
			})
		spec_out[Instruction.Head.keys()[head]] = params_out
	return {
		"compiler": DialogueImporter.COMPILER_VERSION,
		"heads": Array(Instruction.Head.keys()),
		"spec": spec_out,
		"cond_tags": Array(Instruction.CondTag.keys()),
		"anchor_whitelist": DialogueImporter.ANCHOR_WHITELIST,
		"reserved_keys": DialogueImporter.RESERVED_KEYS,
		"indent_unit": DialogueImporter.INDENT_UNIT,
	}


# --- 结构走查 ---

## 线性扫描 [from, to)：对话/独立指令/选项组/条件链/跳转。prev/post 指令落槽到相邻对话节点。
static func _walk(w: Dictionary, from: int, to: int) -> void:
	var items: Array = w["items"]
	var i := from
	while i < to:
		var item: GalEventItem = items[i]
		if item is DialogueItem:
			_make_dialogue_node(w, item)
			i += 1
		elif item is PrevInstruction:
			w["cached_prev"].append(item)
			i += 1
		elif item is PostInstruction:
			_attach_post(w, item)
			i += 1
		else:
			var ins := item as Instruction
			match ins.head:
				Instruction.Head.OPTION:
					if ins.params[2]:
						i = _walk_option_group(w, i, to)
					else:
						# 防御：非组头 OPTION 不该出现在线性流，按普通指令处理
						_make_inst_node(w, ins)
						i += 1
				Instruction.Head.IF:
					i = _walk_cond_chain(w, i, to)
				Instruction.Head.JUMP_SCRIPT, Instruction.Head.JUMP_MAIN_MENU:
					_make_jump_node(w, ins)
					i += 1
				Instruction.Head.OPTION_END, Instruction.Head.END_IF:
					# 防御：结构收尾由组/链走查跳过，正常不会到达
					i += 1
				_:
					_make_inst_node(w, ins)
					i += 1


## 选项组：沿 next_option 链收分支，体区间 [body_start, 下一兄弟或 group_end) 递归走查。
## 返回组后下标（group_end + 1，跳过 OPTION_END）；各体出口汇入 pending 形成汇合。
static func _walk_option_group(w: Dictionary, head_idx: int, limit: int) -> int:
	var items: Array = w["items"]
	var head_ins := items[head_idx] as Instruction
	var group_id := _new_id(w)
	w["nodes"].append({"id": group_id, "kind": "option_group"})
	_drain_pending(w, group_id)

	var group_end: int = head_ins.params[5]
	var exits: Array = []
	var idx := head_idx
	while idx != -1 and idx < items.size():
		var opt := items[idx] as Instruction
		var next_option: int = opt.params[4]
		var stub := {"from": group_id, "kind": "option", "text": opt.params[0]}
		var tokens: Array = opt.params[1]
		if not tokens.is_empty():
			stub["cond"] = _cond_to_infix(tokens)
		w["pending"] = [stub]
		var body_end := next_option if next_option != -1 else group_end
		_walk(w, opt.params[3], clampi(body_end, opt.params[3], mini(limit, items.size())))
		exits.append_array(w["pending"])
		idx = next_option
	w["pending"] = exits
	return group_end + 1


## 条件链：IF →（ELSE_IF)* →（ELSE)?，分支体递归走查。返回 END_IF + 1（汇合点）。
static func _walk_cond_chain(w: Dictionary, if_idx: int, limit: int) -> int:
	var items: Array = w["items"]
	var cond_id := _new_id(w)
	w["nodes"].append({"id": cond_id, "kind": "cond"})
	_drain_pending(w, cond_id)

	var exits: Array = []
	var idx := if_idx
	var end_if := -1
	while idx != -1 and idx < items.size():
		var ins := items[idx] as Instruction
		var stub := {"from": cond_id, "kind": "branch"}
		var next_idx := -1
		if ins.head == Instruction.Head.ELSE:
			end_if = ins.params[0]
		else:
			stub["cond"] = _cond_to_infix(ins.params[0])
			next_idx = ins.params[1]
		var body_end := end_if if ins.head == Instruction.Head.ELSE else next_idx
		w["pending"] = [stub]
		_walk(w, idx + 1, clampi(body_end, idx + 1, mini(limit, items.size())))
		exits.append_array(w["pending"])
		if ins.head == Instruction.Head.ELSE:
			break
		# next 处是 ELSE_IF/ELSE 则续链，是 END_IF 则收尾
		if next_idx < items.size() and items[next_idx] is Instruction \
			and (items[next_idx] as Instruction).head in [Instruction.Head.ELSE_IF, Instruction.Head.ELSE]:
			idx = next_idx
		else:
			end_if = next_idx
			break
	w["pending"] = exits
	if end_if == -1:
		push_warning("GraphDumper: 条件链缺少 END_IF（产物损毁？），链头下标 %d" % if_idx)
		return items.size()
	return end_if + 1


# --- 节点构造 ---

static func _new_id(w: Dictionary) -> String:
	var id := "n%d" % w["next_id"]
	w["next_id"] += 1
	return id


## 新节点入边接入：pending 中的边存根补全 to 后落表并清空
static func _drain_pending(w: Dictionary, to_id: String) -> void:
	var edges: Array = w["edges"]
	for stub in w["pending"]:
		var edge := {"from": stub["from"], "to": to_id, "kind": stub["kind"]}
		if stub.has("text"):
			edge["text"] = stub["text"]
		if stub.has("cond"):
			edge["cond"] = stub["cond"]
		edges.append(edge)
	w["pending"] = []


## 普通可出边节点收尾：自身注册为唯一 seq 前驱
static func _seq_out(w: Dictionary, id: String) -> void:
	w["pending"] = [{"from": id, "kind": "seq"}]


static func _make_dialogue_node(w: Dictionary, item: DialogueItem) -> void:
	var id := _new_id(w)
	# display_text/anchors 以「剥锚点但不插值」的文本为基准（{var} 保持字面）
	var rendered := DialogueRenderer.render(item.dialogue, {}, false)
	var anchors: Array = []
	for a in rendered["anchors"]:
		var ins: Instruction = a["ins"]
		anchors.append({"index": a["index"], "head": Instruction.Head.keys()[ins.head], "params": _params_to_dict(ins.head, ins.params)})
	var prev: Array = []
	for ins in w["cached_prev"]:
		prev.append(_inst_to_dict(ins))
	w["cached_prev"] = []
	var nodes: Array = w["nodes"]
	nodes.append({
		"id": id,
		"kind": "dialogue",
		"character": item.character,
		"text": item.dialogue,
		"display_text": rendered["text"],
		"anchors": anchors,
		"prev": prev,
		"post": [] as Array,
	})
	w["prev_dlg"] = nodes.size() - 1
	_drain_pending(w, id)
	_seq_out(w, id)


static func _make_inst_node(w: Dictionary, ins: Instruction, dangling := false) -> void:
	var id := _new_id(w)
	var node := {
		"id": id,
		"kind": "inst",
		"head": Instruction.Head.keys()[ins.head],
		"params": _params_to_dict(ins.head, ins.params),
	}
	if dangling:
		node["dangling"] = true
	w["nodes"].append(node)
	_drain_pending(w, id)
	_seq_out(w, id)


## 跳转：终端节点（无 seq 出边），target = 剧本名或 main_menu
static func _make_jump_node(w: Dictionary, ins: Instruction) -> void:
	var id := _new_id(w)
	var target: String = "main_menu" if ins.head == Instruction.Head.JUMP_MAIN_MENU else ins.params[0]
	w["nodes"].append({"id": id, "kind": "jump", "target": target})
	_drain_pending(w, id)
	w["pending"] = []


## 后指令附着到上一个对话节点的 post 槽；文件首等无对话可附着的降级为独立指令节点
static func _attach_post(w: Dictionary, ins: PostInstruction) -> void:
	var prev_dlg: int = w["prev_dlg"]
	if prev_dlg == -1:
		_make_inst_node(w, ins, true)
	else:
		(w["nodes"][prev_dlg]["post"] as Array).append(_inst_to_dict(ins))


## prev/post/anchors 槽内的指令对象：形态同独立指令节点，无 id
static func _inst_to_dict(ins: Instruction) -> Dictionary:
	return {
		"kind": "inst",
		"head": Instruction.Head.keys()[ins.head],
		"params": _params_to_dict(ins.head, ins.params),
	}


# --- 参数与条件还原 ---

## 指令参数按 _SPEC 位置映射为名字：跳过结构回填下标、与默认值相等的项；
## 名为 tokens 的 ARR 参数转中缀后放 cond 键（空数组 = 恒真，省略）
static func _params_to_dict(head: Instruction.Head, params: Array[Variant]) -> Dictionary:
	var out := {}
	var spec: Array = Instruction._SPEC.get(head, [])
	var structural: Array = Instruction._STRUCTURAL_PARAMS.get(head, [])
	for i in mini(params.size(), spec.size()):
		if i in structural:
			continue
		var param_name: String = spec[i][0]
		var value: Variant = params[i]
		if param_name == "tokens" and spec[i][1] == Instruction._T.ARR:
			if (value as Array).is_empty():
				continue
			out["cond"] = _cond_to_infix(value)
			continue
		if value == spec[i][2]:
			continue
		out[param_name] = value
	return out


## 条件后缀记号流 → 中缀字符串（栈式逆解析）。
## 优先级：原子4 > CMP3 > NOT2 > AND1 > OR0；子表达式优先级不足补括号，NOT 子表达式非原子必加括号。
## 畸形 tokens 返回 "" 并 push_warning。
static func _cond_to_infix(tokens: Array) -> String:
	var stack: Array = []
	for t in tokens:
		if not (t is Array) or (t as Array).is_empty():
			return _cond_malformed(tokens)
		var tag: int = t[0]
		match tag:
			Instruction.CondTag.PUSH_NUM:
				var f := float(t[1])
				stack.append({"text": "%d" % int(f) if f == floorf(f) else str(f), "prec": 4})
			Instruction.CondTag.PUSH_VAR:
				stack.append({"text": str(t[1]), "prec": 4})
			Instruction.CondTag.CMP:
				if stack.size() < 2:
					return _cond_malformed(tokens)
				var cmp_rhs: Dictionary = stack.pop_back()
				var cmp_lhs: Dictionary = stack.pop_back()
				# 比较操作数按文法必为原子（变量/数字），非原子防御性补括号
				stack.append({"text": "%s %s %s" % [_cond_child(cmp_lhs, 4, true), t[1], _cond_child(cmp_rhs, 4, true)], "prec": 3})
			Instruction.CondTag.NOT:
				if stack.is_empty():
					return _cond_malformed(tokens)
				var sub: Dictionary = stack.pop_back()
				var s: String = sub["text"] if sub["prec"] >= 4 else "(" + sub["text"] + ")"
				stack.append({"text": "not " + s, "prec": 2})
			Instruction.CondTag.AND, Instruction.CondTag.OR:
				if stack.size() < 2:
					return _cond_malformed(tokens)
				var prec := 1 if tag == Instruction.CondTag.AND else 0
				var op := " and " if tag == Instruction.CondTag.AND else " or "
				var rhs: Dictionary = stack.pop_back()
				var lhs: Dictionary = stack.pop_back()
				stack.append({"text": _cond_child(lhs, prec, true) + op + _cond_child(rhs, prec, false), "prec": prec})
			_:
				return _cond_malformed(tokens)
	if stack.size() != 1:
		return _cond_malformed(tokens)
	return stack[0]["text"]


## 子表达式按上下文优先级补括号：左侧同级不补（左结合），右侧同级也补（还原唯一）
static func _cond_child(sub: Dictionary, ctx_prec: int, is_left: bool) -> String:
	var prec: int = sub["prec"]
	var need_paren := prec < ctx_prec if is_left else prec <= ctx_prec
	return "(" + sub["text"] + ")" if need_paren else sub["text"]


static func _cond_malformed(tokens: Array) -> String:
	push_warning("GraphDumper: 畸形条件记号流，无法还原中缀: %s" % [tokens])
	return ""


## 剧本宏观关系图（bgals-overview/1）：输入若干图 JSON（build 的产物），提取 jump 连接与节点统计。
## begin 为起始剧本名；missing 为 jump 目标中不存在于 scripts 的名字（main_menu 特殊目标除外）。
static func build_overview(graphs: Array[Dictionary], begin: String) -> Dictionary:
	var names := {}
	var scripts: Array[Dictionary] = []
	var edges: Array[Dictionary] = []
	var edge_seen := {}
	var targets := {}
	for g in graphs:
		var script: String = g["script"]
		names[script] = true
		var stats := {"dialogue": 0, "inst": 0, "option_group": 0, "cond": 0, "jump": 0}
		for node in g["nodes"]:
			var kind: String = node["kind"]
			if stats.has(kind):
				stats[kind] += 1
			if kind == "jump":
				var target: String = node["target"]
				targets[target] = true
				var key := "%s->%s" % [script, target]
				if not edge_seen.has(key):
					edge_seen[key] = true
					edges.append({"from": script, "to": target, "kind": "jump"})
		scripts.append({
			"name": script,
			"dialogues": stats["dialogue"],
			"insts": stats["inst"],
			"options": stats["option_group"],
			"conds": stats["cond"],
			"jumps": stats["jump"],
		})
	var missing: Array[String] = []
	for t in targets:
		if not names.has(t) and t != "main_menu":
			missing.append(t)
	scripts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"])
	return {
		"format": "bgals-overview/1",
		"compiler": DialogueImporter.COMPILER_VERSION,
		"begin": begin,
		"scripts": scripts,
		"edges": edges,
		"missing": missing,
	}
