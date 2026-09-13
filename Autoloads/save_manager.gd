extends Node

var SAVE_DIR = OS.get_executable_path().get_base_dir().path_join(Global.config["save_dir"])

# 存档信息列表: {saved_game: SavedGame, path: String}
var save_data_list: Array[Dictionary] = []

# SaveUI 引用
var save_ui: SaveUI

# 当前选中存档索引
var selected_index: int = -1

func _ready() -> void:
	# 确保存档目录存在
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		Utils.make_dir_absolute(SAVE_DIR)
	
	SceneManager.pre_load({"ui": {"存档UI": Global.scenes["存档UI"]}})
	save_ui = SceneManager.get_scene("ui", "pool", "存档UI")
	
	# 连接 SaveUI 的信号和按钮
	if save_ui:
		# ItemList 选择信号
		if save_ui.item_list:
			save_ui.item_list.item_selected.connect(_on_save_selected)
		# 按钮
		if save_ui.delete_button:
			save_ui.delete_button.pressed.connect(_on_delete_pressed)
		if save_ui.load_button:
			save_ui.load_button.pressed.connect(_on_load_pressed)
	
	# 初始加载存档列表
	load_save_list()


## 扫描存档目录，加载所有存档
func load_save_list() -> void:
	save_data_list.clear()
	
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		GalLogger.warn("存档目录不存在: " + SAVE_DIR)
		return
	
	# 获取所有 .tres 文件
	var file_list = Utils.get_file_list(SAVE_DIR, false, false)
	
	for file_name in file_list:
		# 只处理 .tres
		if not file_name.ends_with(".tres"):
			continue
		
		var file_path = SAVE_DIR.path_join(file_name)
		
		# 试着加载存档
		var saved_game = _load_save_file(file_path)
		if saved_game:
			save_data_list.append({
				"saved_game": saved_game,
				"path": file_path
			})
	
	# 按时间戳排序，新的在前
	save_data_list.sort_custom(func(a, b): 
		var timestamp_a = _parse_timestamp(a.saved_game.timestamp)
		var timestamp_b = _parse_timestamp(b.saved_game.timestamp)
		return timestamp_a > timestamp_b
	)
	
	# 刷新 UI
	update_ui()


## 加载单个存档文件
func _load_save_file(file_path: String) -> SavedGame:
	if not FileAccess.file_exists(file_path):
		return null
	
	if not ResourceLoader.exists(file_path):
		GalLogger.warn("存档资源不存在: " + file_path)
		return null
	
	var saved_game = load(file_path) as SavedGame
	if not saved_game:
		GalLogger.warn("无法加载存档: " + file_path)
		return null
	
	return saved_game


## 解析时间戳字符串为 Unix 时间戳（用于排序）
## @param timestamp_str: 时间戳字符串（格式：YYYY-MM-DD HH:MM:SS 或 Unix 时间戳字符串）
## @return: Unix 时间戳（整数）
func _parse_timestamp(timestamp_str: String) -> int:
	if timestamp_str.is_empty():
		return 0
	
	# 纯数字直接转
	if timestamp_str.is_valid_int():
		return timestamp_str.to_int()
	
	# 简化处理，解析失败返回 0
	return 0


