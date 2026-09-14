class_name Utils extends Node
const LOG_TAG := "Utils"



## 打开文件，失败时返回 null 并记录日志
static func open_file(
	path: String,
	flags: FileAccess.ModeFlags = FileAccess.READ
) -> FileAccess:
	var file = FileAccess.open(path, flags)
	if not file:
		GalLogger.error(LOG_TAG, "无法打开文件：" + path)
	return file


## 打开目录，可选自动创建，失败时返回 null 并记录日志
static func open_dir(
	path: String,
	create: bool = false
) -> DirAccess:
	var dir = DirAccess.open(path)
	if not dir:
		if create:
			make_dir_absolute(dir)
		else:
			GalLogger.error(LOG_TAG, "无法打开目录：" + path)
	return dir


## 加载 JSON 文件为字典，失败返回空字典
static func load_json(path: String) -> Dictionary:
	var hash_file = open_file(path, FileAccess.READ)
	if not hash_file:
		return {}
	var json_text = hash_file.get_as_text()
	hash_file.close()
		
	var json = JSON.new()
	var parse_result = json.parse(json_text)
	
	if parse_result != OK:
		GalLogger.error(LOG_TAG, "解析 JSON 失败：" + path +
			"，code=" + str(parse_result) +
			"，msg=" + json.get_error_message())
		return {}
	
	if json.data is not Dictionary:
		GalLogger.error(LOG_TAG, "JSON 结构不是字典: " + path)
	
	return json.data


static func save_json(path: String, json_dict: Dictionary):
	var file = Utils.open_file(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(json_dict, "\t"))
	file.close()


static func get_file_list(
	path: String,
	recursive: bool = false,
	add_path: bool = false
) -> Array[String]:
	var list: Array[String] = _get_file_list(
		path, recursive, add_path, ""
	)
	return list


## 递归合并配置字典
static func merge_dicts(target: Dictionary, source: Dictionary) -> void:
	for key in source:
		if target.has(key):
			if target[key] is Dictionary and source[key] is Dictionary:
				if target[key].is_empty() and not source[key].is_empty():
					target[key] = source[key]
				else:
					merge_dicts(target[key], source[key])
			else:
				target[key] = source[key]


static func _get_file_list(
	path: String,
	recursive: bool = false,
	add_path: bool = false,
	relative_prefix: String = ""
) -> Array[String]:
	var list: Array[String] = []
	var dir = Utils.open_dir(path, false)
	dir.list_dir_begin()
	var file_or_dir = dir.get_next()
	while not file_or_dir.is_empty():
		if dir.current_is_dir():
			if recursive:
				list.append_array(_get_file_list(
					path.path_join(file_or_dir), recursive, add_path,
					relative_prefix.path_join(file_or_dir))) 
		else:
			var file_path = relative_prefix.path_join(file_or_dir)
			if add_path:
				file_path = path.path_join(file_or_dir)
			list.append(file_path)
		file_or_dir = dir.get_next()
	return list


static func make_dir_absolute(
	path: String
) -> void:
	if DirAccess.make_dir_absolute(path) != OK:
		GalLogger.error(LOG_TAG, "无法创建目录: " + path)


static func take_screenshot() -> Image:
	# 根 Viewport 截图
	var root = Engine.get_main_loop().root
	if root:
		var viewport = root.get_viewport()
		var image = viewport.get_texture().get_image()
		return image
	else:
		GalLogger.error(LOG_TAG, "无法获取根 Viewport")
		return null
