class_name DialogueImporter extends Node
const LOG_TAG := "Importer"

## BGalS v2 编译前端：行分类 → 缩进块拍平 → 线性 GalEventItemSequence。
## 产物中 基类 Instruction = 独立指令，PrevInstruction/PostInstruction = 前/后指令。

const COMPILER_VERSION := "bgals2.4"

var check: bool = true
var read_dir: String = "res://scripts"
var save_dir: String = "res://GalSs"
## char 实例上限（编译期越界校验用；< 0 不校验）。本类不引用 autoload（-s 测试可编译），由 ResourceManager 从 Global.config 注入
var char_max: int = -1

## 资源登记表（index.json 各域 key 集合），由 ResourceManager 注入；空 = 不校验引用
## 形态：{"audio": {key: path, ...}, "texture": {...}, ...}
var known_refs: Dictionary = {}
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
	# 跨文件校验上下文：jump/begin 目标名集合（模组 PCK 可提供额外剧本，缺失仅警告不报错）；
	# char 实例上限与资源登记表由 ResourceManager 注入（config.json 的 character.max / index.json）
	var known_scripts: Array[String] = []
	for file_path in file_list:
		known_scripts.append(file_path.get_basename().replace("/", "_").replace("\\", "_"))
	for file_path in file_list:
		var script_name := file_path.get_basename().replace("/", "_").replace("\\", "_")
		if script_name == "main_menu":
			_diagnose(path.path_join(file_path), 0, "error", "剧本名 main_menu 与 jump main_menu 特殊目标冲突，请改名")
			continue
		import_dialogue(
			path.path_join(file_path),
			save_dir.path_join(script_name + ".tres"),
			known_scripts,
			char_max,
			known_refs
		)


func import_dialogue(text_path: String, output_path: String, known_scripts: Array[String] = [], char_max: int = -1, known_refs: Dictionary = {}) -> void:
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
	var dialogue_group := parse_script(text.split("\n"), text_path, diags, known_scripts, char_max, known_refs)
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
## known_scripts 非空时校验 jump/begin 目标（仅警告，模组可提供目标）；char_max >= 0 时校验 char 实例索引（报错）；
## known_refs 非空时对照 index.json 登记表校验 bg/music/sfx/voice/char 立绘引用（仅警告，模组可提供资源）
static func parse_script(lines: PackedStringArray, file_name: String, diags: Array[Dictionary], known_scripts: Array[String] = [], char_max: int = -1, known_refs: Dictionary = {}) -> GalEventItemSequence:
	var gal_event_item_sequence := GalEventItemSequence.new()
	var seq: Array[GalEventItem] = gal_event_item_sequence.seq

	# 块上下文栈：{type: "root"/"option"/"if", indent, has_else, dead, dead_reported}
	# root 伪帧（indent=-1 永不回退关闭）统一顶层与块内的死代码跟踪
	var block_stack: Array[Dictionary] = [
		{"type": "root", "indent": -1, "has_else": false, "dead": false, "dead_reported": false}
	]
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
			while block_stack.size() > 1 and indent < block_stack.back()["indent"]:
				_close_block(block_stack.pop_back(), seq)
			if block_stack.back()["type"] != "if" or indent != block_stack.back()["indent"]:
				_diagnose_static(diags, file_name, line_no, "error", "孤立的 elif/else（无配对 if 或缩进不齐）")
				continue
			if block_stack.back()["has_else"]:
				_diagnose_static(diags, file_name, line_no, "error", "else 之后不允许再接 elif/else")
				continue
			# 新分支是新路径：重置死代码跟踪
			block_stack.back()["dead"] = false
			block_stack.back()["dead_reported"] = false
			_emit_condition_head(kind, stripped, seq, diags, file_name, line_no)
			if kind == LineKind.ELSE_HEAD:
				block_stack.back()["has_else"] = true
			prev_block_head_kind = "if"
			prev_indent = indent
			continue

		if kind == LineKind.OPTION_ITEM:
			while block_stack.size() > 1 and indent < block_stack.back()["indent"]:
				_close_block(block_stack.pop_back(), seq)
		if kind == LineKind.OPTION_ITEM \
			and block_stack.back()["type"] == "option" and indent == block_stack.back()["indent"]:
			# 兄弟选项是新分支：重置死代码跟踪
			block_stack.back()["dead"] = false
			block_stack.back()["dead_reported"] = false
			_check_dead(block_stack.back(), diags, file_name, line_no)
			_emit_option(stripped, seq, diags, file_name, line_no, block_stack.back())
			prev_block_head_kind = "option"
			prev_indent = indent
			continue

		# 缩进回退：关闭所有块缩进 >= 当前缩进的块（root 伪帧 indent=-1 永不关闭）
		while block_stack.size() > 1 and indent <= block_stack.back()["indent"]:
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
				_check_dead(block_stack.back(), diags, file_name, line_no)
				block_stack.append({"type": "option", "indent": indent, "has_else": false, "dead": false, "dead_reported": false, "members": []})
				_emit_option(stripped, seq, diags, file_name, line_no, block_stack.back())
				prev_block_head_kind = "option"
			LineKind.IF_HEAD:
				_check_dead(block_stack.back(), diags, file_name, line_no)
				_emit_condition_head(kind, stripped, seq, diags, file_name, line_no)
				block_stack.append({"type": "if", "indent": indent, "has_else": false, "dead": false, "dead_reported": false})
				prev_block_head_kind = "if"
			LineKind.DIALOGUE:
				seen_dialogue = true
				_check_dead(block_stack.back(), diags, file_name, line_no)
				_emit_dialogue(stripped, seq, diags, file_name, line_no, char_max, known_refs)
				prev_block_head_kind = ""
			LineKind.INSTRUCTION_POST, LineKind.INSTRUCTION_PREV, LineKind.INSTRUCTION_FREE:
				if (kind == LineKind.INSTRUCTION_POST) and not seen_dialogue:
					_diagnose_static(diags, file_name, line_no, "warning", "后指令 > 之前没有任何对话")
				_check_dead(block_stack.back(), diags, file_name, line_no)
				var before := seq.size()
				_emit_instruction(stripped, kind, seq, diags, file_name, line_no, known_scripts, char_max, known_refs)
				# jump 之后同块内容不可达
				if seq.size() > before:
					var head: int = (seq[seq.size() - 1] as Instruction).head
					if head == Instruction.Head.JUMP_SCRIPT or head == Instruction.Head.JUMP_MAIN_MENU:
						block_stack.back()["dead"] = true
				prev_block_head_kind = ""
		prev_indent = indent

	# 文件结束：关闭未闭合块（root 伪帧除外）
	while block_stack.size() > 1:
		_close_block(block_stack.pop_back(), seq)

	# 条件结构目标回填：分支跳转目标直接烧进指令参数（运行时无跳转表、无链式扫描）
	_resolve_condition_targets(seq, diags, file_name)

	return gal_event_item_sequence


