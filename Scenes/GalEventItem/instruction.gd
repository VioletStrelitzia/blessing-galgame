class_name Instruction extends GalEventItem

## BGalS v2 指令。参数在编译期由 DialogueImporter 按本表 spec 定型。
## 基类实例 = 独立指令（不绑定对话）；PrevInstruction/PostInstruction 为前/后指令。

enum Head {
	BLANK,  ## 反序列化占位，编译器不产生

	# [音频指令]
	MUSIC_PLAY,    			# music <path> [from:秒] [loop:bool] [fade:秒] [volume:0~1]
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
	OPTION,     			# * 文本 [if:条件]（条件三槽可为空）
	OPTION_END,     		# 编译期生成的选项组收尾

	# [变量操作]
	VAR_SET,    			# var <key> = <值|变量>
	VAR_ADD,    			# var <key> += <值|变量>
	VAR_SUB,    			# var <key> -= <值|变量>
	VAR_MUL,    			# var <key> *= <值|变量>
	VAR_DIV,    			# var <key> /= <值|变量>
	VAR_RANDOM, 			# var <key> = random <min> <max>

	# [逻辑流控制]
	IF,         			# if <左值> <比较符> <右值|变量>
	ELSE_IF,    			# elif <左值> <比较符> <右值|变量>
	ELSE,       			# else
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
}

@export var head: Head
@export var params: Array[Variant] = []

