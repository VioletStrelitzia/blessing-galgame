class_name GalLogger extends Node

enum LogLevel {
	DEBUG,
	INFO,
	WARN,
	ERROR
}

# 配置
static var log_file: FileAccess = null
static var log_level: LogLevel = LogLevel.INFO
static var use_json_format: bool = false # JSON格式将暂时保留详细格式，未来可扩展
static var use_colors: bool = true

# 模块颜色
static var module_colors: Array[String] = [
	"aqua", "lime", "silver", "teal", "navy", "olive", "maroon",
	"purple", "fuchsia", "gray"
]

# 公共 API（单字符串）
static func info(content: String) -> void:
	_log(LogLevel.INFO, content)

static func warn(content: String) -> void:
	_log(LogLevel.WARN, content)

static func error(content: String) -> void:
	_log(LogLevel.ERROR, content)

static func debug(content: String) -> void:
	_log(LogLevel.DEBUG, content)


# 公共 API（多参数）
static func infos(...args: Array[Variant]) -> void:
	_log_with_args(LogLevel.INFO, " ", args)

static func warns(...args: Array[Variant]) -> void:
	_log_with_args(LogLevel.WARN, " ", args)

static func errors(...args: Array[Variant]) -> void:
	_log_with_args(LogLevel.ERROR, " ", args)

static func debugs(...args: Array[Variant]) -> void:
	_log_with_args(LogLevel.DEBUG, " ", args)


static func infot(...args: Array[Variant]) -> void:
	_log_with_args(LogLevel.INFO, "\t", args)

static func warnt(...args: Array[Variant]) -> void:
	_log_with_args(LogLevel.WARN, "\t", args)

static func errort(...args: Array[Variant]) -> void:
	_log_with_args(LogLevel.ERROR, "\t", args)

static func debugt(...args: Array[Variant]) -> void:
	_log_with_args(LogLevel.DEBUG, "\t", args)


# 配置
static func set_log_file(log_file_path: String) -> void:
	if not log_file_path.is_empty():
		log_file = FileAccess.open(log_file_path, FileAccess.WRITE)

static func set_log_level(log_level_str: String) -> void:
	var upper_str = log_level_str.to_upper()
	if LogLevel.keys().has(upper_str):
		log_level = LogLevel.get(upper_str)
	else:
		push_warning("Logger: 未知的日志级别 '" + log_level_str + "'，将使用 DEBUG")
		log_level = LogLevel.DEBUG


# 核心
static func _log(level: LogLevel, content: String) -> void:
	if level < log_level:
		return

	var call_info = _get_call_info()
	var final_log_str: String

	# 根据日志级别选择不同的格式化策略
	if level == LogLevel.INFO and not use_json_format:
		final_log_str = _format_info_log(call_info, content)
	else:
		final_log_str = _format_detailed_log(level, call_info, content)
	
	_output_log(level, final_log_str)

static func _log_with_args(level: LogLevel, separator: String, args: Array[Variant]) -> void:
	if level < log_level:
		return
		
	if args.is_empty():
		return
		
	var content = _format_args(args, separator)
	_log(level, content)

static func _format_args(args: Array[Variant], separator: String) -> String:
	var string_parts: Array[String] = []
	for arg in args:
		string_parts.append(str(arg))
	return separator.join(string_parts)

static func _format_info_log(call_info: Dictionary, content: String) -> String:
	var timestamp = Time.get_datetime_string_from_system(false, true)
	var module_name = call_info.source.get_file().get_basename()
	var color_tag = _get_module_color(module_name)
	
	var colored_content = "%s%s%s" % [color_tag, content, "[/color]"]
	
	return "[%s] | %s" % [timestamp, colored_content]

static func _format_detailed_log(level: LogLevel, call_info: Dictionary, content: String) -> String:
	var timestamp = Time.get_datetime_string_from_system()
	var level_str = LogLevel.keys()[level].rpad(5)
	var module_str = "%s:%d" % [call_info.source.get_file(), call_info.line]
	
	return "[%s] [%s] [%s] | %s" % [timestamp, level_str, module_str, content]

static func _get_module_color(module_name: String) -> String:
	var hash_value = module_name.hash()
	var color_index = abs(hash_value) % module_colors.size()
	var color_name = module_colors[color_index]
	return "[color=%s]" % color_name

static func _output_log(level: LogLevel, log_str: String) -> void:
	match level:
		LogLevel.WARN:
			push_warning(log_str)
		LogLevel.ERROR:
			push_error(log_str)
		_:
			if use_colors:
				print_rich(log_str)
			else:
				var plain_text = _strip_bbcode(log_str)
				print_rich(plain_text)

	if log_file:
		var plain_text = _strip_bbcode(log_str)
		log_file.store_line(plain_text)
		log_file.flush()

static func _strip_bbcode(text: String) -> String:
	var regex = RegEx.new()
	regex.compile("\\[\\/?.*?\\]")
	return regex.sub(text, "", true)

static func _get_call_info() -> Dictionary:
	var stack = get_stack()
	if stack.size() < 4:
		return { "source": "Unknown", "line": -1 }

	var target_frame: Dictionary = stack[3]
	return {
		"source": target_frame.source,
		"line": target_frame.line,
	}
