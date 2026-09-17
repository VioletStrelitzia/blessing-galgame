class_name DialogueImporter extends Node
const LOG_TAG := "Importer"

## BGalS v2 编译前端：行分类 → 缩进块拍平 → 线性 GalEventItemSequence。
## 产物中 基类 Instruction = 独立指令，PrevInstruction/PostInstruction = 前/后指令。

const COMPILER_VERSION := "bgals2"

var check: bool = true
var read_dir: String = "res://scripts"
var save_dir: String = "res://GalSs"
var hash_file_path: String

var saved_hash: Dictionary = {}
var need_update: bool = false

const CHUNK_SIZE = 1024

# 行级指令保留字表（首词命中即按指令解析；自由文本参数永不进键位）
const RESERVED_KEYS: Array[String] = [
	"bg", "music", "sfx", "voice", "char", "var",
	"if", "elif", "else", "jump", "begin", "wait", "scene", "trans",
]

# 文本内联锚点白名单（指令名后必须跟空格或 ]；pause 由打字机消费）
const ANCHOR_WHITELIST: Array[String] = [
	"sfx", "voice", "char", "bg", "music", "trans", "pause",
]

# 缩进单位：一级 = 4 空格（Tab 视为一级）
const INDENT_UNIT := 4

signal res_update_load_finished

# 诊断收集：[{file, line, level, msg}]
var _diagnostics: Array[Dictionary] = []

static var _regex_condition: RegEx = null


func _ready() -> void:
	hash_file_path = save_dir.path_join(".hash")
	if DirAccess.dir_exists_absolute(save_dir):
		Utils.open_dir(save_dir)
		if FileAccess.file_exists(hash_file_path):
			saved_hash = Utils.load_json(hash_file_path)
	# 编译器版本盐：不匹配则全量重编（枚举按整数序列化，旧产物会错位）
	if saved_hash.get("_compiler", "") != COMPILER_VERSION:
		GalLogger.info(LOG_TAG, "编译器版本变更（%s → %s），全量重编" % [saved_hash.get("_compiler", "无"), COMPILER_VERSION])
		saved_hash.clear()
		saved_hash["_compiler"] = COMPILER_VERSION
		need_update = true
	import_dialogues(read_dir)
	if need_update:
		Utils.save_json(hash_file_path, saved_hash)
		GalLogger.info(LOG_TAG, "导入完成，已更新哈希值和资源列表")
	_flush_diagnostics()
	res_update_load_finished.emit()


func import_dialogues(path: String):
	# 目录不存在（如导出包排除了 scripts/）时安静跳过，直接运行既有产物
	if not DirAccess.dir_exists_absolute(path):
		GalLogger.info(LOG_TAG, "剧本目录不存在，跳过导入: " + path)
		return
	var file_list := Utils.get_file_list(path, true, false)
	for file_path in file_list:
		var script_name := file_path.get_basename().replace("/", "_").replace("\\", "_")
		if script_name == "main_menu":
			_diagnose(path.path_join(file_path), 0, "error", "剧本名 main_menu 与 jump main_menu 特殊目标冲突，请改名")
			continue
		import_dialogue(
			path.path_join(file_path),
			save_dir.path_join(script_name + ".tres")
		)


func import_dialogue(text_path: String, output_path: String) -> void:
	var current_hash = calculate_text_hash(text_path)
	if current_hash.is_empty():
		GalLogger.error(LOG_TAG, "无法计算文本哈希: " + text_path)
		return

	if saved_hash.has(text_path) and saved_hash[text_path] == current_hash and FileAccess.file_exists(output_path):
		GalLogger.debug(LOG_TAG, "资源无变化: " + text_path)
		return

	saved_hash[text_path] = current_hash
	need_update = true
	GalLogger.debug(LOG_TAG, "导入资源: " + text_path)

	var file = Utils.open_file(text_path, FileAccess.READ)
	var text = file.get_as_text()
	file.close()

	var diags: Array[Dictionary] = []
	var dialogue_group := parse_script(text.split("\n"), text_path, diags)
	_diagnostics.append_array(diags)
	if _has_error(diags):
		GalLogger.error(LOG_TAG, "存在编译错误，跳过产物保存: " + text_path)
		return

	dialogue_group.compiler = COMPILER_VERSION

	if not DirAccess.dir_exists_absolute(output_path.get_base_dir()):
		Utils.make_dir_absolute(output_path.get_base_dir())

	if ResourceSaver.save(dialogue_group, output_path) != OK:
		GalLogger.error(LOG_TAG, "保存失败: " + output_path)
	else:
		GalLogger.debug(LOG_TAG, "生成成功: " + output_path)


