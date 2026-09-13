class_name Instruction extends GalEventItem

enum Head {
	# 空白头
	BLANK,
	
	# [音频指令]
	MUSIC_PLAY,    			# < music play path vol loop
	MUSIC_PAUSE,    		# < music pause
	MUSIC_RESUME,   		# < music resume
	MUSIC_STOP,     		# < music stop
	VOICE_PLAY,     		# < voice play path offset
	SFX_PLAY,       		# < sfx play path offset
	
	# [视觉与资源]
	SET_BACKGROUND, 		# < bg set path
	
	# [语音事件]
	VOICE_EVENT,    		# < voice event time
	
	# [动画指令]
	CHARACTER,          	# < char begin char_index
	CHAR_SETUP,      		# < char setup path x y
	CHAR_SHOW_FADE,  		# < char show duration
	CHAR_HIDE_FADE,  		# < char hide duration
	CHAR_MOVE_TO,    		# < char move x y duration
	CHAR_WAIT,       		# < char wait duration
	CHAR_CHANGE_TEXTURE,	# < char texture path
	CHAR_PLAY,         		# < char play char_index (默认播放动画序列)
	
	# [选择系统]
	OPTION,     			# < choice text "Text" (或包含指令)
	OPTION_END,     		# < choice end
	
	# [变量操作]
	VAR_SET,    			# < var set key value
	VAR_ADD,    			# < var add key value
	VAR_SUB,    			# < var sub key value
	VAR_MUL,    			# < var mul key value
	VAR_DIV,    			# < var div key value
	VAR_RANDOM, 			# < var random key min max

	# [逻辑流控制]
	IF,         			# < if key operator value
	ELSE_IF,    			# < elif key operator value
	ELSE,       			# < else
	END_IF,     			# < endif

	# [脚本跳转]
	SET_BEGIN_SCRIPT, 		# < set begin script_name
	JUMP_SCRIPT,      		# < jump script_name
	JUMP_MAIN_MENU,   		# < return

	# [场景管理原子指令]
	SCENE_MOUNT,    		# < scene mount type name path [fade_duration=0]
	SCENE_UNMOUNT,  		# < scene unmount type name [fade_duration=0] [free=true]
	TRANSITION_IN,  		# < trans in [duration=1.0] [anim="fade_in"] [wait=true]
	TRANSITION_OUT, 		# < trans out [duration=1.0] [anim="fade_out"] [wait=true]
}

@export var head: Head
@export var params: Array[Variant] = []

func _init(head_: Head, args: Array[String] = []) -> void:
	head = head_
	
	match head_:
		# 音频指令
		# 参数: [path: String, vol: float, loop: bool]
		Head.MUSIC_PLAY:
			params.append(_arg_str(args, 0, ""))
			params.append(_arg_float(args, 1, 0.0)) # 默认音量偏移 0db 或 线性 0 (取决于你AudioManager实现)
			params.append(_arg_bool(args, 2, true))
		
		# 参数: [path: String, offset: float]
		Head.VOICE_PLAY, \
		Head.SFX_PLAY:
			params.append(_arg_str(args, 0, ""))
			params.append(_arg_float(args, 1, 0.0))
			
		# 参数: [time: float]
		Head.VOICE_EVENT:
			params.append(_arg_float(args, 0, 0.0))

		# 无参数音频指令
		Head.MUSIC_PAUSE, \
		Head.MUSIC_RESUME, \
		Head.MUSIC_STOP:
			pass

		# 视觉与资源
		# 参数: [path/script_name/text: String]
		Head.SET_BACKGROUND, \
		Head.CHAR_CHANGE_TEXTURE, \
		Head.OPTION, \
		Head.SET_BEGIN_SCRIPT, \
		Head.JUMP_SCRIPT:
			params.append(_arg_str(args, 0, ""))

		# 无参数跳转
		Head.JUMP_MAIN_MENU:
			pass

		# 角色动画
		# 参数: [char_index: int]
		Head.CHARACTER, \
		Head.CHAR_PLAY:
			params.append(_arg_int(args, 0, 0))

		# 参数: [path: String, x: float, y: float]
		Head.CHAR_SETUP:
			params.append(_arg_str(args, 0, ""))
			params.append(_arg_float(args, 1, 0.0))
			params.append(_arg_float(args, 2, 0.0))
				
		# 参数: [duration: float]
		Head.CHAR_SHOW_FADE, \
		Head.CHAR_HIDE_FADE, \
		Head.CHAR_WAIT:
			params.append(_arg_float(args, 0, 0.0))
			
		# 参数: [x: float, y: float, duration: float]
		Head.CHAR_MOVE_TO:
			params.append(_arg_float(args, 0, 0.0))
			params.append(_arg_float(args, 1, 0.0))
			params.append(_arg_float(args, 2, 0.0))

		# 选项系统（OPTION 已在上方按字符串处理）
		Head.OPTION_END:
			pass

		# 变量操作
		# 参数: [key: String, value: float]
		Head.VAR_SET, \
		Head.VAR_ADD, \
		Head.VAR_SUB, \
		Head.VAR_MUL, \
		Head.VAR_DIV:
			params.append(_arg_str(args, 0, "unknown_var")) # Key
			params.append(_arg_float(args, 1, 0.0)) # Value

		# 参数: [key: String, min: float, max: float]
		Head.VAR_RANDOM:
			params.append(_arg_str(args, 0, "unknown_var"))
			params.append(_arg_float(args, 1, 0.0)) # Min
			params.append(_arg_float(args, 2, 1.0)) # Max

		# 逻辑流控制
		# 参数: [key: String, operator: String, value: float]
		Head.IF, \
		Head.ELSE_IF:
			params.append(_arg_str(args, 0, ""))           # Key
			params.append(_arg_str(args, 1, "=="))         # Operator (>, <, ==, etc)
			params.append(_arg_float(args, 2, 0.0))         # Threshold Value

		# 无参数逻辑指令
		Head.ELSE, \
		Head.END_IF:
			pass

		# 场景挂载
		# 语法: < scene mount type name path [duration=0] [anim="fade"]
		Head.SCENE_MOUNT:
			params.append(_arg_str(args, 0, "world2d"))    # type
			params.append(_arg_str(args, 1, "default"))    # name
			params.append(_arg_str(args, 2, ""))           # path
			params.append(_arg_float(args, 3, 0.0))        # duration
			params.append(_arg_str(args, 4, "fade"))      # anim_name (新增)
		
		# 场景卸载
		# 语法: < scene unmount type name [duration=0] [anim="fade"] [free=true]
		Head.SCENE_UNMOUNT:
			params.append(_arg_str(args, 0, "world2d"))
			params.append(_arg_str(args, 1, "default"))
			params.append(_arg_float(args, 2, 0.0))        # duration
			params.append(_arg_str(args, 3, "fade"))       # anim_name (新增)
			params.append(_arg_bool(args, 4, true))        # free

		# 场景转场
		# 语法: < trans in [duration=1.0] [anim="fade_in"] [wait=true]
		Head.TRANSITION_IN:
			params.append(_arg_float(args, 0, 1.0))
			params.append(_arg_str(args, 1, "fade_in"))
			params.append(_arg_bool(args, 2, true))
			
		Head.TRANSITION_OUT:
			params.append(_arg_float(args, 0, 1.0))
			params.append(_arg_str(args, 1, "fade_out"))
			params.append(_arg_bool(args, 2, true))



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
	var head_name := _get_head_name(head)
	var params_str := _format_params()
	return "[Instruction] " + head_name + params_str


