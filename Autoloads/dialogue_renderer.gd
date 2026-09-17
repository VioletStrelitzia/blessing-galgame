class_name DialogueRenderer
## BGalS v2 对话文本渲染器：一次线性扫描完成——
## 转义处理（\[ \{ \\）、{var} 插值求值（未定义按 0）、白名单锚点剥离。
## 锚点索引基准 = 渲染后显示文本的字符串索引（含 BBCode 标签原文），
## 与 DialogueUI 打字循环的原始串游标同口径。

## render(raw, vars) -> {"text": String, "anchors": Array[Dictionary]}
## anchors 元素：{"index": int, "ins": Instruction}
## 其中 head == WAIT 的锚点为打字机暂停（[pause 秒]），由 DialogueUI 内部消费。
## vars 由调用方传入（静态工具不依赖 autoload，-s 模式下 Global 标识符不可编译）。
static func render(raw: String, vars: Dictionary) -> Dictionary:
	var text := ""
	var anchors: Array[Dictionary] = []
	var i := 0
	var length := raw.length()

	while i < length:
		var c := raw[i]

		# 转义：\[ \{ \\ → 字面量
		if c == "\\" and i + 1 < length:
			var next := raw[i + 1]
			if next == "[" or next == "{" or next == "\\":
				text += next
				i += 2
				continue
			# 非转义组合：反斜杠原样保留
			text += c
			i += 1
			continue

		# {var} 插值
		if c == "{":
			var close := raw.find("}", i)
			if close != -1:
				var var_name := raw.substr(i + 1, close - i - 1).strip_edges()
				if var_name.is_valid_identifier():
					text += _format_var(var_name, vars)
					i = close + 1
					continue
			# 非插值：原样保留
			text += c
			i += 1
			continue

		# [指令 ...] 锚点：白名单 + 定界符判定，否则留给 BBCode
		if c == "[":
			var close := raw.find("]", i)
			if close != -1:
				var inner := raw.substr(i + 1, close - i - 1)
				var first_word := inner.split(" ", false, 1)[0]
				var is_anchor := first_word in DialogueImporter.ANCHOR_WHITELIST \
					and (inner.length() == first_word.length() or inner[first_word.length()] == " ")
				if is_anchor:
					var ins := _parse_anchor(inner)
					if ins != null:
						anchors.append({"index": text.length(), "ins": ins})
						i = close + 1
						continue
			text += c
			i += 1
			continue

		text += c
		i += 1

	return {"text": text, "anchors": anchors}


## 锚点 → Instruction；[pause 秒] 特化为 WAIT 指令（DialogueUI 内部消费）。
## 失败返回 null（文本原样保留，保守不吞内容）。
static func _parse_anchor(inner: String) -> Instruction:
	if inner.begins_with("pause"):
		var arg := inner.substr(5).strip_edges()
		if not arg.is_valid_float():
			return null
		return Instruction.new(Instruction.Head.WAIT, [arg])
	# 复用编译器的指令解析（静默模式：诊断传空数组）
	return DialogueImporter.parse_instruction_line(inner)


static func _format_var(var_name: String, vars: Dictionary) -> String:
	var value: float = vars.get(var_name, 0.0)
	# 整数值去掉小数部分（好感度 3 而非 3.0）
	if value == floorf(value):
		return str(int(value))
	return str(value)
