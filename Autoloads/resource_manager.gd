extends Node
const LOG_TAG := "ResourceManager"


var json_path: String = "res://".path_join(Global.config["res_json"])
var scripts_save_dir: String = "res://".path_join(Global.config["scripts"]["save_dir"])

var _path_dict: Dictionary = {
	"audio": {},
	"texture": {},
	"script": {},
}

var _cache: Dictionary = {}


func _ready():
	_load_pck_mods()
	var path_dict = Utils.load_json(json_path)
	Utils.merge_dicts(_path_dict, path_dict)
	
	for type in _path_dict:
		for key in _path_dict[type]:
			if _path_dict[type][key] is String and \
				not _path_dict[type][key].begins_with("res://"):
				_path_dict[type][key] = "res://".path_join(_path_dict[type][key])
	
	if OS.has_feature("editor") and Global.config["scripts"]["check"]:
		var di := DialogueImporter.new()
		di.read_dir = "res://".path_join(Global.config["scripts"]["read_dir"])
		di.save_dir = scripts_save_dir
		add_child(di)
		remove_child(di)
		di.queue_free()
	elif Global.config["scripts"]["check"]:
		GalLogger.info(LOG_TAG, "导出构建，跳过剧本编译")

	var list := Utils.get_file_list(scripts_save_dir)
	for file in list:
		if file.begins_with("."):
			continue
		var logical := Utils.logical_name(file)
		_path_dict["script"][logical.get_basename()] = scripts_save_dir.path_join(logical)


func _exit_tree() -> void:
	_cache.clear()
	_path_dict.clear()


func load(res_type: String, res_key: String) -> Resource:
	GalLogger.debug(LOG_TAG, "尝试加载资源: " + res_type + "/" + res_key)
	
	# 运行时缓存
	if _cache.has(res_type) and _cache[res_type].has(res_key):
		return _cache[res_type][res_key]
	
	# 解析为内部路径
	var internal_path = _resolve_path(res_type, res_key)
	if internal_path.is_empty():
		GalLogger.error(LOG_TAG, "无法解析资源路径: %s/%s" % [res_type, res_key])
		return null

	var loaded_resource: Resource = null

	# 加载
	if ResourceLoader.exists(internal_path):
		loaded_resource = load(internal_path)
		if loaded_resource:
			GalLogger.debug(LOG_TAG, "从内部资源加载: " + internal_path)
		else:
			GalLogger.error(LOG_TAG, "内部资源加载失败: " + internal_path)
	else:
		GalLogger.error(LOG_TAG, "内部资源不存在: " + internal_path)

	# 缓存并返回
	if loaded_resource:
		if not _cache.has(res_type):
			_cache[res_type] = {}
		_cache[res_type][res_key] = loaded_resource
		GalLogger.debug(LOG_TAG, "资源已加载并缓存: " + internal_path + " -> " + res_type + "-" + res_key)
		return loaded_resource
	else:
		GalLogger.error(LOG_TAG, "未找到资源: " + res_type + "-" + res_key)
		return null


func _resolve_path(res_type: String, res_key: String) -> String:
	if res_key.begins_with("user://") or res_key.begins_with("res://"):
		return res_key

	if _path_dict.has(res_type) and _path_dict[res_type].has(res_key):
		return _path_dict[res_type][res_key]

	var base_dir = ""
	if res_type == "audio":
		base_dir = Global.config["audio_dir"]
	elif res_type == "texture":
		base_dir = Global.config["image_dir"]
	elif res_type == "script":
		base_dir = scripts_save_dir
	
	if not base_dir.is_empty():
		if base_dir.begins_with("res://"):
			base_dir = base_dir.substr(6)
		
		if res_key.begins_with(base_dir):
			return "res://".path_join(res_key)
		else:
			return "res://".path_join(base_dir).path_join(res_key)

	GalLogger.warn(LOG_TAG, "映射表未找到 '" + res_type + "/" + res_key + "'，尝试直接当路径用")
	return res_key


func unload(res_type: String, res_key: String) -> void:
	if _cache.has(res_type) and _cache[res_type].has(res_key):
		_cache[res_type].erase(res_key)
		GalLogger.debug(LOG_TAG, "资源已从缓存中卸载: " + res_type + "/" + res_key)
		if _cache[res_type].is_empty():
			_cache.erase(res_type)


func clear_all_cache() -> void:
	_cache.clear()
	GalLogger.debug(LOG_TAG, "所有资源缓存已清空")


func _load_pck_mods():
	var mods_dir_path = PathManager.mods_dir(Global.config["mod_dir"])
	GalLogger.info(LOG_TAG, "扫描模组目录: " + mods_dir_path)

	if not DirAccess.dir_exists_absolute(mods_dir_path):
		GalLogger.warn(LOG_TAG, "模组目录不存在，跳过模组加载")
		return

	var dir = DirAccess.open(mods_dir_path)
	if not dir:
		GalLogger.error(LOG_TAG, "无法打开模组目录: " + mods_dir_path)
		return

	# 扫描所有模组文件夹，读取 mod.json
	var mod_info_list = []
	dir.list_dir_begin()
	var mod_dir_name = dir.get_next()
	while mod_dir_name != "":
		if dir.current_is_dir():
			var mod_path = mods_dir_path.path_join(mod_dir_name)
			var mode_json_path = mod_path.path_join("mod.json")
			
			if FileAccess.file_exists(mode_json_path):
				var mod_info = _parse_mod_metadata(mode_json_path, mod_path)
				if mod_info:
					mod_info_list.append(mod_info)
			else:
				GalLogger.warn(LOG_TAG, "在模组文件夹 '" + mod_dir_name + "' 中未找到 mod.json，将跳过。")
		mod_dir_name = dir.get_next()
	dir.list_dir_end()

	# 按 priority 排序，小的先加载
	mod_info_list.sort_custom(func(a, b): return a.priority < b.priority)

	# 依次加载 PCK
	GalLogger.info(LOG_TAG, "发现 " + str(mod_info_list.size()) + " 个模组，按优先级加载")
	for mod_info in mod_info_list:
		var pck_path = mod_info.pck_path
		GalLogger.debug(LOG_TAG, "加载模组: '" + mod_info.name + "' (priority=" + str(mod_info.priority) + ") -> " + pck_path)
		if ProjectSettings.load_resource_pack(pck_path):
			GalLogger.debug(LOG_TAG, "模组加载成功")
		else:
			GalLogger.error(LOG_TAG, "模组加载失败: " + pck_path)


func _parse_mod_metadata(mode_json_path: String, mod_folder_path: String) -> Dictionary:
	var data = Utils.load_json(mode_json_path)
	
	# 必需字段
	if not data.has("name") or not data.has("pck_file") or not data.has("priority"):
		GalLogger.error(LOG_TAG, "mod.json (" + mode_json_path + ") 缺少 name/pck_file/priority")
		return {}

	var pck_file_name = data.get("pck_file")
	var pck_path = mod_folder_path.path_join(pck_file_name)

	if not FileAccess.file_exists(pck_path):
		GalLogger.error(LOG_TAG, "mod.json '" + data.get("name") + "' 指定的 PCK 不存在: " + pck_path)
		return {}

	return {
		"name": data.get("name"),
		"priority": data.get("priority"),
		"pck_path": pck_path
	}
