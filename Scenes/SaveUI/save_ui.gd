class_name SaveUI extends Control

@export var item_list: ItemList        ## 列表（图标为缩略图）
@export var texture_rect: TextureRect  ## 当前选中存档缩略图
@export var delete_button: Button      ## 删除按钮
@export var load_button: Button        ## 载入按钮


func _enter_tree() -> void:
	SaveManager.load_save_list()


func _on_exit_pressed() -> void:
	get_tree().paused = false
	SceneManager.unmount({"ui": {"存档UI": Global.scenes["存档UI"]}}, false)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				_on_exit_pressed()
			KEY_DELETE:
				SaveManager._on_delete_pressed()
			KEY_ENTER, KEY_KP_ENTER:
				SaveManager._on_load_pressed()