func _init(head_: Head = Head.BLANK, args: Array[String] = []) -> void:
	head = head_

	match head_:
		# 参数: [path: String, from: float, loop: bool, fade: float, volume: float]
		Head.MUSIC_PLAY:
			params.append(_arg_str(args, 0, ""))
			params.append(_arg_float(args, 1, 0.0))
			params.append(_arg_bool(args, 2, true))
			params.append(_arg_float(args, 3, 1.0))
			params.append(_arg_float(args, 4, 1.0))

		# 参数: [fade: float]
		Head.MUSIC_STOP:
			params.append(_arg_float(args, 0, 1.0))

		# 无参数音频指令
		Head.MUSIC_PAUSE, \
		Head.MUSIC_RESUME:
			pass

		# 参数: [path: String, from: float, volume: float]
		Head.VOICE_PLAY:
			params.append(_arg_str(args, 0, ""))
			params.append(_arg_float(args, 1, 0.0))
			params.append(_arg_float(args, 2, 1.0))

		# 参数: [path: String, from: float, volume: float, loop: bool]
		Head.SFX_PLAY:
			params.append(_arg_str(args, 0, ""))
			params.append(_arg_float(args, 1, 0.0))
			params.append(_arg_float(args, 2, 1.0))
			params.append(_arg_bool(args, 3, false))

		# 视觉与资源
		# 参数: [path: String, time: float]
		Head.SET_BACKGROUND:
			params.append(_arg_str(args, 0, ""))
			params.append(_arg_float(args, 1, 0.0))

		# 参数: [text/script_name: String]
		Head.SET_BEGIN_SCRIPT, \
		Head.JUMP_SCRIPT:
			params.append(_arg_str(args, 0, ""))

		# 参数: [char_index: int, path: String]
		Head.CHAR_CHANGE_TEXTURE:
			params.append(_arg_int(args, 0, 0))
			params.append(_arg_str(args, 1, ""))

		# 选项：文本 + 可选条件三槽（key/op/value，无条件时全空）
		# 参数: [text: String, cond_key: String, cond_op: String, cond_value: String]
		Head.OPTION:
			params.append(_arg_str(args, 0, ""))
			params.append(_arg_str(args, 1, ""))
			params.append(_arg_str(args, 2, ""))
			params.append(_arg_str(args, 3, ""))

		# 无参数指令
		Head.JUMP_MAIN_MENU, \
		Head.OPTION_END:
			pass

		# 角色动画（实例索引进入各指令参数）
		# 参数: [char_index: int, path: String, x: float, y: float]
		Head.CHAR_SETUP:
			params.append(_arg_int(args, 0, 0))
			params.append(_arg_str(args, 1, ""))
			params.append(_arg_float(args, 2, 0.0))
			params.append(_arg_float(args, 3, 0.0))

		# 参数: [char_index: int, duration: float, wait: bool]
		Head.CHAR_SHOW_FADE, \
		Head.CHAR_HIDE_FADE:
			params.append(_arg_int(args, 0, 0))
			params.append(_arg_float(args, 1, 1.0))
			params.append(_arg_bool(args, 2, false))

		# 参数: [char_index: int, x: float, y: float, duration: float, wait: bool]
		Head.CHAR_MOVE_TO:
			params.append(_arg_int(args, 0, 0))
			params.append(_arg_float(args, 1, 0.0))
			params.append(_arg_float(args, 2, 0.0))
			params.append(_arg_float(args, 3, 1.0))
			params.append(_arg_bool(args, 4, false))

		# 参数: [char_index: int, duration: float]
		Head.CHAR_WAIT:
			params.append(_arg_int(args, 0, 0))
			params.append(_arg_float(args, 1, 0.0))

		# 变量操作（value 为字符串：数字字面量或变量名，运行时解析）
		# 参数: [key: String, value: String]
		Head.VAR_SET, \
		Head.VAR_ADD, \
		Head.VAR_SUB, \
		Head.VAR_MUL, \
		Head.VAR_DIV:
			params.append(_arg_str(args, 0, ""))
			params.append(_arg_str(args, 1, ""))

		# 参数: [key: String, min: float, max: float]
		Head.VAR_RANDOM:
			params.append(_arg_str(args, 0, ""))
			params.append(_arg_float(args, 1, 0.0))
			params.append(_arg_float(args, 2, 1.0))

		# 逻辑流控制（value 为字符串：数字字面量或变量名，运行时解析）
		# 参数: [key: String, operator: String, value: String]
		Head.IF, \
		Head.ELSE_IF:
			params.append(_arg_str(args, 0, ""))
			params.append(_arg_str(args, 1, "=="))
			params.append(_arg_str(args, 2, ""))

		# 无参数逻辑指令
		Head.ELSE, \
		Head.END_IF:
			pass

		# 场景挂载
		# 语法: scene mount <type> <name> <path> [time:秒] [anim:名]
		Head.SCENE_MOUNT:
			params.append(_arg_str(args, 0, "world2d"))    # type
			params.append(_arg_str(args, 1, "default"))    # name
			params.append(_arg_str(args, 2, ""))           # path
			params.append(_arg_float(args, 3, 0.0))        # duration
			params.append(_arg_str(args, 4, "fade"))       # anim_name

		# 场景卸载
		# 语法: scene unmount <type> <name> [time:秒] [anim:名] [free:bool]
		Head.SCENE_UNMOUNT:
			params.append(_arg_str(args, 0, "world2d"))
			params.append(_arg_str(args, 1, "default"))
			params.append(_arg_float(args, 2, 0.0))        # duration
			params.append(_arg_str(args, 3, "fade"))       # anim_name
			params.append(_arg_bool(args, 4, true))        # free

		# 场景转场
		# 语法: trans in [time:秒] [anim:名] [wait:bool]
		Head.TRANSITION_IN:
			params.append(_arg_float(args, 0, 1.0))
			params.append(_arg_str(args, 1, "fade_in"))
			params.append(_arg_bool(args, 2, true))

		Head.TRANSITION_OUT:
			params.append(_arg_float(args, 0, 1.0))
			params.append(_arg_str(args, 1, "fade_out"))
			params.append(_arg_bool(args, 2, true))

		# 剧情等待
		# 参数: [duration: float]
		Head.WAIT:
			params.append(_arg_float(args, 0, 0.0))

		# 参数: [fade: float]
		Head.VOICE_STOP:
			params.append(_arg_float(args, 0, 0.1))

		# 参数: [ref: String, fade: float]（ref 为空 = 停止全部 SFX）
		Head.SFX_STOP:
			params.append(_arg_str(args, 0, ""))
			params.append(_arg_float(args, 1, 0.3))

		# 参数: [volume: float, fade: float]
		Head.MUSIC_VOLUME:
			params.append(_arg_float(args, 0, 1.0))
			params.append(_arg_float(args, 1, 0.5))


func _arg_str(args: Array[String], idx: int, default: String = "") -> String:
	return args[idx] if idx < args.size() else default


func _arg_int(args: Array[String], idx: int, default: int = 0) -> int:
	return args[idx].to_int() if idx < args.size() else default


func _arg_float(args: Array[String], idx: int, default: float = 0.0) -> float:
	return args[idx].to_float() if idx < args.size() else default


func _arg_bool(args: Array[String], idx: int, default: bool = false) -> bool:
	if idx >= args.size(): return default
	var s = args[idx].to_lower()
	return s == "true" or s == "1" or s == "on"


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