## jump 后死代码检查（每块只报一次）
static func _check_dead(frame: Dictionary, diags: Array[Dictionary], file: String, line_no: int) -> void:
	if frame["dead"] and not frame["dead_reported"]:
		frame["dead_reported"] = true
		_diagnose_static(diags, file, line_no, "warning", "jump 之后的内容不可达（跳转后本脚本已卸载）")


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
			# 组结构回填：is_head/body_start/next_option/group_end 烧进参数（运行时零扫描零状态）
			var end_idx := seq.size()
			seq.append(Instruction.new(Instruction.Head.OPTION_END))
			var members: Array = block["members"]
			for k in members.size():
				var ins := seq[members[k]] as Instruction
				ins.params[2] = (k == 0)
				ins.params[3] = members[k] + 1
				ins.params[4] = members[k + 1] if k + 1 < members.size() else -1
				ins.params[5] = end_idx
		"if":
			seq.append(Instruction.new(Instruction.Head.END_IF))


# --- 指令行 ---

static func _emit_instruction(text: String, kind: LineKind, seq: Array[GalEventItem], diags: Array[Dictionary], file: String, line_no: int, known_scripts: Array[String] = [], char_max: int = -1, known_refs: Dictionary = {}) -> void:
	var content := text
	if kind == LineKind.INSTRUCTION_POST or kind == LineKind.INSTRUCTION_PREV:
		content = text.substr(1).strip_edges()
		# 结构语句不接受前/后指令前缀（它们不是指令，时机由块语义决定）
		var head_word := content.split(" ", false, 1)[0]
		if head_word in ["if", "elif", "else"] or content.begins_with("*"):
			_diagnose_static(diags, file, line_no, "error",
				"if/elif/else/选项是块结构语句，不接受前/后指令前缀（去掉行首的 < 或 >）")
			return

	var ins := parse_instruction_line(content, diags, file, line_no, known_scripts, char_max, known_refs)
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
## known_scripts 非空时校验 jump/begin 目标（仅警告）；char_max >= 0 时校验 char 实例索引（报错）；
## known_refs 非空时校验资源引用（仅警告，模组可提供资源）。
static func parse_instruction_line(content: String, diags: Array[Dictionary] = [], file: String = "", line_no: int = 0, known_scripts: Array[String] = [], char_max: int = -1, known_refs: Dictionary = {}) -> Instruction:
	var args := _split_cli_args(content)
	if args.is_empty():
		return null
	var key: String = args[0]
	var rest := args.slice(1)

	match key:
		"bg":
			var kv := _parse_kv(rest, ["time"], diags, file, line_no)
			if kv["pos"].size() < 1:
				return _fail(diags, file, line_no, "bg 缺少背景引用名")
			_warn_unknown_ref(known_refs, "texture", kv["pos"][0], "bg", diags, file, line_no)
			var bg_time: String = kv["kv"].get("time", "0")
			if not _check_float(bg_time, "bg time", diags, file, line_no):
				return null
			return Instruction.new(Instruction.Head.SET_BACKGROUND, [kv["pos"][0], bg_time])
		"music":
			if rest.size() > 0 and rest[0] in ["stop", "pause", "resume", "volume"]:
				var sub: String = rest[0]
				var kv := _parse_kv(rest.slice(1), ["fade"] if sub in ["stop", "volume"] else [], diags, file, line_no)
				match sub:
					"stop":
						if not kv["pos"].is_empty():
							return _fail(diags, file, line_no, "music stop 不接受位置参数")
						var fade: String = kv["kv"].get("fade", "1.0")
						if not _check_float(fade, "music stop fade", diags, file, line_no):
							return null
						return Instruction.new(Instruction.Head.MUSIC_STOP, [fade])
					"volume":
						# 调节在播音轨响度（不重启曲目；同曲守卫下「music 同曲 volume:x」会被吞，调音量必须用它）
						if kv["pos"].is_empty():
							return _fail(diags, file, line_no, "music volume 缺少音量值（0~1）")
						if kv["pos"].size() > 1:
							return _fail(diags, file, line_no, "music volume 只接受一个位置参数（音量值）")
						if not _check_volume(kv["pos"][0], "music volume", diags, file, line_no):
							return null
						var vol_fade: String = kv["kv"].get("fade", "0.5")
						if not _check_float(vol_fade, "music volume fade", diags, file, line_no):
							return null
						return Instruction.new(Instruction.Head.MUSIC_VOLUME, [kv["pos"][0], vol_fade])
					"pause", "resume":
						if not kv["pos"].is_empty():
							return _fail(diags, file, line_no, "music " + sub + " 不接受位置参数")
						return Instruction.new(Instruction.Head.MUSIC_PAUSE if sub == "pause" else Instruction.Head.MUSIC_RESUME)
			var kv := _parse_kv(rest, ["from", "loop", "fade", "fade_in", "fade_out", "volume"], diags, file, line_no)
			if kv["pos"].is_empty():
				return _fail(diags, file, line_no, "music 缺少音乐引用名")
			if kv["pos"].size() > 1:
				return _fail(diags, file, line_no, "music 只接受一个位置参数（引用名），多余: " + " ".join(kv["pos"].slice(1)))
			_warn_unknown_ref(known_refs, "audio", kv["pos"][0], "music", diags, file, line_no)
			var from_str: String = kv["kv"].get("from", "0")
			var loop_str: String = kv["kv"].get("loop", "true")
			# fade 为 fade_in/fade_out 的简写（双侧同值）；显式键覆盖对应侧，可写「快出慢进」
			var fade_in_str: String = kv["kv"].get("fade_in", kv["kv"].get("fade", "1.0"))
			var fade_out_str: String = kv["kv"].get("fade_out", kv["kv"].get("fade", "1.0"))
			var volume_str: String = kv["kv"].get("volume", "1.0")
			if not _check_float(from_str, "music from", diags, file, line_no):
				return null
			if not _check_bool(loop_str, "music loop", diags, file, line_no):
				return null
			if not _check_float(fade_in_str, "music fade_in", diags, file, line_no):
				return null
			if not _check_float(fade_out_str, "music fade_out", diags, file, line_no):
				return null
			if not _check_volume(volume_str, "music volume", diags, file, line_no):
				return null
			return Instruction.new(Instruction.Head.MUSIC_PLAY, [
				kv["pos"][0], from_str, loop_str, fade_in_str, fade_out_str, volume_str,
			])
		"sfx", "voice":
			# stop 子动作：sfx stop [引用]（省略 = 停止全部）；voice stop（单播放器无需引用）
			if rest.size() > 0 and rest[0] == "stop":
				var stop_kv := _parse_kv(rest.slice(1), ["fade"], diags, file, line_no)
				var stop_fade: String = stop_kv["kv"].get("fade", "0.3" if key == "sfx" else "0.1")
				if not _check_float(stop_fade, key + " stop fade", diags, file, line_no):
					return null
				if key == "voice":
					if not stop_kv["pos"].is_empty():
						return _fail(diags, file, line_no, "voice stop 不接受引用参数（语音为单播放器）")
					return Instruction.new(Instruction.Head.VOICE_STOP, [stop_fade])
				if stop_kv["pos"].size() > 1:
					return _fail(diags, file, line_no, "sfx stop 至多一个引用参数")
				if stop_kv["pos"].size() == 1:
					_warn_unknown_ref(known_refs, "audio", stop_kv["pos"][0], "sfx stop", diags, file, line_no)
				return Instruction.new(Instruction.Head.SFX_STOP, [stop_kv["pos"][0] if stop_kv["pos"].size() == 1 else "", stop_fade])
			# volume 子动作：仅 sfx（语音响度在制作期归一，voice 无此子动作——见 docs/未来开发设计.md 音频设计规则）
			if rest.size() > 0 and rest[0] == "volume":
				if key == "voice":
					return _fail(diags, file, line_no, "voice 不支持 volume 子动作（语音响度请在制作期归一；全局调节用语音总线）")
				var vol_kv := _parse_kv(rest.slice(1), ["fade"], diags, file, line_no)
				if vol_kv["pos"].size() < 2:
					return _fail(diags, file, line_no, "sfx volume 需要 <引用> <0~1> 两个位置参数")
				if vol_kv["pos"].size() > 2:
					return _fail(diags, file, line_no, "sfx volume 只接受两个位置参数（引用 音量），多余: " + " ".join(vol_kv["pos"].slice(2)))
				if not _check_volume(vol_kv["pos"][1], "sfx volume", diags, file, line_no):
					return null
				_warn_unknown_ref(known_refs, "audio", vol_kv["pos"][0], "sfx volume", diags, file, line_no)
				var sfx_vol_fade: String = vol_kv["kv"].get("fade", "0.3")
				if not _check_float(sfx_vol_fade, "sfx volume fade", diags, file, line_no):
					return null
				return Instruction.new(Instruction.Head.SFX_VOLUME, [vol_kv["pos"][0], vol_kv["pos"][1], sfx_vol_fade])
			var kv := _parse_kv(rest, ["from", "volume", "loop"] if key == "sfx" else ["from", "volume"], diags, file, line_no)
			if kv["pos"].is_empty():
				return _fail(diags, file, line_no, key + " 缺少音频引用名")
			if kv["pos"].size() > 1:
				return _fail(diags, file, line_no, key + " 只接受一个位置参数（引用名），多余: " + " ".join(kv["pos"].slice(1)))
			_warn_unknown_ref(known_refs, "audio", kv["pos"][0], key, diags, file, line_no)
			var from_str: String = kv["kv"].get("from", "0")
			var volume_str: String = kv["kv"].get("volume", "1.0")
			if not _check_float(from_str, key + " from", diags, file, line_no):
				return null
			if not _check_volume(volume_str, key + " volume", diags, file, line_no):
				return null
			if key == "sfx":
				var loop_str: String = kv["kv"].get("loop", "false")
				if not _check_bool(loop_str, "sfx loop", diags, file, line_no):
					return null
				return Instruction.new(Instruction.Head.SFX_PLAY, [kv["pos"][0], from_str, volume_str, loop_str])
			return Instruction.new(Instruction.Head.VOICE_PLAY, [kv["pos"][0], from_str, volume_str])
		"char":
			return _parse_char(rest, diags, file, line_no, char_max, known_refs)
		"var":
			return _parse_var(rest, diags, file, line_no)
		"jump":
			if rest.is_empty():
				return _fail(diags, file, line_no, "jump 缺少目标剧本名")
			if rest[0] == "main_menu":
				return Instruction.new(Instruction.Head.JUMP_MAIN_MENU)
			_warn_unknown_script(known_scripts, rest[0], "jump", diags, file, line_no)
			return Instruction.new(Instruction.Head.JUMP_SCRIPT, [rest[0]])
		"begin":
			if rest.is_empty():
				return _fail(diags, file, line_no, "begin 缺少剧本名")
			_warn_unknown_script(known_scripts, rest[0], "begin", diags, file, line_no)
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


