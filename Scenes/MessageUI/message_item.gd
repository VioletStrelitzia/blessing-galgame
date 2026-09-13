extends PanelContainer

@onready var label = $HBoxContainer/RichTextLabel

func setup(text: String, type: String):
	label.text = text
	
	var style = get_theme_stylebox("panel").duplicate()
	match type:
		"error": style.bg_color = Color.RED
		"success": style.bg_color = Color.GREEN
		_: style.bg_color = Color.DARK_GRAY
	add_theme_stylebox_override("panel", style)
	
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	tween.tween_interval(3.0) # 停留3秒
	tween.tween_property(self, "modulate:a", 0.0, 0.3) # 淡出
	tween.tween_callback(queue_free) # 销毁