func calculate_text_hash(file_path: String) -> String:
	var ctx = HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK: return ""
	var file = Utils.open_file(file_path)
	if not file: return ""
	while file.get_position() < file.get_length():
		ctx.update(file.get_buffer(min(file.get_length() - file.get_position(), CHUNK_SIZE)))
	file.close()
	return ctx.finish().hex_encode()


static func _has_error(diags: Array[Dictionary]) -> bool:
	for d in diags:
		if d["level"] == "error":
			return true
	return false


func _flush_diagnostics() -> void:
	for d in _diagnostics:
		var msg := "%s:%d %s" % [d["file"], d["line"], d["msg"]]
		if d["level"] == "error":
			GalLogger.error(LOG_TAG, msg)
		else:
			GalLogger.warn(LOG_TAG, msg)
	if not _diagnostics.is_empty():
		GalLogger.info(LOG_TAG, "剧本诊断：共 %d 条" % _diagnostics.size())
	_diagnostics.clear()


static func _diagnose_static(diags: Array[Dictionary], file: String, line: int, level: String, msg: String) -> void:
	diags.append({"file": file, "line": line, "level": level, "msg": msg})


func _diagnose(file: String, line: int, level: String, msg: String) -> void:
	_diagnose_static(_diagnostics, file, line, level, msg)


# ============================================================
# 解析器（静态，供编译期与 Renderer 锚点复用）
# ============================================================

