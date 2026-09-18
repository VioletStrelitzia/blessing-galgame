class_name Instruction extends GalEventItem

## BGalS v2 指令。参数在编译期由 DialogueImporter 按本表 spec 定型。
## 基类实例 = 独立指令（不绑定对话）；PrevInstruction/PostInstruction 为前/后指令。

enum Head {
	BLANK,  ## 反序列化占位，编译器不产生

	# [音频指令]
	MUSIC_PLAY,    			# music <path> [from:秒] [loop:bool] [fade:秒] [fade_in:秒] [fade_out:秒] [volume:0~1]
	MUSIC_PAUSE,    		# music pause
	MUSIC_RESUME,   		# music resume
	MUSIC_STOP,     		# music stop [fade:秒]
	VOICE_PLAY,     		# voice <path> [from:秒] [volume:0~1]
	SFX_PLAY,       		# sfx <path> [from:秒] [volume:0~1] [loop:bool]

	# [视觉与资源]
	SET_BACKGROUND, 		# bg <path> [time:秒]

	# [角色动画：直挂实例，入队异步执行]
	CHAR_SETUP,      		# char <idx> setup <path> <x,y>
	CHAR_SHOW_FADE,  		# char <idx> show [time:秒] [wait:bool]
	CHAR_HIDE_FADE,  		# char <idx> hide [time:秒] [wait:bool]
	CHAR_MOVE_TO,    		# char <idx> move <x,y> [time:秒] [wait:bool]
	CHAR_WAIT,       		# char <idx> wait <秒>（队列内等待，仅正秒）
	CHAR_CHANGE_TEXTURE,	# char <idx> texture <path>

	# [选择系统]
	OPTION,     			# * 文本 [if:条件]（tokens 空 = 恒真；组结构编译期回填：is_head/body_start/next_option/group_end）
	OPTION_END,     		# 编译期生成的选项组收尾

	# [变量操作]
	VAR_SET,    			# var <key> = <值|变量>
	VAR_ADD,    			# var <key> += <值|变量>
	VAR_SUB,    			# var <key> -= <值|变量>
	VAR_MUL,    			# var <key> *= <值|变量>
	VAR_DIV,    			# var <key> /= <值|变量>
	VAR_RANDOM, 			# var <key> = random <min> <max>

	# [逻辑流控制]（v2.3 起：条件为后缀记号流，分支跳转目标由编译期回填）
	IF,         			# if <条件>，参数 [tokens, next_target]
	ELSE_IF,    			# elif <条件>，参数 [tokens, next_target, end_target]
	ELSE,       			# else，参数 [end_target]
	END_IF,     			# 编译期生成的条件结构收尾

	# [脚本跳转]
	SET_BEGIN_SCRIPT, 		# begin <script_name>
	JUMP_SCRIPT,      		# jump <script_name>
	JUMP_MAIN_MENU,   		# jump main_menu（编译期从 JUMP_SCRIPT 特化）

	# [场景管理原子指令]
	SCENE_MOUNT,    		# scene mount <type> <name> <path> [time:秒] [anim:名]
	SCENE_UNMOUNT,  		# scene unmount <type> <name> [time:秒] [anim:名] [free:bool]
	TRANSITION_IN,  		# trans in [time:秒] [anim:名] [wait:bool]
	TRANSITION_OUT, 		# trans out [time:秒] [anim:名] [wait:bool]

	# [剧情等待]
	WAIT,       			# wait <秒>（SKIP/重放时短路）

	# [音频指令·v2.1 追加]（新增枚举一律尾部追加，勿重排——序列化按整数存储）
	VOICE_STOP, 			# voice stop [fade:秒]
	SFX_STOP,   			# sfx stop [引用] [fade:秒]（引用省略 = 停止全部）
	MUSIC_VOLUME,   		# music volume <0~1> [fade:秒]（调节在播音轨响度，不重启曲目）

	# [音频指令·v2.2 追加]
	SFX_VOLUME, 			# sfx volume <引用> <0~1> [fade:秒]（调节在播音效响度，不中断播放）
}

## 条件记号标签：条件表达式经编译期递归下降解析为后缀记号流（token = [tag, payload]），
## 运行时栈机求值（StoryManager._eval_condition）。序列化按整数存储，新增一律尾部追加。
enum CondTag {
	PUSH_NUM,  ## [PUSH_NUM, float] 压入数字字面量
	PUSH_VAR,  ## [PUSH_VAR, String] 压入变量值（未定义按 0.0）
	CMP,       ## [CMP, op] 弹出 lhs/rhs 比较，压入 bool
	NOT,       ## [NOT, 0] 弹出一值取真值后取反
	AND,       ## [AND, 0] 弹出两值取真值逻辑与
	OR,        ## [OR, 0] 弹出两值取真值逻辑或
}

