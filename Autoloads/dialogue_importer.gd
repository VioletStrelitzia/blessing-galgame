class_name DialogueImporter extends Node
const LOG_TAG := "Importer"


var check: bool = true
var read_dir: String = "res://scripts"
var save_dir: String = "res://GalSs"
var hash_file_path: String = save_dir.path_join(".hash")

var saved_hash: Dictionary = {}
var need_update: bool = false

const CHUNK_SIZE = 1024

# 指令映射表
const INSTRUCTION_MAP: Dictionary[String, Instruction.Head] = {
	# 音频
	"music play": 		Instruction.Head.MUSIC_PLAY,
	"music pause": 		Instruction.Head.MUSIC_PAUSE,
	"music resume":		Instruction.Head.MUSIC_RESUME,
	"music stop": 		Instruction.Head.MUSIC_STOP,
	"voice play": 		Instruction.Head.VOICE_PLAY,
	"voice event":		Instruction.Head.VOICE_EVENT,
	"sfx play": 			Instruction.Head.SFX_PLAY,
	
	# 背景
	"bg set":			Instruction.Head.SET_BACKGROUND,
	
	# 角色
	"character":			Instruction.Head.CHARACTER,
	"char setup":		Instruction.Head.CHAR_SETUP,
	"char show":			Instruction.Head.CHAR_SHOW_FADE,
	"char hide":			Instruction.Head.CHAR_HIDE_FADE,
	"char move":			Instruction.Head.CHAR_MOVE_TO,
	"char wait":			Instruction.Head.CHAR_WAIT,
	"char texture":		Instruction.Head.CHAR_CHANGE_TEXTURE,
	"char play":			Instruction.Head.CHAR_PLAY,

	# 选项
	"option":			Instruction.Head.OPTION,
	"option end":		Instruction.Head.OPTION_END,

	# 变量
	"var set":			Instruction.Head.VAR_SET,
	"var add":			Instruction.Head.VAR_ADD,
	"var sub":			Instruction.Head.VAR_SUB,
	"var mul":			Instruction.Head.VAR_MUL,
	"var div":			Instruction.Head.VAR_DIV,
	"var random":		Instruction.Head.VAR_RANDOM,
	
	# 逻辑
	"if":				Instruction.Head.IF,
	"elif":				Instruction.Head.ELSE_IF,
	"else":				Instruction.Head.ELSE,
	"endif":				Instruction.Head.END_IF,

	# 跳转
	"begin script": 		Instruction.Head.SET_BEGIN_SCRIPT,
	"jump": 				Instruction.Head.JUMP_SCRIPT,
	"jump main_menu": 	Instruction.Head.JUMP_MAIN_MENU,

	# 场景
	"scene mount":		Instruction.Head.SCENE_MOUNT,
	"scene unmount":		Instruction.Head.SCENE_UNMOUNT,
	
	# 转场
	"trans in":			Instruction.Head.TRANSITION_IN,
	"trans out":			Instruction.Head.TRANSITION_OUT,
}

signal res_update_load_finished

static var _regex_dialogue: RegEx = RegEx.new()

func _init() -> void:
	_regex_dialogue.compile("^(?:(.*?):)?\\s*(.*)$")

func _ready() -> void:
	if DirAccess.dir_exists_absolute(save_dir):
		Utils.open_dir(save_dir)
		saved_hash = Utils.load_json(hash_file_path)
	import_dialogues(read_dir)
	if need_update:
		Utils.save_json(hash_file_path, saved_hash)
		GalLogger.info(LOG_TAG, "导入完成，已更新哈希值和资源列表")
	res_update_load_finished.emit()

func import_dialogues(path: String):
	var file_list := Utils.get_file_list(path, true, false)
	for file_path in file_list:
		import_dialogue(
			path.path_join(file_path),
			save_dir.path_join(file_path.get_basename().replace("/", "_").replace("\\", "_") + ".tres")
		)

func import_dialogue(text_path: String, output_path: String) -> void:
	var current_hash = calculate_text_hash(text_path)
	if current_hash.is_empty():
		GalLogger.error(LOG_TAG, "无法计算文本哈希")
		return
	
	var need_reimport = false
	if saved_hash.has(text_path) and saved_hash[text_path] == current_hash and FileAccess.file_exists(output_path):
		pass
	else:
		need_reimport = true
		saved_hash[text_path] = current_hash
		need_update = true
	
	if not need_reimport:
		GalLogger.debug(LOG_TAG, "资源无变化: " + text_path)
		return
	
	GalLogger.debug(LOG_TAG, "导入资源: " + text_path)
	
	var file = Utils.open_file(text_path, FileAccess.READ)
	var text = file.get_as_text()
	file.close()
	
	var dialogue_group = parse_dialogue_texts(text.split("\n"))
	
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

func parse_dialogue_texts(lines: PackedStringArray) -> GalEventItemSequence:
	var gal_event_item_sequence = GalEventItemSequence.new()
	var seq: Array[GalEventItem] = gal_event_item_sequence.seq
	
	for i in range(lines.size()):
		var line = lines[i]
		var item = parse_dialogue_text(line)
		if item:
			seq.append(item)
	
	return gal_event_item_sequence

static func parse_dialogue_text(line: String) -> GalEventItem:
	var text = line.strip_edges()
	
	# 忽略空行和注释
	if text.is_empty() or text.begins_with("//") or text.begins_with("#"):
		return null
	
	# 指令解析 (< 前序, > 后序)
	if text.begins_with("<") or text.begins_with(">"):
		var prefix = text[0]
		var is_post = (prefix == ">")
		
		# 提取内容并分词
		var cont = text.substr(1).strip_edges()
		var args = _split_cli_args(cont)
		
		if args.is_empty():
			return null
			
		var head: Instruction.Head
		var params_array: Array[String] = []
		var found_cmd: bool = false
		
		# 优先匹配双词指令
		if args.size() >= 2:
			var key_2w = args[0] + " " + args[1]
			if INSTRUCTION_MAP.has(key_2w):
				head = INSTRUCTION_MAP[key_2w]
				# 剩余部分作为参数
				if args.size() > 2:
					params_array = args.slice(2)
				found_cmd = true
		
		# 再尝试单词指令
		if not found_cmd:
			var key_1w = args[0]
			if INSTRUCTION_MAP.has(key_1w):
				head = INSTRUCTION_MAP[key_1w]
				# 剩余部分作为参数
				if args.size() > 1:
					params_array = args.slice(1)
				found_cmd = true
		
		if found_cmd:
			if is_post:
				return PostInstruction.new(head, params_array)
			else:
				return PrevInstruction.new(head, params_array)
		else:
			GalLogger.warn(LOG_TAG, "未定义指令: " + cont)
			return null

	# 3. 对话解析
	var speaker = ""
	var content = text
	
	var colon_index = text.find(":")
	if colon_index == -1:
		colon_index = text.find("：")
	
	if colon_index != -1:
		speaker = text.substr(0, colon_index).strip_edges()
		content = text.substr(colon_index + 1).strip_edges()
	
	return DialogueItem.new(speaker, content)

# --- CLI 分词器 ---
static func _split_cli_args(text: String) -> Array[String]:
	var args: Array[String] = []
	var current_arg := ""
	var in_quote := false
	var length := text.length()
	var i := 0
	
	while i < length:
		var c = text[i]
		
		# 注释检测
		if not in_quote and c == "/" and i + 1 < length and text[i+1] == "/":
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