func _get_head_name(head_type: Head) -> String:
	match head_type:
		Head.BLANK: return "BLANK"
		Head.MUSIC_PLAY: return "MUSIC_PLAY"
		Head.MUSIC_PAUSE: return "MUSIC_PAUSE"
		Head.MUSIC_RESUME: return "MUSIC_RESUME"
		Head.MUSIC_STOP: return "MUSIC_STOP"
		Head.VOICE_PLAY: return "VOICE_PLAY"
		Head.SFX_PLAY: return "SFX_PLAY"
		Head.SET_BACKGROUND: return "SET_BACKGROUND"
		Head.VOICE_EVENT: return "VOICE_EVENT"
		Head.CHARACTER: return "CHARACTER"
		Head.CHAR_SETUP: return "CHAR_SETUP"
		Head.CHAR_SHOW_FADE: return "CHAR_SHOW_FADE"
		Head.CHAR_HIDE_FADE: return "CHAR_HIDE_FADE"
		Head.CHAR_MOVE_TO: return "CHAR_MOVE_TO"
		Head.CHAR_WAIT: return "CHAR_WAIT"
		Head.CHAR_CHANGE_TEXTURE: return "CHAR_CHANGE_TEXTURE"
		Head.CHAR_PLAY: return "CHAR_PLAY"
		Head.OPTION: return "OPTION"
		Head.OPTION_END: return "OPTION_END"
		Head.VAR_SET: return "VAR_SET"
		Head.VAR_ADD: return "VAR_ADD"
		Head.VAR_SUB: return "VAR_SUB"
		Head.VAR_MUL: return "VAR_MUL"
		Head.VAR_DIV: return "VAR_DIV"
		Head.VAR_RANDOM: return "VAR_RANDOM"
		Head.IF: return "IF"
		Head.ELSE_IF: return "ELSE_IF"
		Head.ELSE: return "ELSE"
		Head.END_IF: return "END_IF"
		Head.SET_BEGIN_SCRIPT: return "SET_BEGIN_SCRIPT"
		Head.JUMP_SCRIPT: return "JUMP_SCRIPT"
		Head.JUMP_MAIN_MENU: return "JUMP_MAIN_MENU"
		Head.SCENE_MOUNT: return "SCENE_MOUNT"
		Head.SCENE_UNMOUNT: return "SCENE_UNMOUNT"
		Head.TRANSITION_IN: return "TRANSITION_IN"
		Head.TRANSITION_OUT: return "TRANSITION_OUT"
		_: return "UNKNOWN"


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
