class_name DialogueUI
extends Control

@export_group("UI")
@export var charater_name_text: RichTextLabel
@export var text_box: RichTextLabel
@export var avatar: TextureRect

var typing_tween: Tween

var current_fade_tween: Tween

var current_dialogue_content: String

signal dialogue_finished
signal forward
signal fast_forward


func _ready():
	visible = false
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _kill_current_fade():
	if current_fade_tween and current_fade_tween.is_running():
		current_fade_tween.kill()
	current_fade_tween = null


func fade_in() -> Tween:
	_kill_current_fade()

	visible = true
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	current_fade_tween = create_tween()
	current_fade_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	current_fade_tween.tween_property(self, "modulate:a", 1.0, 0.3)

	current_fade_tween.tween_callback(func():
		mouse_filter = Control.MOUSE_FILTER_PASS
		current_fade_tween = null  # 动画结束，清理引用
	)

	return current_fade_tween


func fade_out() -> Tween:
	_kill_current_fade()

	# 确保淡出开始时 UI 可见
	visible = true
	mouse_filter = Control.MOUSE_FILTER_PASS

	current_fade_tween = create_tween()
	current_fade_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	current_fade_tween.tween_property(self, "modulate:a", 0.0, 0.3)

	current_fade_tween.tween_callback(func():
		visible = false
		modulate.a = 1.0
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		current_fade_tween = null
	)

	return current_fade_tween


func clear_display():
	charater_name_text.text = ""
	text_box.text = ""
	avatar.texture = null


func show_dialogue(character_name: String, content: String):
	charater_name_text.text = character_name
	current_dialogue_content = content
	
	if typing_tween and typing_tween.is_running():
		typing_tween.kill()
	
	typing_tween = get_tree().create_tween()
	text_box.text = "\t"
	
	var i := 0
	var pass_flag := false
	var content_len := content.length()
	
	while i < content_len:
		# 处理转义 '\'
		if content[i] == "\\":
			pass_flag = true
			i += 1
			continue
		
		if not pass_flag and content[i] == "[":
			var end_pos := content.find("]", i)
			if end_pos != -1:
				var tag = content.substr(i, end_pos - i + 1)
				i = end_pos + 1
				typing_tween.tween_callback(func(): text_box.text += tag)
				typing_tween.tween_interval(0.001)
				continue
		
		typing_tween.tween_interval(Global.text_interval)
		typing_tween.tween_callback(func(): text_box.text += content[i])
		i += 1
		
		if pass_flag:
			pass_flag = false
	
	typing_tween.tween_callback(dialogue_finished.emit)


## 跳过当前打字效果
func skip_typing() -> bool:
	if typing_tween and typing_tween.is_running():
		typing_tween.kill()
		text_box.text = "\t" + current_dialogue_content.replace(r"\[", "[")
		dialogue_finished.emit()
		return true  # 确实执行了跳过
	return false  #并未在打字


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and \
		event.button_index == MOUSE_BUTTON_LEFT and \
		event.is_pressed()) or \
		event.is_action_pressed("ui_accept"):
		forward.emit()
	elif event is InputEventMouseButton and \
		event.button_index == MOUSE_BUTTON_RIGHT and \
		event.is_pressed():
		fast_forward.emit()