## jump/begin 目标跨文件校验：目标不在编译目录则警告（模组 PCK 可提供目标剧本，故不报错）
static func _warn_unknown_script(known_scripts: Array[String], target: String, cmd: String, diags: Array[Dictionary], file: String, line_no: int) -> void:
	if known_scripts.is_empty() or known_scripts.has(target):
		return
	_diagnose_static(diags, file, line_no, "warning",
		"%s 目标剧本不在编译目录中: %s（若由模组提供可忽略）" % [cmd, target])


## 资源引用编译期校验：known_refs 非空时对照 index.json 登记表。
## 仅警告不报错——模组 PCK 可提供登记表之外的资源（与 jump/begin 目标校验同口径）。
## 域未注入（如 Renderer 锚点解析只传空表）时不校验。
static func _warn_unknown_ref(known_refs: Dictionary, domain: String, ref: String, cmd: String, diags: Array[Dictionary], file: String, line_no: int) -> void:
	if ref.is_empty() or not known_refs.has(domain):
		return
	if (known_refs[domain] as Dictionary).has(ref):
		return
	_diagnose_static(diags, file, line_no, "warning",
		"%s 引用的资源未在登记表（index.json）中: %s（域 %s；若由模组提供可忽略）" % [cmd, ref, domain])


static func _fail(diags: Array[Dictionary], file: String, line_no: int, msg: String) -> Instruction:
	_diagnose_static(diags, file, line_no, "error", msg)
	return null


