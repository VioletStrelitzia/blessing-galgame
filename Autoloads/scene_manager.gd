extends Node
const LOG_TAG := "SceneManager"


@export var transition_controller: SceneTransitionController

# 场景管理器核心结构
# world2d: 游戏世界
# ui: UI 界面
var scene_managers: Dictionary = {
	"world2d": {
		"pool": {},        # 预加载但未挂载的场景池 {scene_name: Node}
		"mounted": {},     # 已挂载到场景树的场景 {scene_name: Node}
		"mount_point": Node.new() # 场景挂载的父节点
	},
	"ui": {
		"pool": {},
		"mounted": {},
		"mount_point": Node.new()
	}
}

# 记录所有场景路径，key 形如 "world2d|Level1" / "ui|HUD"
var path_dict: Dictionary[String, String] = {}


func _ready() -> void:
	# 把挂载点加进场景树
	add_child(scene_managers["world2d"]["mount_point"])
	add_child(scene_managers["ui"]["mount_point"])
	
	GalLogger.info(LOG_TAG, "场景管理器初始化完毕")


func get_scene(type: String, where: String, key: String) -> Node:
	if not scene_managers.has(type):
		return null
	
	var type_dict = scene_managers[type]
	if typeof(type_dict) != TYPE_DICTIONARY:
		return null
	
	if not type_dict.has(where):
		return null
	
	var where_dict = type_dict[where]
	if typeof(where_dict) != TYPE_DICTIONARY:
		return null
	
	if not where_dict.has(key):
		return null
	
	var node = where_dict[key]
	# 确保返回的是 Node 类型
	if node is Node:
		return node
	else:
		return null


## 淡出 -> 卸载 -> 挂载 -> 淡入
func mount_and_unmount(
	scenes_to_mount: Dictionary,
	scenes_to_unmount: Dictionary,
	fade_out_duration: float = 1.0,
	fade_in_duration: float = 1.0,
	free_on_unmount: bool = true
) -> void:
	await transition("fade_out", fade_out_duration)
	
	unmount(scenes_to_unmount, free_on_unmount)
	mount(scenes_to_mount)
	
	await transition("fade_in", fade_in_duration)


## 预加载到池中，不挂载
func pre_load(scenes_to_load: Dictionary) -> void:
	for scene_type in scenes_to_load:
		var manager = scene_managers.get(scene_type)
		if not manager:
			GalLogger.error(LOG_TAG, "未知的场景类型 '" + scene_type + "'")
			continue
		
		var pool_dict = manager.pool as Dictionary
		
		for scene_name in scenes_to_load[scene_type]:
			if pool_dict.has(scene_name):
				continue
			
			var path = scenes_to_load[scene_type][scene_name]
			GalLogger.info(LOG_TAG, "预加载: " + scene_name + " - " + path)
			var packed_scene = load(path) as PackedScene
			if packed_scene:
				var node = packed_scene.instantiate()
				pool_dict[scene_name] = node
				var composite_key = scene_type + "|" + scene_name
				path_dict[composite_key] = path
			else:
				GalLogger.error(LOG_TAG, "无法加载场景: " + path)


func mount(scenes_to_mount: Dictionary) -> void:
	for scene_type in scenes_to_mount:
		var manager = scene_managers.get(scene_type)
		if not manager:
			GalLogger.error(LOG_TAG, "未知的场景类型 '" + scene_type + "'")
			continue
		
		var mount_point = manager.mount_point
		if not mount_point:
			GalLogger.error(LOG_TAG, "场景类型 '" + scene_type + "' 的挂载点 未设置！")
			continue

		for scene_name in scenes_to_mount[scene_type]:
			var path = scenes_to_mount[scene_type][scene_name]
			_mount_single_scene(scene_type, scene_name, path, manager)


func umount_all(
	types: Array[String],
	free: bool = true
) -> void:
	for type in types:
		# 构造 unmount 期望的字典格式
		var mounted_names = scene_managers[type]["mounted"].keys()
		var scenes_to_unmount: Dictionary = {}
		for mounted_name in mounted_names:
			scenes_to_unmount[mounted_name] = ""
		
		unmount({type: scenes_to_unmount}, free)


func unmount(
	scenes_to_unmount: Dictionary,
	free: bool = true
) -> void:
	for scene_type in scenes_to_unmount:
		var manager = scene_managers.get(scene_type)
		if not manager:
			GalLogger.error(LOG_TAG, "未知的场景类型 '" + scene_type + "'")
			continue
		
		# 用 .keys() 拿一份键的副本，避免遍历时修改原字典
		for scene_name in scenes_to_unmount[scene_type].keys():
			_unmount_single_scene(scene_name, manager, free)


func _mount_single_scene(scene_type: String, scene_name: String, path: String, manager: Dictionary) -> void:
	var pool_dict = manager.pool
	var mounted_dict = manager.mounted
	var mount_point = manager.mount_point

	# 已挂载则直接返回
	if mounted_dict.has(scene_name):
		GalLogger.warn(LOG_TAG, "场景 '" + scene_name + "' 已经挂载，跳过。")
		return

	var node: Node
	if pool_dict.has(scene_name):
		# 从池中取出
		node = pool_dict[scene_name]
		pool_dict.erase(scene_name)
		GalLogger.info(LOG_TAG, "从池中获取: " + scene_name)
	else:
		# 现场加载
		GalLogger.info(LOG_TAG, "加载: " + scene_name + " - " + path)
		var packed_scene = load(path) as PackedScene
		if not packed_scene:
			GalLogger.error(LOG_TAG, "无法加载场景: " + path)
			return
		node = packed_scene.instantiate()
		var composite_key = scene_type + "|" + scene_name
		path_dict[composite_key] = path

	mount_point.add_child(node)
	mounted_dict[scene_name] = node


func _unmount_single_scene(
	scene_name: String,
	manager: Dictionary,
	free: bool
) -> void:
	var mounted_dict = manager.mounted
	var mount_point = manager.mount_point

	if not mounted_dict.has(scene_name):
		GalLogger.warn(LOG_TAG, "尝试卸载一个未挂载的场景: " + scene_name)
		return

	GalLogger.info(LOG_TAG, "卸载: " + scene_name)
	var node = mounted_dict[scene_name]
	mount_point.remove_child(node)

	if free:
		GalLogger.info(LOG_TAG, "释放: " + scene_name)
		node.queue_free()
	else:
		GalLogger.info(LOG_TAG, "加入缓存池: " + scene_name)
		manager.pool[scene_name] = node
	
	# 从已挂载字典中移除
	mounted_dict.erase(scene_name)


func transition(animation: String, duration: float = 1.0):
	# 空值检查，避免编辑器中未设置 transition_controller 崩溃
	if not is_instance_valid(transition_controller):
		GalLogger.error(LOG_TAG, "SceneTransitionController 未设置或无效！")
		return
		
	if duration > 0:
		await transition_controller.transition(animation, duration)


func free_scenes(scenes_to_free: Dictionary):
	for scene_type in scenes_to_free:
		var manager = scene_managers.get(scene_type)
		if not manager:
			GalLogger.error(LOG_TAG, "未知的场景类型 '" + scene_type + "'")
			continue

		for scene_name in scenes_to_free[scene_type]:
			var node = manager["pool"].get(scene_name)
			if node:
				# queue_free 确保安全释放
				node.queue_free()
				manager["pool"].erase(scene_name)
				GalLogger.info(LOG_TAG, "已将场景 '" + scene_name + "' 加入释放队列")
			else:
				GalLogger.warn(LOG_TAG, "尝试释放一个不在池中的场景: " + scene_name)