@export var head: Head
@export var params: Array[Variant] = []

## 参数形状表：head → [[参数名, 类型, 默认值, 语义角色]]。
## 参数在编译期由 DialogueImporter 产出即定型（类型化，不经字符串回环）；
## 本表提供默认值补齐、类型校验与 from_strings 转型（测试辅助路径）。
## 语义角色（role）为开放 StringName，不写死：编译期校验与工具链 schema 导出共用；
## 未知角色仅作元数据，不参与校验。内建角色：
##   "audio"/"texture" —— index.json 登记表引用；"script" —— 剧本名（编译目录）；
##   "res_path" —— res:// 直路径；"scene_type" —— 场景类型（world2d/ui）
enum _T { STR, FLOAT, INT, BOOL, ARR }

const _SPEC: Dictionary = {
	# [音频指令]
	Head.MUSIC_PLAY: [["path", _T.STR, "", "audio"], ["from", _T.FLOAT, 0.0, ""], ["loop", _T.BOOL, true, ""], ["fade_in", _T.FLOAT, 1.0, ""], ["fade_out", _T.FLOAT, 1.0, ""], ["volume", _T.FLOAT, 1.0, ""]],
	Head.MUSIC_STOP: [["fade", _T.FLOAT, 1.0, ""]],
	Head.VOICE_PLAY: [["path", _T.STR, "", "audio"], ["from", _T.FLOAT, 0.0, ""], ["volume", _T.FLOAT, 1.0, ""]],
	Head.VOICE_STOP: [["fade", _T.FLOAT, 0.1, ""]],
	Head.SFX_PLAY: [["path", _T.STR, "", "audio"], ["from", _T.FLOAT, 0.0, ""], ["volume", _T.FLOAT, 1.0, ""], ["loop", _T.BOOL, false, ""]],
	Head.SFX_STOP: [["ref", _T.STR, "", "audio"], ["fade", _T.FLOAT, 0.3, ""]],  # ref 为空 = 停止全部 SFX
	Head.SFX_VOLUME: [["ref", _T.STR, "", "audio"], ["volume", _T.FLOAT, 1.0, ""], ["fade", _T.FLOAT, 0.3, ""]],
	Head.MUSIC_VOLUME: [["volume", _T.FLOAT, 1.0, ""], ["fade", _T.FLOAT, 0.5, ""]],

	# [视觉与资源]
	Head.SET_BACKGROUND: [["path", _T.STR, "", "texture"], ["time", _T.FLOAT, 0.0, ""]],

	# [角色动画]
	Head.CHAR_SETUP: [["char_index", _T.INT, 0, ""], ["path", _T.STR, "", "texture"], ["x", _T.FLOAT, 0.0, ""], ["y", _T.FLOAT, 0.0, ""]],
	Head.CHAR_SHOW_FADE: [["char_index", _T.INT, 0, ""], ["duration", _T.FLOAT, 1.0, ""], ["wait", _T.BOOL, false, ""]],
	Head.CHAR_HIDE_FADE: [["char_index", _T.INT, 0, ""], ["duration", _T.FLOAT, 1.0, ""], ["wait", _T.BOOL, false, ""]],
	Head.CHAR_MOVE_TO: [["char_index", _T.INT, 0, ""], ["x", _T.FLOAT, 0.0, ""], ["y", _T.FLOAT, 0.0, ""], ["duration", _T.FLOAT, 1.0, ""], ["wait", _T.BOOL, false, ""]],
	Head.CHAR_WAIT: [["char_index", _T.INT, 0, ""], ["duration", _T.FLOAT, 0.0, ""]],
	Head.CHAR_CHANGE_TEXTURE: [["char_index", _T.INT, 0, ""], ["path", _T.STR, "", "texture"]],

	# [选择系统]（tokens 条件记号流；is_head/body_start/next_option/group_end 编译期回填）
	Head.OPTION: [["text", _T.STR, "", ""], ["tokens", _T.ARR, [], ""], ["is_head", _T.BOOL, false, ""], ["body_start", _T.INT, 0, ""], ["next_option", _T.INT, -1, ""], ["group_end", _T.INT, 0, ""]],

	# [变量操作]（value 为字符串：数字字面量或变量名，运行时解析）
	Head.VAR_SET: [["key", _T.STR, "", ""], ["value", _T.STR, "", ""]],
	Head.VAR_ADD: [["key", _T.STR, "", ""], ["value", _T.STR, "", ""]],
	Head.VAR_SUB: [["key", _T.STR, "", ""], ["value", _T.STR, "", ""]],
	Head.VAR_MUL: [["key", _T.STR, "", ""], ["value", _T.STR, "", ""]],
	Head.VAR_DIV: [["key", _T.STR, "", ""], ["value", _T.STR, "", ""]],
	Head.VAR_RANDOM: [["key", _T.STR, "", ""], ["min", _T.FLOAT, 0.0, ""], ["max", _T.FLOAT, 1.0, ""]],

	# [逻辑流控制]（tokens 与跳转目标由编译期回填）
	Head.IF: [["tokens", _T.ARR, [], ""], ["next_target", _T.INT, 0, ""]],
	Head.ELSE_IF: [["tokens", _T.ARR, [], ""], ["next_target", _T.INT, 0, ""], ["end_target", _T.INT, 0, ""]],
	Head.ELSE: [["end_target", _T.INT, 0, ""]],

	# [脚本跳转]
	Head.SET_BEGIN_SCRIPT: [["script_name", _T.STR, "", "script"]],
	Head.JUMP_SCRIPT: [["script_name", _T.STR, "", "script"]],

	# [场景管理原子指令]
	Head.SCENE_MOUNT: [["type", _T.STR, "world2d", "scene_type"], ["name", _T.STR, "default", ""], ["path", _T.STR, "", "res_path"], ["time", _T.FLOAT, 0.0, ""], ["anim", _T.STR, "fade", ""]],
	Head.SCENE_UNMOUNT: [["type", _T.STR, "world2d", "scene_type"], ["name", _T.STR, "default", ""], ["time", _T.FLOAT, 0.0, ""], ["anim", _T.STR, "fade", ""], ["free", _T.BOOL, true, ""]],
	Head.TRANSITION_IN: [["time", _T.FLOAT, 1.0, ""], ["anim", _T.STR, "fade_in", ""], ["wait", _T.BOOL, true, ""]],
	Head.TRANSITION_OUT: [["time", _T.FLOAT, 1.0, ""], ["anim", _T.STR, "fade_out", ""], ["wait", _T.BOOL, true, ""]],

	# [剧情等待]
	Head.WAIT: [["duration", _T.FLOAT, 0.0, ""]],
}