## 全文解析：行分类 + 缩进块拍平 + 诊断
static func parse_script(lines: PackedStringArray, file_name: String, diags: Array[Dictionary]) -> GalEventItemSequence:
	var gal_event_item_sequence := GalEventItemSequence.new()
	var seq: Array[GalEventItem] = gal_event_item_sequence.seq

	# 块上下文栈：{type: "option"/"if", indent: int, has_else: bool}
	var block_stack: Array[Dictionary] = []
	var prev_indent := 0
	var prev_block_head_kind := ""  # 上一行若为块头：""/"option"/"if"
	var seen_dialogue := false

	for i in range(lines.size()):
		var line_no := i + 1
		var raw := lines[i]

		# 预处理：全角空格报错；Tab 视为一级缩进
		if raw.contains("　"):
			_diagnose_static(diags, file_name, line_no, "error", "行首含全角空格，请改用半角空格缩进")
			continue
		var expanded := raw.replace("\t", "    ")

		# 空行/注释：不打断块结构
		var stripped := expanded.strip_edges()
		if stripped.is_empty() or stripped.begins_with("//") or stripped.begins_with("#"):
			continue

		# 计算缩进层级（必须为 4 的倍数，Tab 已展开）
		var space_count := expanded.length() - expanded.strip_edges(true, false).length()
		if space_count % INDENT_UNIT != 0:
			_diagnose_static(diags, file_name, line_no, "error", "缩进深度必须是 %d 空格的整数倍" % INDENT_UNIT)
			continue
		var indent := space_count / INDENT_UNIT

		# 行首转义：整行强制对话
		var force_dialogue := stripped.begins_with("\\")
		if force_dialogue:
			stripped = stripped.substr(1)

		var kind := _classify_line(stripped) if not force_dialogue else LineKind.DIALOGUE

		# if 类块头后的空块校验（选项允许空体=直接汇合，故只查 if 链）
		if prev_block_head_kind == "if" and indent <= prev_indent:
			_diagnose_static(diags, file_name, line_no, "error", "if/elif/else 块头后缺少缩进体（空块）")
			prev_block_head_kind = ""

		# elif/else 与兄弟选项优先于同级回退（它们与块头同级），
		# 但需先关闭比它们更深的块（内层 if/选项组）
		if kind == LineKind.ELIF_HEAD or kind == LineKind.ELSE_HEAD:
			while not block_stack.is_empty() and indent < block_stack.back()["indent"]:
				_close_block(block_stack.pop_back(), seq)
			if block_stack.is_empty() or block_stack.back()["type"] != "if" or indent != block_stack.back()["indent"]:
				_diagnose_static(diags, file_name, line_no, "error", "孤立的 elif/else（无配对 if 或缩进不齐）")
				continue
			if block_stack.back()["has_else"]:
				_diagnose_static(diags, file_name, line_no, "error", "else 之后不允许再接 elif/else")
				continue
			_emit_condition_head(kind, stripped, seq, diags, file_name, line_no)
			if kind == LineKind.ELSE_HEAD:
				block_stack.back()["has_else"] = true
			prev_block_head_kind = "if"
			prev_indent = indent
			continue

		if kind == LineKind.OPTION_ITEM:
			while not block_stack.is_empty() and indent < block_stack.back()["indent"]:
				_close_block(block_stack.pop_back(), seq)
		if kind == LineKind.OPTION_ITEM and not block_stack.is_empty() \
			and block_stack.back()["type"] == "option" and indent == block_stack.back()["indent"]:
			_emit_option(stripped, seq, diags, file_name, line_no)
			prev_block_head_kind = "option"
			prev_indent = indent
			continue

		# 缩进回退：关闭所有块缩进 >= 当前缩进的块
		while not block_stack.is_empty() and indent <= block_stack.back()["indent"]:
			_close_block(block_stack.pop_back(), seq)

		# 缩进加深只能跟在块头后
		if indent > prev_indent and prev_block_head_kind.is_empty():
			_diagnose_static(diags, file_name, line_no, "error", "缩进加深只能跟在选项/条件块头之后")
			continue

		match kind:
			LineKind.OPTION_ITEM:
				# 新选项组：嵌套检查
				for b in block_stack:
					if b["type"] == "option":
						_diagnose_static(diags, file_name, line_no, "error", "选项组不支持嵌套")
						break
				block_stack.append({"type": "option", "indent": indent, "has_else": false})
				_emit_option(stripped, seq, diags, file_name, line_no)
				prev_block_head_kind = "option"
			LineKind.IF_HEAD:
				_emit_condition_head(kind, stripped, seq, diags, file_name, line_no)
				block_stack.append({"type": "if", "indent": indent, "has_else": false})
				prev_block_head_kind = "if"
			LineKind.DIALOGUE:
				seen_dialogue = true
				_emit_dialogue(stripped, seq, diags, file_name, line_no)
				prev_block_head_kind = ""
			LineKind.INSTRUCTION_POST, LineKind.INSTRUCTION_PREV, LineKind.INSTRUCTION_FREE:
				if (kind == LineKind.INSTRUCTION_POST) and not seen_dialogue:
					_diagnose_static(diags, file_name, line_no, "warning", "后指令 > 之前没有任何对话")
				_emit_instruction(stripped, kind, seq, diags, file_name, line_no)
				prev_block_head_kind = ""
		prev_indent = indent

	# 文件结束：关闭未闭合块（缩进回退到 0 以下）
	while not block_stack.is_empty():
		_close_block(block_stack.pop_back(), seq)

	return gal_event_item_sequence


enum LineKind {
	DIALOGUE,
	INSTRUCTION_PREV,  # < 前指令
	INSTRUCTION_POST,  # > 后指令
	INSTRUCTION_FREE,  # 独立指令
	OPTION_ITEM,       # * 选项
	IF_HEAD,
	ELIF_HEAD,
	ELSE_HEAD,
}