## 将存档列表渲染到 ItemList
func update_ui() -> void:
	if not save_ui or not save_ui.item_list:
		return
	
	var item_list = save_ui.item_list
	item_list.clear()
	
	for i in range(save_data_list.size()):
		var save_data = save_data_list[i]
		var saved_game: SavedGame = save_data.get("saved_game")
		var file_path: String = save_data.get("path", "")
		
		if not saved_game:
			continue
		
		# 组装显示文本
		var display_text = saved_game.title
		if display_text.is_empty():
			display_text = saved_game.script_name
		if display_text.is_empty():
			display_text = file_path.get_file().get_basename()
		
		# 附加脚本名和时间
		if not saved_game.script_name.is_empty():
			display_text += " " + saved_game.script_name
		
		if not saved_game.timestamp.is_empty():
			display_text += " " + saved_game.timestamp
		
		# 加载缩略图
		var thumbnail: Texture2D = null
		var thumbnail_path = saved_game.thumbnail_path
		if thumbnail_path.is_empty():
			# 未设置路径时按文件名推断
			var base_name = file_path.get_basename()
			thumbnail_path = SAVE_DIR.path_join(base_name + ".png")
		
		if not thumbnail_path.is_empty() and FileAccess.file_exists(thumbnail_path):
			var image = Image.load_from_file(thumbnail_path)
			if image:
				var image_texture = ImageTexture.create_from_image(image)
				thumbnail = image_texture
		
		# 添加到 ItemList
		item_list.add_item(display_text, thumbnail)
		
		# 把存档路径写进 metadata
		item_list.set_item_metadata(i, file_path)
	
	# 清空选中状态
	selected_index = -1
	_update_selected_display()


## 时间戳转可读字符串
func _format_timestamp(timestamp: int) -> String:
	if timestamp <= 0:
		return "未知时间"
	
	var dt = Time.get_datetime_dict_from_unix_time(timestamp)
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		dt.year, dt.month, dt.day,
		dt.hour, dt.minute, dt.second
	]


## 保存游戏到指定槽位
func save_game(slot_index: int = -1, title: String = "") -> bool:
	# 检查是否有可保存内容
	if StoryManager.cur_script_name.is_empty():
		GalLogger.warn("当前没有可保存的剧本")
		return false
	
	# 生成文件名
	var file_name: String
	var timestamp = Time.get_unix_time_from_system()
	if slot_index >= 0:
		file_name = "save_%d.tres" % slot_index
	else:
		# 使用时间戳生成文件名
		file_name = "save_%d.tres" % timestamp
	
	var file_path = SAVE_DIR.path_join(file_name)
	
	# 填充 SavedGame
	var saved_game = SavedGame.new()
	
	saved_game.vars = Global.vars
	saved_game.script_name = StoryManager.cur_script_name
	saved_game.idx = StoryManager.idx
	saved_game.execution_stack = StoryManager._execution_stack
	saved_game.timestamp = _format_timestamp(timestamp)
	if title.is_empty():
		saved_game.title = StoryManager.cur_script_name
	else:
		saved_game.title = title
	
	# 保存缩略图并写入路径
	var thumbnail_path = SAVE_DIR.path_join(file_name + ".png")
	
	var screenshot = Utils.take_screenshot()
	
	if screenshot:
		GalLogger.infos(screenshot)
		var size = save_ui.texture_rect.size
		screenshot.resize(size[0], size[1], Image.INTERPOLATE_LANCZOS)
		if screenshot.save_png(thumbnail_path) == OK:
			GalLogger.infos(thumbnail_path)
			saved_game.thumbnail_path = thumbnail_path
			GalLogger.info("缩略图已保存: " + thumbnail_path)
		else:
			GalLogger.error("缩略图保存失败")
	
	# 保存资源
	if ResourceSaver.save(saved_game, file_path) == OK:
		GalLogger.info("存档已保存: " + file_path)
	else:
		GalLogger.error("存档保存失败: " + file_path)
		return false
		
	MessageManager.show("已保存存档", "success")
	# 重新加载存档列表并刷新 UI
	load_save_list()
	
	return true


## 旧版缩略图保存接口（保留兼容）
func save_screenshot(slot_index: int):
	var screenshot = Utils.take_screenshot()
	if screenshot:
		screenshot.resize(128, 72, Image.INTERPOLATE_LANCZOS)
		
		var path = SAVE_DIR.path_join("save_%d.png" % slot_index)
		
		if screenshot.save_png(path) == OK:
			GalLogger.infos("缩略图已保存至:", path)
		else:
			GalLogger.error("缩略图保存失败")