## 数值参数校验（保留字劫持防护的收尾：旁白误入指令时参数必然非法）
static func _check_float(value: String, name: String, diags: Array[Dictionary], file: String, line_no: int) -> bool:
	if value.is_valid_float():
		return true
	_diagnose_static(diags, file, line_no, "error", "%s 参数必须是数字: %s（若这是对话文本，请在行首加 \\ 转义）" % [name, value])
	return false


## 音量参数校验：线性 0~1（与设置界面滑条同口径）
static func _check_volume(value: String, name: String, diags: Array[Dictionary], file: String, line_no: int) -> bool:
	if value.is_valid_float() and value.to_float() >= 0.0 and value.to_float() <= 1.0:
		return true
	_diagnose_static(diags, file, line_no, "error", "%s 参数必须是 0~1 的数字: %s" % [name, value])
	return false


## 布尔参数校验（与 Instruction._arg_bool 同口径；拼写错误不得静默落为 false）
static func _check_bool(value: String, name: String, diags: Array[Dictionary], file: String, line_no: int) -> bool:
	if value.to_lower() in ["true", "false", "1", "0", "on", "off"]:
		return true
	_diagnose_static(diags, file, line_no, "error", "%s 参数必须是布尔值（true/false/1/0/on/off）: %s" % [name, value])
	return false


