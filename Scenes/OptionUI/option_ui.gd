class_name OptionUI extends Control

signal option_made(index: int)
@warning_ignore("unused_signal")
signal canceled

@export var vbox: VBoxContainer


func _ready() -> void:
	self.hide()

func show_options(options: Array[String]) -> void:
	_clear_options()

	for i in options.size():
		var option_text = options[i]
		
		var button = Button.new()
		button.text = option_text
		button.autowrap_mode = TextServer.AUTOWRAP_WORD
		
		# 按钮内边距和样式
		var style_normal = StyleBoxFlat.new()
		style_normal.set_content_margin_all(10)
		
		style_normal.bg_color = Color(0.2, 0.2, 0.2) 
		
		button.add_theme_stylebox_override("normal", style_normal)
		
		var style_hover = style_normal.duplicate()
		style_hover.bg_color = Color(0.3, 0.3, 0.3)
		button.add_theme_stylebox_override("hover", style_hover)
		# --- 代码方式结束 ---
		
		button.pressed.connect(_on_option_button_pressed.bind(i))
		vbox.add_child(button)
	
	self.show()


func _clear_options() -> void:
	for child in vbox.get_children():
		child.queue_free()


func _on_option_button_pressed(index: int) -> void:
	option_made.emit(index)
	GalLogger.infos("选择了选项索引", index)
	# 卸载但不释放（保留在pool中）
	SceneManager.unmount({
		"ui": {"选择UI": ""}
	}, false)
	_clear_options()


func _on_canceled() -> void:
	SceneManager.unmount({
		"ui": {"选择UI": ""}
	}, false)
	_clear_options()
