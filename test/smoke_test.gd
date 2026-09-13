extends SceneTree

## 冒烟测试：校验演示剧本编译产物的内容结构 + bool→float 传参行为
## 用法：godot --headless --path . -s test/smoke_test.gd

func _init() -> void:
	var ok := true
	for path in ["res://GalSs/demo_scene1.tres", "res://GalSs/demo_scene2.tres"]:
		var seq_res = ResourceLoader.load(path)
		if seq_res == null:
			print("FAIL: 无法加载 ", path)
			ok = false
			continue
		print("== ", path, " 共 ", seq_res.seq.size(), " 项 ==")
		for item in seq_res.seq:
			print("   ", item)
	# 对应 story_manager._music_play 里 play_music(stream, pos, loop) 的调用方式
	_type_check(true)
	print("SMOKE_TEST_DONE ok=", ok)
	quit(0 if ok else 1)

func _type_check(x: float) -> void:
	print("bool->float 传参未报错，x = ", x)