## 加载指定索引的存档
func load_game(item_index: int) -> SavedGame:
	# 检查索引
	if item_index < 0 or item_index >= save_data_list.size():
		GalLogger.error("存档索引无效: " + str(item_index))
		return null
	
	var save_data = save_data_list[item_index]
	var file_path: String = save_data.get("path", "")
	var saved_game: SavedGame = save_data.get("saved_game")
	
	if not saved_game:
		GalLogger.error("存档数据无效")
		return null
	
	# 文件存在性检查
	if not FileAccess.file_exists(file_path):
		GalLogger.errors("存档文件不存在:", file_path, "从列表中移除")
		# 从列表中删除
		save_data_list.remove_at(item_index)
		update_ui()
		return null
	
	# 重新加载一次，拿最新数据
	var reloaded_game = _load_save_file(file_path)
	if not reloaded_game:
		GalLogger.errors("无法重新加载存档:", file_path, "从列表中移除")
		# 从列表中删除
		save_data_list.remove_at(item_index)
		update_ui()
		return null
	
	# 简单检查数据
	if reloaded_game.script_name.is_empty():
		GalLogger.warn("存档数据不完整: " + file_path)
	
	# 回写列表中的数据
	save_data_list[item_index]["saved_game"] = reloaded_game
	
	GalLogger.info("存档加载成功: " + file_path)
	return reloaded_game


## 返回存档列表副本
func get_save_list() -> Array[Dictionary]:
	return save_data_list.duplicate()


## 删除指定索引的存档
func delete_save(item_index: int) -> bool:
	if item_index < 0 or item_index >= save_data_list.size():
		GalLogger.errors("存档索引无效:", str(item_index))
		return false
	
	var save_data = save_data_list[item_index]
	var file_path: String = save_data.get("path", "")
	var saved_game: SavedGame = save_data.get("saved_game")
	
	# 删除存档文件
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
		GalLogger.infos("已删除存档文件:", file_path)
	
	# 删除缩略图
	if saved_game and not saved_game.thumbnail_path.is_empty():
		var thumbnail_path = saved_game.thumbnail_path
		if FileAccess.file_exists(thumbnail_path):
			DirAccess.remove_absolute(thumbnail_path)
			GalLogger.infos("已删除缩略图:", thumbnail_path)
	
	# 从列表中移除
	save_data_list.remove_at(item_index)
	update_ui()
	
	return true


## SaveUI: 存档选中
func _on_save_selected(item_index: int) -> void:
	selected_index = item_index
	_update_selected_display()


## 更新选中存档的显示（缩略图/按钮）
func _update_selected_display() -> void:
	if not save_ui:
		return
	
	# 缩略图
	if save_ui.texture_rect:
		if selected_index >= 0 and selected_index < save_data_list.size():
			var save_data = save_data_list[selected_index]
			var saved_game: SavedGame = save_data.get("saved_game")
			
			if saved_game and not saved_game.thumbnail_path.is_empty():
				var thumbnail_path = saved_game.thumbnail_path
				if FileAccess.file_exists(thumbnail_path):
					var image = Image.load_from_file(thumbnail_path)
					if image:
						var image_texture = ImageTexture.create_from_image(image)
						save_ui.texture_rect.texture = image_texture
					else:
						save_ui.texture_rect.texture = null
				else:
					save_ui.texture_rect.texture = null
			else:
				save_ui.texture_rect.texture = null
		else:
			save_ui.texture_rect.texture = null
	
	# 按钮状态
	if save_ui.delete_button:
		save_ui.delete_button.disabled = (selected_index < 0)
	if save_ui.load_button:
		save_ui.load_button.disabled = (selected_index < 0)


## 删除按钮
func _on_delete_pressed() -> void:
	if selected_index >= 0:
		delete_save(selected_index)


## 加载按钮
func _on_load_pressed() -> void:
	if selected_index >= 0:
		var saved_game = load_game(selected_index)
		if saved_game:
			StoryManager.load_game(saved_game)
			var option_ui: OptionUI = SceneManager.get_scene("ui", "mounted", "选择UI")
			if option_ui:
				option_ui.canceled.emit()
			get_tree().paused = false
			SceneManager.unmount({"ui": {"存档UI": Global.scenes["存档UI"]}}, false)
		else:
			GalLogger.warns("载入存档失败")
