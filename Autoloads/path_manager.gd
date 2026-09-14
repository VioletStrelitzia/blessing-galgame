class_name PathManager extends Node
const LOG_TAG := "PathManager"

## 路径统一入口。设计见 docs/路径策略设计.md。
## 三域：内置 res://（只读资产）｜game_root（编辑器=项目根，导出=exe 旁）｜user://（兜底）

const CONFIG_FILE := "config.json"

static var _writable_root: String = ""


## 游戏根目录：编辑器=项目根，导出=exe 所在目录
static func game_root() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://")
	return OS.get_executable_path().get_base_dir()


## 可写数据根目录：便携优先，不可写降级 user://
static func writable_root() -> String:
	if _writable_root.is_empty():
		_writable_root = _resolve_writable_root()
	return _writable_root


## 模组目录（只读扫描）
static func mods_dir(mod_dir: String) -> String:
	return game_root().path_join(mod_dir)


## 配置文件读取链：默认层在前，覆盖层在后（后合并者优先级高）
static func config_read_paths() -> Array[String]:
	var paths: Array[String] = ["res://".path_join(CONFIG_FILE)]
	if not OS.has_feature("editor"):
		for p in [game_root().path_join(CONFIG_FILE), "user://".path_join(CONFIG_FILE)]:
			if FileAccess.file_exists(p):
				paths.append(p)
	return paths


## 配置文件写回落点
static func config_write_path() -> String:
	if OS.has_feature("editor"):
		return "res://".path_join(CONFIG_FILE)
	return writable_root().path_join(CONFIG_FILE)


static func _resolve_writable_root() -> String:
	var root := game_root()
	if _probe_writable(root):
		GalLogger.info(LOG_TAG, "可写数据目录: %s" % root)
		return root
	GalLogger.warn(LOG_TAG, "游戏目录不可写，降级: %s → %s" % [root, ProjectSettings.globalize_path("user://")])
	if _probe_writable("user://"):
		return "user://"
	GalLogger.error(LOG_TAG, "user:// 亦不可写，退回游戏目录，数据可能无法持久保存")
	return root


static func _probe_writable(dir: String) -> bool:
	var probe := dir.path_join(".probe")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true