static func _classify_line(text: String) -> LineKind:
	if text.begins_with(">"):
		return LineKind.INSTRUCTION_POST
	if text.begins_with("<"):
		return LineKind.INSTRUCTION_PREV
	if text.begins_with("*"):
		return LineKind.OPTION_ITEM
	var first_word := text.split(" ", false, 1)[0].split("\t", false, 1)[0]
	if first_word == "if":
		return LineKind.IF_HEAD
	if first_word == "elif":
		return LineKind.ELIF_HEAD
	if first_word == "else":
		return LineKind.ELSE_HEAD
	if first_word in RESERVED_KEYS:
		return LineKind.INSTRUCTION_FREE
	return LineKind.DIALOGUE


static func _close_block(block: Dictionary, seq: Array[GalEventItem]) -> void:
	match block["type"]:
		"option":
			seq.append(Instruction.new(Instruction.Head.OPTION_END))
		"if":
			seq.append(Instruction.new(Instruction.Head.END_IF))


# --- 指令行 ---

static func _emit_instruction(text: String, kind: LineKind, seq: Array[GalEventItem], diags: Array[Dictionary], file: String, line_no: int) -> void:
	var content := text
	if kind == LineKind.INSTRUCTION_POST or kind == LineKind.INSTRUCTION_PREV:
		content = text.substr(1).strip_edges()

	var ins := parse_instruction_line(content, diags, file, line_no)
	if ins == null:
		return
	match kind:
		LineKind.INSTRUCTION_POST:
			seq.append(PostInstruction.new(ins.head, _params_to_strings(ins.params)))
		LineKind.INSTRUCTION_PREV:
			seq.append(PrevInstruction.new(ins.head, _params_to_strings(ins.params)))
		_:
			seq.append(ins)


## 把已转型的 params 还原为字符串数组供子类构造器二次转型
## （Prev/PostInstruction 构造器复用 Instruction 的参数 spec 表）
static func _params_to_strings(params: Array[Variant]) -> Array[String]:
	var out: Array[String] = []
	for p in params:
		out.append(str(p))
	return out


## 解析单行指令（无前缀标记）。失败返回 null 并记录诊断。
## 也被 DialogueRenderer 用于锚点解析（diags 传空数组则静默返回 null）。
static func parse_instruction_line(content: String, diags: Array[Dictionary] = [], file: String = "", line_no: int = 0) -> Instruction:
	var args := _split_cli_args(content)
	if args.is_empty():
		return null
	var key: String = args[0]
	var rest := args.slice(1)

	match key:
		"bg":
			var kv := _parse_kv(rest, ["time"])
			if kv["pos"].size() < 1:
				return _fail(diags, file, line_no, "bg 缺少背景引用名")
			var bg_time: String = kv["kv"].get("time", "0")
			if not _check_float(bg_time, "bg time", diags, file, line_no):
				return null
			return Instruction.new(Instruction.Head.SET_BACKGROUND, [kv["pos"][0], bg_time])
		"music":
			if rest.size() > 0 and rest[0] in ["stop", "pause", "resume"]:
				var sub: String = rest[0]
				var kv := _parse_kv(rest.slice(1), ["fade"] if sub == "stop" else [])
				match sub:
					"stop":
						return Instruction.new(Instruction.Head.MUSIC_STOP, [kv["kv"].get("fade", "1.0")])
					"pause":
						return Instruction.new(Instruction.Head.MUSIC_PAUSE)
					"resume":
						return Instruction.new(Instruction.Head.MUSIC_RESUME)
			var kv := _parse_kv(rest, ["from", "loop", "fade"])
			if kv["pos"].is_empty():
				return _fail(diags, file, line_no, "music 缺少音乐引用名")
			return Instruction.new(Instruction.Head.MUSIC_PLAY, [
				kv["pos"][0],
				kv["kv"].get("from", "0"),
				kv["kv"].get("loop", "true"),
				kv["kv"].get("fade", "1.0"),
			])
		"sfx", "voice":
			var kv := _parse_kv(rest, ["from"])
			if kv["pos"].is_empty():
				return _fail(diags, file, line_no, key + " 缺少音频引用名")
			var head := Instruction.Head.SFX_PLAY if key == "sfx" else Instruction.Head.VOICE_PLAY
			return Instruction.new(head, [kv["pos"][0], kv["kv"].get("from", "0")])
		"char":
			return _parse_char(rest, diags, file, line_no)
		"var":
			return _parse_var(rest, diags, file, line_no)
		"jump":
			if rest.is_empty():
				return _fail(diags, file, line_no, "jump 缺少目标剧本名")
			if rest[0] == "main_menu":
				return Instruction.new(Instruction.Head.JUMP_MAIN_MENU)
			return Instruction.new(Instruction.Head.JUMP_SCRIPT, [rest[0]])
		"begin":
			if rest.is_empty():
				return _fail(diags, file, line_no, "begin 缺少剧本名")
			return Instruction.new(Instruction.Head.SET_BEGIN_SCRIPT, [rest[0]])
		"wait":
			if rest.is_empty():
				return _fail(diags, file, line_no, "wait 缺少秒数")
			if not _check_float(rest[0], "wait", diags, file, line_no):
				return null
			return Instruction.new(Instruction.Head.WAIT, [rest[0]])
		"scene":
			return _parse_scene(rest, diags, file, line_no)
		"trans":
			return _parse_trans(rest, diags, file, line_no)

	# 未定义指令（不应到达：保留字表已过滤）
	_diagnose_static(diags, file, line_no, "error", "未定义指令: " + key + "（若这是对话文本，请在行首加 \\ 转义）")
	return null


