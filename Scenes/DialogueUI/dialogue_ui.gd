class_name DialogueUI
extends Control

@export_group("UI")
@export var charater_name_text: RichTextLabel
@export var text_box: RichTextLabel
@export var avatar: TextureRect

var typing_tween: Tween

var current_fade_tween: Tween

var current_dialogue_content: String

# 当前对话的锚点表（渲染后文本字符串索引 → Instruction），由 StoryManager 经 show_dialogue 注入
var _pending_anchors: Array = []
var _triggered_anchor_idx: int = 0

signal dialogue_finished
signal forward
signal fast_forward
signal anchor_triggered(ins: Instruction)  ## 打字机播放到锚点位置（[pause] 内部消费，不发信号）


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


## 展示对话。content 为 DialogueRenderer.render() 的输出（转义已处理、插值已求值、锚点已剥离）；
## anchors 索引与 content 字符串游标同口径。文本中的 [...] 一律视为 BBCode 标签整体瞬时插入。
func show_dialogue(character_name: String, content: String, anchors: Array = []):
	charater_name_text.text = character_name
	current_dialogue_content = content
	_pending_anchors = anchors
	_triggered_anchor_idx = 0

	if typing_tween and typing_tween.is_running():
		typing_tween.kill()

	typing_tween = get_tree().create_tween()
	text_box.text = "\t"

	var i := 0
	var content_len := content.length()

	while i < content_len:
		# 锚点：到达位置即触发（[pause 秒] 由打字机内部消费为停顿）
		while _triggered_anchor_idx < _pending_anchors.size() and _pending_anchors[_triggered_anchor_idx]["index"] <= i:
			var anchor: Dictionary = _pending_anchors[_triggered_anchor_idx]
			_triggered_anchor_idx += 1
			if anchor["ins"].head == Instruction.Head.WAIT:
				typing_tween.tween_interval(anchor["ins"].params[0])
			else:
				typing_tween.tween_callback(func(): anchor_triggered.emit(anchor["ins"]))

		# BBCode 标签整体瞬时插入
		if content[i] == "[":
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

	typing_tween.tween_callback(dialogue_finished.emit)


## 跳过当前打字效果：显示全文并触发全部未触发锚点
func skip_typing() -> bool:
	if typing_tween and typing_tween.is_running():
		typing_tween.kill()
		text_box.text = "\t" + current_dialogue_content
		while _triggered_anchor_idx < _pending_anchors.size():
			var anchor: Dictionary = _pending_anchors[_triggered_anchor_idx]
			_triggered_anchor_idx += 1
			if anchor["ins"].head != Instruction.Head.WAIT:
				anchor_triggered.emit(anchor["ins"])
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
