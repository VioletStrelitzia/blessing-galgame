extends SceneTree

## 冒烟测试：校验演示剧本编译产物的内容结构 + 路径策略 + bool→float 传参行为
## 用法：godot --headless --path . -s test/smoke_test.gd

var _ok := true

func _init() -> void:
	for path in ["res://GalSs/demo_scene1.tres", "res://GalSs/demo_scene2.tres"]:
		var seq_res = ResourceLoader.load(path)
		if seq_res == null:
			print("FAIL: 无法加载 ", path)
			_ok = false
			continue
		print("== ", path, " 共 ", seq_res.seq.size(), " 项 ==")
		for item in seq_res.seq:
			print("   ", item)
	# 对应 story_manager._music_play 里 play_music(stream, pos, loop) 的调用方式
	_type_check(true)

# -s 模式下 autoload 与全局类要到主循环初始化后才可用，路径断言须放在这里
func _initialize() -> void:
	# 路径策略：编辑器/CI 下一律解析到项目根（导出行为见 docs/路径策略设计.md）
	var project_root := ProjectSettings.globalize_path("res://")
	if PathManager.game_root() != project_root:
		print("FAIL: game_root = ", PathManager.game_root())
		_ok = false
	if PathManager.writable_root() != project_root:
		print("FAIL: writable_root = ", PathManager.writable_root())
		_ok = false
	var cfg_paths := PathManager.config_read_paths()
	if cfg_paths.size() != 1 or cfg_paths[0] != "res://config.json":
		print("FAIL: config_read_paths = ", cfg_paths)
		_ok = false
	print("SMOKE_TEST_DONE ok=", _ok)
	quit(0 if _ok else 1)

func _type_check(x: float) -> void:
	print("bool->float 传参未报错，x = ", x)