static func _fail(diags: Array[Dictionary], file: String, line_no: int, msg: String) -> Instruction:
	_diagnose_static(diags, file, line_no, "error", msg)
	return null


## 数值参数校验（保留字劫持防护的收尾：旁白误入指令时参数必然非法）
static func _check_float(value: String, name: String, diags: Array[Dictionary], file: String, line_no: int) -> bool:
	if value.is_valid_float():
		return true
	_diagnose_static(diags, file, line_no, "error", "%s 参数必须是数字: %s（若这是对话文本，请在行首加 \\ 转义）" % [name, value])
	return false


## 键值参数解析：positional 进 pos，key:value 进 kv；未知键报警告
static func _parse_kv(args: Array[String], known_keys: Array, diags: Array[Dictionary] = [], file: String = "", line_no: int = 0) -> Dictionary:
	var pos: Array[String] = []
	var kv: Dictionary = {}
	for a in args:
		var colon := a.find(":")
		if colon > 0 and a.substr(0, colon).is_valid_identifier():
			var k := a.substr(0, colon)
			var v := a.substr(colon + 1)
			if k in known_keys:
				kv[k] = v
			else:
				_diagnose_static(diags, file, line_no, "warning", "未知参数键: " + k)
		else:
			pos.append(a)
	return {"pos": pos, "kv": kv}