## 键值参数解析：positional 进 pos，key:value 进 kv；未知键报警告
static func _parse_kv(args: Array[String], known_keys: Array, diags: Array[Dictionary] = [], file: String = "", line_no: int = 0) -> Dictionary:
	var pos: Array[String] = []
	var kv: Dictionary = {}
	for a in args:
		var colon := a.find(":")
		# res:// user:// 等路径不算键值对（冒号后跟 //）
		if colon > 0 and a.substr(0, colon).is_valid_identifier() and not a.substr(colon + 1).begins_with("//"):
			var k := a.substr(0, colon)
			var v := a.substr(colon + 1)
			if k in known_keys:
				kv[k] = v
			else:
				_diagnose_static(diags, file, line_no, "warning", "未知参数键: " + k)
		else:
			pos.append(a)
	return {"pos": pos, "kv": kv}


static func _parse_char(rest: Array[String], diags: Array[Dictionary], file: String, line_no: int, char_max: int = -1, known_refs: Dictionary = {}) -> Instruction:
	if rest.size() < 2:
		return _fail(diags, file, line_no, "char 缺少实例索引或子动作（setup/show/hide/move/texture/wait）")
	if not rest[0].is_valid_int():
		return _fail(diags, file, line_no, "char 实例索引必须是整数: " + rest[0])
	var idx := rest[0]
	# 编译期越界检查（上限 = config.json 的 character.max；char_max < 0 表示不校验）
	if char_max >= 0 and (idx.to_int() < 0 or idx.to_int() >= char_max):
		return _fail(diags, file, line_no, "char 实例索引越界: %s（上限 character.max = %d）" % [idx, char_max])
	var sub := rest[1]
	var tail := rest.slice(2)

	match sub:
		"setup":
			if tail.size() < 2:
				return _fail(diags, file, line_no, "char setup 需要 <立绘> <x,y>（逗号后无空格）")
			_warn_unknown_ref(known_refs, "texture", tail[0], "char setup", diags, file, line_no)
			var xy := _parse_xy(tail[1], diags, file, line_no)
			if xy.is_empty():
				return null
			return Instruction.new(Instruction.Head.CHAR_SETUP, [idx, tail[0], xy[0], xy[1]])
		"show", "hide":
			var kv := _parse_kv(tail, ["time", "wait"], diags, file, line_no)
			var time_str: String = kv["kv"].get("time", "1.0")
			var wait_str: String = kv["kv"].get("wait", "false")
			if not _check_float(time_str, "char " + sub + " time", diags, file, line_no):
				return null
			if not _check_bool(wait_str, "char " + sub + " wait", diags, file, line_no):
				return null
			var head := Instruction.Head.CHAR_SHOW_FADE if sub == "show" else Instruction.Head.CHAR_HIDE_FADE
			return Instruction.new(head, [idx, time_str, wait_str])
		"move":
			var kv := _parse_kv(tail, ["time", "wait"], diags, file, line_no)
			if kv["pos"].is_empty():
				return _fail(diags, file, line_no, "char move 缺少目标坐标 <x,y>（逗号后无空格）")
			var xy := _parse_xy(kv["pos"][0], diags, file, line_no)
			if xy.is_empty():
				return null
			var move_time: String = kv["kv"].get("time", "1.0")
			var move_wait: String = kv["kv"].get("wait", "false")
			if not _check_float(move_time, "char move time", diags, file, line_no):
				return null
			if not _check_bool(move_wait, "char move wait", diags, file, line_no):
				return null
			return Instruction.new(Instruction.Head.CHAR_MOVE_TO, [idx, xy[0], xy[1], move_time, move_wait])
		"texture":
			if tail.is_empty():
				return _fail(diags, file, line_no, "char texture 缺少立绘引用名")
			_warn_unknown_ref(known_refs, "texture", tail[0], "char texture", diags, file, line_no)
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

	# 变量名必须合法，否则永远无法被 {var} 插值读取（渲染器按 is_valid_identifier 判定）
	if not key.is_valid_identifier():
		return _fail(diags, file, line_no, "var 变量名必须是合法标识符（字母/下划线开头）: " + key)
	# 条件保留字：变量取这名后在条件表达式里会被解析为逻辑运算符
	if key in ["and", "or", "not"]:
		return _fail(diags, file, line_no, "var 变量名不得为条件保留字（and/or/not）: " + key)

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
	# 右值必须是数字或变量名（否则运行时会按未定义变量静默取 0）
	if not rest[2].is_valid_float() and not rest[2].is_valid_identifier():
		return _fail(diags, file, line_no, "var 右值必须是数字或变量名: " + rest[2])
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
			var free_str: String = kv["kv"].get("free", "true")
			if not _check_bool(free_str, "scene unmount free", diags, file, line_no):
				return null
			return Instruction.new(Instruction.Head.SCENE_UNMOUNT, [
				kv["pos"][0], kv["pos"][1],
				kv["kv"].get("time", "0"), kv["kv"].get("anim", "fade"), free_str,
			])
	return _fail(diags, file, line_no, "未知 scene 子动作: " + sub)