## 类型化构造：编译器产出即定型。缺省补默认值；超产/类型不符报错并保持默认（产物损毁护栏）
func _init(head_: Head = Head.BLANK, typed: Array = []) -> void:
	head = head_
	var spec: Array = _SPEC.get(head_, [])
	params = []
	for entry in spec:
		params.append((entry[2] as Array).duplicate() if entry[1] == _T.ARR else entry[2])
	for i in typed.size():
		if i >= spec.size():
			GalLogger.error("Instruction", "参数超产: %s 期望 %d 个，实际 %d 个" % [Head.keys()[head_], spec.size(), typed.size()])
			break
		if not _type_ok(typed[i], spec[i][1]):
			GalLogger.error("Instruction", "参数类型不符: %s 第 %d 位（期望 %s），保持默认值" % [Head.keys()[head_], i, _T.keys()[spec[i][1]]])
			continue
		params[i] = typed[i]


## 字符串参数构造（测试辅助路径）：按 spec 类型转型
static func from_strings(head_: Head, args: Array[String]) -> Instruction:
	return _from_strings_into(Instruction.new(), head_, args)


## 供子类（Prev/PostInstruction）复用的 from_strings
static func _from_strings_into(ins: Instruction, head_: Head, args: Array[String]) -> Instruction:
	ins.head = head_
	var spec: Array = _SPEC.get(head_, [])
	ins.params = []
	for entry in spec:
		ins.params.append((entry[2] as Array).duplicate() if entry[1] == _T.ARR else entry[2])
	for i in mini(args.size(), spec.size()):
		ins.params[i] = _convert_str(args[i], spec[i][1])
	return ins


static func _convert_str(s: String, t: _T) -> Variant:
	match t:
		_T.STR:
			return s
		_T.FLOAT:
			return s.to_float()
		_T.INT:
			return s.to_int()
		_T.BOOL:
			return s.to_lower() in ["true", "1", "on"]
		_T.ARR:
			return []
	return s


static func _type_ok(v: Variant, t: _T) -> bool:
	match t:
		_T.STR:
			return v is String
		_T.FLOAT:
			return v is float or v is int
		_T.INT:
			return v is int
		_T.BOOL:
			return v is bool
		_T.ARR:
			return v is Array
	return true


func _to_string() -> String:
	var head_name: String = Head.keys()[head]
	return "[Instruction] " + head_name + _format_params()


func _format_params() -> String:
	if params.is_empty():
		return ""

	var parts: Array[String] = []
	for param in params:
		if param is String:
			# 如果字符串包含空格，用引号包裹
			if param.contains(" "):
				parts.append("\"" + param + "\"")
			else:
				parts.append(param)
		elif param is bool:
			parts.append("true" if param else "false")
		else:
			parts.append(str(param))

	return " " + " ".join(parts)