static func _parse_char(rest: Array[String], diags: Array[Dictionary], file: String, line_no: int) -> Instruction:
	if rest.size() < 2:
		return _fail(diags, file, line_no, "char 缺少实例索引或子动作（setup/show/hide/move/texture/wait）")
	if not rest[0].is_valid_int():
		return _fail(diags, file, line_no, "char 实例索引必须是整数: " + rest[0])
	var idx := rest[0]
	var sub := rest[1]
	var tail := rest.slice(2)

	match sub:
		"setup":
			if tail.size() < 2:
				return _fail(diags, file, line_no, "char setup 需要 <立绘> <x,y>（逗号后无空格）")
			var xy := _parse_xy(tail[1], diags, file, line_no)
			if xy.is_empty():
				return null
			return Instruction.new(Instruction.Head.CHAR_SETUP, [idx, tail[0], xy[0], xy[1]])
		"show", "hide":
			var kv := _parse_kv(tail, ["time", "wait"], diags, file, line_no)
			var time_str: String = kv["kv"].get("time", "1.0")
			if not _check_float(time_str, "char " + sub + " time", diags, file, line_no):
				return null
			var head := Instruction.Head.CHAR_SHOW_FADE if sub == "show" else Instruction.Head.CHAR_HIDE_FADE
			return Instruction.new(head, [idx, time_str, kv["kv"].get("wait", "false")])
		"move":
			var kv := _parse_kv(tail, ["time", "wait"], diags, file, line_no)
			if kv["pos"].is_empty():
				return _fail(diags, file, line_no, "char move 缺少目标坐标 <x,y>（逗号后无空格）")
			var xy := _parse_xy(kv["pos"][0], diags, file, line_no)
			if xy.is_empty():
				return null
			var move_time: String = kv["kv"].get("time", "1.0")
			if not _check_float(move_time, "char move time", diags, file, line_no):
				return null
			return Instruction.new(Instruction.Head.CHAR_MOVE_TO, [idx, xy[0], xy[1], move_time, kv["kv"].get("wait", "false")])
		"texture":
			if tail.is_empty():
				return _fail(diags, file, line_no, "char texture 缺少立绘引用名")
			return Instruction.new(Instruction.Head.CHAR_CHANGE_TEXTURE, [idx, tail[0]])
		"wait":
			if tail.is_empty():
				return _fail(diags, file, line_no, "char wait 缺少秒数")
			if not _check_float(tail[0], "char wait", diags, file, line_no):
				return null
			if tail[0].to_float() < 0:
				return _fail(diags, file, line_no, "char wait 负秒暂停语义已废除，秒数必须 >= 0")
			return Instruction.new(Instruction.Head.CHAR_WAIT, [idx, tail[0]])
	return _fail(diags, file, line_no, "未知 char 子动作: " + sub + "（应为 setup/show/hide/move/texture/wait）")


## 坐标 "x,y" → [x_str, y_str]；失败报错并返回空数组
static func _parse_xy(token: String, diags: Array[Dictionary], file: String, line_no: int) -> Array[String]:
	var parts := token.split(",")
	if parts.size() != 2 or not parts[0].is_valid_float() or not parts[1].is_valid_float():
		_diagnose_static(diags, file, line_no, "error", "坐标格式应为 x,y（逗号后无空格）: " + token)
		return []
	return [parts[0], parts[1]]


static func _parse_var(rest: Array[String], diags: Array[Dictionary], file: String, line_no: int) -> Instruction:
	if rest.size() < 3:
		return _fail(diags, file, line_no, "var 语法: var <名> <op> <值|变量>（op 为 = += -= *= /=），或 var <名> = random <min> <max>")
	var key := rest[0]
	var op := rest[1]

	# var x = random 0 100
	if op == "=" and rest.size() >= 5 and rest[2] == "random":
		if not _check_float(rest[3], "random min", diags, file, line_no) or not _check_float(rest[4], "random max", diags, file, line_no):
			return null
		return Instruction.new(Instruction.Head.VAR_RANDOM, [key, rest[3], rest[4]])

	if rest.size() != 3:
		return _fail(diags, file, line_no, "var 右值过多: " + " ".join(rest.slice(3)))

	var head: Instruction.Head
	match op:
		"=": head = Instruction.Head.VAR_SET
		"+=": head = Instruction.Head.VAR_ADD
		"-=": head = Instruction.Head.VAR_SUB
		"*=": head = Instruction.Head.VAR_MUL
		"/=": head = Instruction.Head.VAR_DIV
		_:
			return _fail(diags, file, line_no, "var 未知操作符: " + op)
	return Instruction.new(head, [key, rest[2]])