static func _parse_trans(rest: Array[String], diags: Array[Dictionary], file: String, line_no: int) -> Instruction:
	if rest.is_empty():
		return _fail(diags, file, line_no, "trans 缺少方向（in/out）")
	var sub := rest[0]
	var kv := _parse_kv(rest.slice(1), ["time", "anim", "wait"], diags, file, line_no)
	var wait_str: String = kv["kv"].get("wait", "true")
	if not _check_bool(wait_str, "trans wait", diags, file, line_no):
		return null
	match sub:
		"in":
			return Instruction.new(Instruction.Head.TRANSITION_IN, [
				kv["kv"].get("time", "1.0"), kv["kv"].get("anim", "fade_in"), wait_str,
			])
		"out":
			return Instruction.new(Instruction.Head.TRANSITION_OUT, [
				kv["kv"].get("time", "1.0"), kv["kv"].get("anim", "fade_out"), wait_str,
			])
	return _fail(diags, file, line_no, "未知 trans 方向: " + sub)


# --- 选项与条件 ---

## 选项组成员索引登记进 frame["members"]，供 _close_block 回填组结构（is_head/body_start/next_option/group_end）
static func _emit_option(text: String, seq: Array[GalEventItem], diags: Array[Dictionary], file: String, line_no: int, frame: Dictionary) -> void:
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

	var tokens: Array = []
	if not cond.is_empty():
		var parsed: Variant = _parse_condition_expr(cond, diags, file, line_no)
		if parsed == null:
			return
		tokens = parsed
	var ins := Instruction.new(Instruction.Head.OPTION, [option_text])
	ins.params[1] = tokens
	(frame["members"] as Array).append(seq.size())
	seq.append(ins)


static func _emit_condition_head(kind: LineKind, text: String, seq: Array[GalEventItem], diags: Array[Dictionary], file: String, line_no: int) -> void:
	if kind == LineKind.ELSE_HEAD:
		seq.append(Instruction.new(Instruction.Head.ELSE))
		return
	var key_word := "if" if kind == LineKind.IF_HEAD else "elif"
	var cond := _strip_inline_comment(text.substr(key_word.length()).strip_edges())
	var tokens: Variant = _parse_condition_expr(cond, diags, file, line_no)
	if tokens == null:
		return
	var ins := Instruction.new(Instruction.Head.IF if kind == LineKind.IF_HEAD else Instruction.Head.ELSE_IF)
	ins.params[0] = tokens
	seq.append(ins)


## 行内注释截断（引号外 //）；选项/条件行专用，指令行由 _split_cli_args 处理
static func _strip_inline_comment(text: String) -> String:
	var in_quote := false
	var i := 0
	while i < text.length():
		var c := text[i]
		if c == '"':
			in_quote = !in_quote
		elif not in_quote and c == "/" and i + 1 < text.length() and text[i + 1] == "/" \
			and (i == 0 or text[i - 1] != ":"):
			return text.substr(0, i).strip_edges()
		i += 1
	return text


