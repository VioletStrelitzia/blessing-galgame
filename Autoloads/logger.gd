class_name GalLogger extends Node

## 统一日志入口。规范见 docs/日志规范.md。
## 用法：文件顶部定义 const LOG_TAG := "StoryManager"，然后
##   GalLogger.info(LOG_TAG, "加载剧本: %s (%d 项)" % [name, count])

enum Level { DEBUG, INFO, WARN, ERROR }

const _LEVEL_NAMES: Array[String] = ["DEBUG", "INFO ", "WARN ", "ERROR"]
const _LEVEL_COLORS: Array[String] = ["gray", "white", "yellow", "red"]

static var _level: int = Level.INFO
static var _file: FileAccess = null


static func debug(tag: String, msg: String) -> void:
	_write(Level.DEBUG, tag, msg)


static func info(tag: String, msg: String) -> void:
	_write(Level.INFO, tag, msg)


static func warn(tag: String, msg: String) -> void:
	_write(Level.WARN, tag, msg)


static func error(tag: String, msg: String) -> void:
	_write(Level.ERROR, tag, msg)


static func set_log_file(path: String) -> void:
	if path.is_empty():
		return
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_error("GalLogger: 无法打开日志文件: " + path)


static func set_log_level(level_str: String) -> void:
	var idx := Level.keys().find(level_str.to_upper())
	if idx == -1:
		warn("Logger", "未知日志级别: %s，保持当前级别" % level_str)
		return
	_level = idx


static func _write(level: int, tag: String, msg: String) -> void:
	if level < _level:
		return

	var line := "[%s] [%s] [%s] %s" % [_timestamp(), _LEVEL_NAMES[level], tag, msg]

	match level:
		Level.WARN:
			push_warning(line)
		Level.ERROR:
			push_error(line)
		_:
			# 控制台路径转义 BBCode（消息可能含剧本正文等带方括号的内容）
			var console_line := "[%s] [%s] [%s] %s" % [
				_timestamp(), _LEVEL_NAMES[level], tag, msg.replace("[", "[lb]")
			]
			print_rich("[color=%s]%s[/color]" % [_LEVEL_COLORS[level], console_line])

	if _file:
		_file.store_line(line)
		_file.flush()


static func _timestamp() -> String:
	var unix := Time.get_unix_time_from_system()
	var d := Time.get_datetime_dict_from_system()  # 本地墙钟（秒级）
	var ms := int(fposmod(unix, 1.0) * 1000.0)     # 毫秒取自 unix 时间的小数部分
	return "%04d-%02d-%02d %02d:%02d:%02d.%03d" % [
		d.year, d.month, d.day, d.hour, d.minute, d.second, ms
	]