static func _parse_scene(rest: Array[String], diags: Array[Dictionary], file: String, line_no: int) -> Instruction:
	if rest.is_empty():
		return _fail(diags, file, line_no, "scene 缺少子动作（mount/unmount）")
	var sub := rest[0]
	var tail := rest.slice(1)
	match sub:
		"mount":
			var kv := _parse_kv(tail, ["time", "anim"], diags, file, line_no)
			if kv["pos"].size() < 3:
				return _fail(diags, file, line_no, "scene mount 需要 <类型> <名称> <路径>")
			return Instruction.new(Instruction.Head.SCENE_MOUNT, [
				kv["pos"][0], kv["pos"][1], kv["pos"][2],
				kv["kv"].get("time", "0"), kv["kv"].get("anim", "fade"),
			])
		"unmount":
			var kv := _parse_kv(tail, ["time", "anim", "free"], diags, file, line_no)
			if kv["pos"].size() < 2:
				return _fail(diags, file, line_no, "scene unmount 需要 <类型> <名称>")
			return Instruction.new(Instruction.Head.SCENE_UNMOUNT, [
				kv["pos"][0], kv["pos"][1],
				kv["kv"].get("time", "0"), kv["kv"].get("anim", "fade"), kv["kv"].get("free", "true"),
			])
	return _fail(diags, file, line_no, "未知 scene 子动作: " + sub)


static func _parse_trans(rest: Array[String], diags: Array[Dictionary], file: String, line_no: int) -> Instruction:
	if rest.is_empty():
		return _fail(diags, file, line_no, "trans 缺少方向（in/out）")
	var sub := rest[0]
	var kv := _parse_kv(rest.slice(1), ["time", "anim", "wait"], diags, file, line_no)
	match sub:
		"in":
			return Instruction.new(Instruction.Head.TRANSITION_IN, [
				kv["kv"].get("time", "1.0"), kv["kv"].get("anim", "fade_in"), kv["kv"].get("wait", "true"),
			])
		"out":
			return Instruction.new(Instruction.Head.TRANSITION_OUT, [
				kv["kv"].get("time", "1.0"), kv["kv"].get("anim", "fade_out"), kv["kv"].get("wait", "true"),
			])
	return _fail(diags, file, line_no, "未知 trans 方向: " + sub)


# --- 选项与条件 ---

static func _emit_option(text: String, seq: Array[GalEventItem], diags: Array[Dictionary], file: String, line_no: int) -> void:
	var body := _strip_inline_comment(text.substr(1).strip_edges())
	if body.is_empty():
		_diagnose_static(diags, file, line_no, "error", "选项缺少文本")
		return

	var option_text := ""
	var cond := ""

	if body.begins_with("\""):
		# 引号包裹文本：不解析 if:
		var end_quote := body.find("\"", 1)
		if end_quote == -1:
			_diagnose_static(diags, file, line_no, "error", "选项文本引号未闭合")
			return
		option_text = body.substr(1, end_quote - 1)
		var tail := body.substr(end_quote + 1).strip_edges()
		if tail.begins_with("if:"):
			cond = tail.substr(3).strip_edges()
		elif not tail.is_empty():
			_diagnose_static(diags, file, line_no, "warning", "选项文本后的内容被忽略: " + tail)
	else:
		# 免引号文本：按行尾方向最后一个「 if:」（前有空格）切分条件
		var if_pos := body.rfind(" if:")
		if if_pos != -1:
			option_text = body.substr(0, if_pos).strip_edges()
			cond = body.substr(if_pos + 4).strip_edges()
		else:
			option_text = body

	if cond.is_empty():
		seq.append(Instruction.new(Instruction.Head.OPTION, [option_text]))
	else:
		var parts := _parse_condition(cond, diags, file, line_no)
		if parts.is_empty():
			return
		seq.append(Instruction.new(Instruction.Head.OPTION, [option_text, parts[0], parts[1], parts[2]]))


static func _emit_condition_head(kind: LineKind, text: String, seq: Array[GalEventItem], diags: Array[Dictionary], file: String, line_no: int) -> void:
	if kind == LineKind.ELSE_HEAD:
		seq.append(Instruction.new(Instruction.Head.ELSE))
		return
	var key_word := "if" if kind == LineKind.IF_HEAD else "elif"
	var cond := _strip_inline_comment(text.substr(key_word.length()).strip_edges())
	var parts := _parse_condition(cond, diags, file, line_no)
	if parts.is_empty():
		return
	var head := Instruction.Head.IF if kind == LineKind.IF_HEAD else Instruction.Head.ELSE_IF
	seq.append(Instruction.new(head, parts))