## 条件表达式 → 后缀记号流（Instruction.CondTag）。
## 文法（优先级 或 < 与 < 非 < 比较 < 原子）：
##   or   := and ("or" and)*
##   and  := not ("and" not)*
##   not  := "not" not | "(" or ")" | comparison
##   comparison := 操作数 比较符 操作数 | 裸变量（真值口径：!= 0）
## 返回 Array；失败返回 null（已记录诊断）。操作数仅为变量名或数字字面量（无算术运算）
static func _parse_condition_expr(text: String, diags: Array[Dictionary], file: String, line_no: int) -> Variant:
	var tokens: Variant = _tokenize_condition(text, diags, file, line_no)
	if tokens == null:
		return null
	var p := {"t": tokens, "i": 0, "diags": diags, "file": file, "line": line_no}
	var out: Variant = _cond_or(p)
	if out == null:
		return null
	if p["i"] != (tokens as Array).size():
		_cond_err(p, "条件表达式尾部有多余内容（缺少 and/or 连接？）")
		return null
	return out


## 条件词法：数字/变量/比较符/括号/and/or/not。失败返回 null（已记录诊断）
static func _tokenize_condition(text: String, diags: Array[Dictionary], file: String, line_no: int) -> Variant:
	const STOP := " \t()<>=!"
	var tokens: Array = []
	var i := 0
	while i < text.length():
		var c := text[i]
		if c == " " or c == "\t":
			i += 1
		elif c == "(":
			tokens.append(["lp", ""])
			i += 1
		elif c == ")":
			tokens.append(["rp", ""])
			i += 1
		elif i + 1 < text.length() and text.substr(i, 2) in ["==", "!=", ">=", "<="]:
			tokens.append(["cmp", text.substr(i, 2)])
			i += 2
		elif c == ">" or c == "<":
			tokens.append(["cmp", c])
			i += 1
		elif c == "=" or c == "!":
			_diagnose_static(diags, file, line_no, "error",
				"条件中无法识别的符号: '%s'（等值比较是 ==，不等是 !=）" % (text.substr(i, 2).strip_edges()))
			return null
		else:
			var j := i
			while j < text.length() and not STOP.contains(text[j]):
				j += 1
			var word := text.substr(i, j - i)
			if word in ["and", "or", "not"]:
				tokens.append([word, ""])
			elif word.is_valid_float():
				tokens.append(["num", word])
			elif word.is_valid_identifier():
				tokens.append(["var", word])
			else:
				_diagnose_static(diags, file, line_no, "error", "条件中无法识别的记号: " + word)
				return null
			i = j
	return tokens


static func _cond_peek_token(p: Dictionary) -> Variant:
	var tokens: Array = p["t"]
	if p["i"] >= tokens.size():
		return null
	return tokens[p["i"]]


static func _cond_peek(p: Dictionary) -> String:
	var t: Variant = _cond_peek_token(p)
	return "" if t == null else t[0]


static func _cond_err(p: Dictionary, msg: String) -> void:
	_diagnose_static(p["diags"], p["file"], p["line"], "error", msg)


static func _cond_or(p: Dictionary) -> Variant:
	var left: Variant = _cond_and(p)
	if left == null:
		return null
	while _cond_peek(p) == "or":
		p["i"] += 1
		var right: Variant = _cond_and(p)
		if right == null:
			_cond_err(p, "or 后缺少条件")
			return null
		left = (left as Array) + (right as Array) + [[Instruction.CondTag.OR]]
	return left


static func _cond_and(p: Dictionary) -> Variant:
	var left: Variant = _cond_not(p)
	if left == null:
		return null
	while _cond_peek(p) == "and":
		p["i"] += 1
		var right: Variant = _cond_not(p)
		if right == null:
			_cond_err(p, "and 后缺少条件")
			return null
		left = (left as Array) + (right as Array) + [[Instruction.CondTag.AND]]
	return left


static func _cond_not(p: Dictionary) -> Variant:
	if _cond_peek(p) == "not":
		p["i"] += 1
		var inner: Variant = _cond_not(p)
		if inner == null:
			_cond_err(p, "not 后缺少条件")
			return null
		return (inner as Array) + [[Instruction.CondTag.NOT]]
	return _cond_primary(p)


static func _cond_primary(p: Dictionary) -> Variant:
	var t: Variant = _cond_peek_token(p)
	if t == null:
		_cond_err(p, "条件表达式不完整或缺失")
		return null
	match t[0]:
		"lp":
			p["i"] += 1
			var inner: Variant = _cond_or(p)
			if inner == null:
				return null
			if _cond_peek(p) != "rp":
				_cond_err(p, "括号不配对：缺少 )")
				return null
			p["i"] += 1
			return inner
		"var", "num":
			p["i"] += 1
			if _cond_peek(p) == "cmp":
				# 比较式：左值必须是变量名（字面量左值会被运行时按未定义变量静默按 0 比较）
				if t[0] == "num":
					_cond_err(p, "条件比较式左值必须是变量名: " + t[1])
					return null
				var op: String = _cond_peek_token(p)[1]
				p["i"] += 1
				var rhs: Variant = _cond_peek_token(p)
				if rhs == null or (rhs[0] != "var" and rhs[0] != "num"):
					_cond_err(p, "比较符 %s 后缺少操作数（数字或变量名）" % op)
					return null
				p["i"] += 1
				return [_cond_push(t), _cond_push(rhs), [Instruction.CondTag.CMP, op]]
			# 裸变量真值（裸数字无意义，拒掉）
			if t[0] == "num":
				_cond_err(p, "条件原子必须是变量名或比较式，不能是裸数字: " + t[1])
				return null
			return [_cond_push(t)]
		_:
			_cond_err(p, "此处缺少变量名或比较式: " + t[0])
			return null


## 操作数记号 → 压栈记号
static func _cond_push(t: Array) -> Array:
	if t[0] == "num":
		return [Instruction.CondTag.PUSH_NUM, t[1].to_float()]
	return [Instruction.CondTag.PUSH_VAR, t[1]]


## 条件结构目标回填（编译期后处理）：分支跳转目标直接写入指令参数，
## 运行时按参数跳转（无跳转表、无链式扫描）。结构配对已由行解析保证，此处仅防御性校验。
## 参数契约：IF [tokens, next]；ELSE_IF [tokens, next, end]；ELSE [end]；END_IF []
static func _resolve_condition_targets(seq: Array[GalEventItem], diags: Array[Dictionary], file: String) -> void:
	var heads: Array[int] = []      # 未闭合分支头索引栈（每层链的当前分支头）
	var chains: Array[Array] = []   # 每层链的全部分支头索引（end_target 回填用）
	for i in range(seq.size()):
		var item := seq[i]
		if not (item is Instruction):
			continue
		match (item as Instruction).head:
			Instruction.Head.IF:
				heads.append(i)
				chains.append([i])
			Instruction.Head.ELSE_IF, Instruction.Head.ELSE:
				if heads.is_empty():
					_diagnose_static(diags, file, 0, "error", "内部错误：elif/else 无配对 if")
					continue
				(seq[heads[-1]] as Instruction).params[1] = i  # 上一分支假 → 跳到本分支头
				heads[-1] = i
				chains[-1].append(i)
			Instruction.Head.END_IF:
				if heads.is_empty():
					_diagnose_static(diags, file, 0, "error", "内部错误：endif 无配对 if")
					continue
				var last := seq[heads.pop_back()] as Instruction
				if last.head != Instruction.Head.ELSE:  # ELSE 无 next 槽位（无条件分支）
					last.params[1] = i  # 末分支假 → END_IF
				for head_idx in chains.pop_back():
					var h := seq[head_idx] as Instruction
					if h.head == Instruction.Head.ELSE_IF:
						h.params[2] = i  # end_target
					elif h.head == Instruction.Head.ELSE:
						h.params[0] = i  # end_target
	if not heads.is_empty():
		_diagnose_static(diags, file, 0, "error", "内部错误：条件结构未闭合")


# --- 对话行 ---

static func _emit_dialogue(text: String, seq: Array[GalEventItem], diags: Array[Dictionary], file: String, line_no: int, char_max: int = -1, known_refs: Dictionary = {}) -> void:
	_validate_anchors(text, diags, file, line_no, char_max, known_refs)

	var speaker := ""
	var content := text
	var colon_index := text.find(":")
	if colon_index == -1:
		colon_index = text.find("：")
	if colon_index != -1:
		speaker = text.substr(0, colon_index).strip_edges()
		content = text.substr(colon_index + 1).strip_edges()

	seq.append(DialogueItem.new(speaker, content))


## 锚点校验（不剥离）：白名单指令名 + 定界符判定，禁止流程指令；char 实例索引随 char_max、资源引用随 known_refs 一并校验
static func _validate_anchors(text: String, diags: Array[Dictionary], file: String, line_no: int, char_max: int = -1, known_refs: Dictionary = {}) -> void:
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
				# 借解析器校验锚点指令合法性（流程指令不在白名单，天然拒绝；锚点不会出现 jump/begin，目标校验传空跳过）
				var anchor_diags: Array[Dictionary] = []
				parse_instruction_line(inner, anchor_diags, file, line_no, [], char_max, known_refs)
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

		# 行内注释（但 res:// user:// 等路径的 // 前是冒号，不截断）
		if not in_quote and c == "/" and i + 1 < length and text[i + 1] == "/" \
			and (i == 0 or text[i - 1] != ":"):
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