## 行内注释截断（引号外 //）；选项/条件行专用，指令行由 _split_cli_args 处理
static func _strip_inline_comment(text: String) -> String:
	var in_quote := false
	var i := 0
	while i < text.length():
		var c := text[i]
		if c == '"':
			in_quote = !in_quote
		elif not in_quote and c == "/" and i + 1 < text.length() and text[i + 1] == "/":
			return text.substr(0, i).strip_edges()
		i += 1
	return text


## 条件表达式：<左值> <比较符> <右值>（比较符两侧空格可选）
## 返回 [left, op, right]；失败返回空数组
static func _parse_condition(cond: String, diags: Array[Dictionary], file: String, line_no: int) -> Array[String]:
	if _regex_condition == null:
		_regex_condition = RegEx.new()
		_regex_condition.compile("^(.+?)\\s*(==|!=|>=|<=|>|<)\\s*(.+?)$")
	var m := _regex_condition.search(cond.strip_edges())
	if m == null:
		_diagnose_static(diags, file, line_no, "error", "条件表达式无法解析: " + cond + "（应为 <左值> <比较符> <右值>，比较符仅 == != > >= < <=）")
		return []
	var op := m.get_string(2)
	return [m.get_string(1).strip_edges(), op, m.get_string(3).strip_edges()]


# --- 对话行 ---

static func _emit_dialogue(text: String, seq: Array[GalEventItem], diags: Array[Dictionary], file: String, line_no: int) -> void:
	_validate_anchors(text, diags, file, line_no)

	var speaker := ""
	var content := text
	var colon_index := text.find(":")
	if colon_index == -1:
		colon_index = text.find("：")
	if colon_index != -1:
		speaker = text.substr(0, colon_index).strip_edges()
		content = text.substr(colon_index + 1).strip_edges()

	seq.append(DialogueItem.new(speaker, content))


## 锚点校验（不剥离）：白名单指令名 + 定界符判定，禁止流程指令
static func _validate_anchors(text: String, diags: Array[Dictionary], file: String, line_no: int) -> void:
	var i := 0
	var length := text.length()
	while i < length:
		var c := text[i]
		if c == "\\":
			i += 2
			continue
		if c != "[":
			i += 1
			continue
		var end := text.find("]", i)
		if end == -1:
			break
		var inner := text.substr(i + 1, end - i - 1)
		var first_word := inner.split(" ", false, 1)[0]
		# 指令名后必须跟定界符（空格或即结尾）
		if first_word in ANCHOR_WHITELIST and (inner.length() == first_word.length() or inner[first_word.length()] == " "):
			if first_word == "pause":
				var arg := inner.substr(5).strip_edges()
				if not arg.is_valid_float():
					_diagnose_static(diags, file, line_no, "error", "锚点 pause 需要秒数: [" + inner + "]")
			else:
				# 借解析器校验锚点指令合法性（流程指令不在白名单，天然拒绝）
				var anchor_diags: Array[Dictionary] = []
				parse_instruction_line(inner, anchor_diags, file, line_no)
				for d in anchor_diags:
					diags.append(d)
		i = end + 1


# --- CLI 分词器 ---

static func _split_cli_args(text: String) -> Array[String]:
	var args: Array[String] = []
	var current_arg := ""
	var in_quote := false
	var length := text.length()
	var i := 0

	while i < length:
		var c := text[i]

		# 行内注释
		if not in_quote and c == "/" and i + 1 < length and text[i + 1] == "/":
			break

		# 引号处理
		if c == '"':
			in_quote = !in_quote
			i += 1
			continue

		# 分隔符处理
		if (c == " " or c == "\t") and not in_quote:
			if not current_arg.is_empty():
				args.append(current_arg)
				current_arg = ""
		else:
			current_arg += c

		i += 1

	if not current_arg.is_empty():
		args.append(current_arg)

	return args
