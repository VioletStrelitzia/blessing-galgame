class_name Character
extends Node2D
const LOG_TAG := "Character"


@export var sprite2d: Sprite2D

## 角色在屏幕上的归一化坐标 (0.0-1.0)，默认底部中央
var normalized_position: Vector2 = Vector2(0.5, 1.0):
	set = set_normalized_position

signal animation_finished  ## 单个动画步骤完成
signal sequence_finished   ## 整个动画序列完成

# 动画类型
enum AnimationType {
	NONE,
	SETUP,
	SHOW_FADE,
	HIDE_FADE,
	MOVE_TO,
	WAIT,
	CHANGE_TEXTURE
}

# Tween / Timer
var tween: Tween
var timer: Timer

# 动画队列
var animation_list: Array[Array] = []
var current_animation: AnimationType = AnimationType.NONE
var idx: int = 0
var tween_property: NodePath
var tween_final_val: Variant

## 是否正在执行动画序列
var is_busy: bool:
	get:
		return idx < animation_list.size() or current_animation != AnimationType.NONE


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_resized)
	modulate.a = 0.0
	hide()


## 设置纹理和位置
func setup(texture: Texture2D, pos: Vector2) -> void:
	sprite2d.texture = texture
	if texture:
		sprite2d.offset = Vector2(-texture.get_size().x / 2, -texture.get_size().y)
	self.normalized_position = pos
	_on_animation_finished_internal()


func set_normalized_position(value: Vector2) -> void:
	normalized_position = value.clamp(Vector2.ZERO, Vector2.ONE)
	_update_display_position()


func _update_display_position() -> void:
	if not get_viewport(): return
	var screen_size = get_viewport().get_visible_rect().size
	self.position = Vector2(normalized_position.x * screen_size.x, normalized_position.y * screen_size.y)


func _on_viewport_resized() -> void:
	_update_display_position()


## 改变角色纹理
func change_texture(new_texture: Texture2D) -> void:
	if not new_texture: return
	sprite2d.texture = new_texture
	sprite2d.offset = Vector2(-new_texture.get_size().x / 2, -new_texture.get_size().y)
	_on_animation_finished_internal()


## 移动到新位置
func move_to(new_pos: Vector2, duration: float = 1.0) -> void:
	_start_tween("normalized_position", new_pos, duration, AnimationType.MOVE_TO)


## 等待一段时间，duration < 0 时暂停到下一次 play
func wait(duration: float) -> void:
	_stop_current_animation()
	current_animation = AnimationType.WAIT
	
	if duration < 0:
		GalLogger.info(LOG_TAG, "暂停，等待下一个 play 指令")
		return
	
	timer = Timer.new()
	timer.wait_time = duration
	timer.one_shot = true
	timer.timeout.connect(_on_timer_finished)
	add_child(timer)
	timer.start()


## 淡入
func show_fade(duration: float = 1.0) -> void:
	show()
	_start_tween("modulate:a", 1.0, duration, AnimationType.SHOW_FADE)


## 淡出
func hide_fade(duration: float = 1.0) -> void:
	_start_tween("modulate:a", 0.0, duration, AnimationType.HIDE_FADE)


## 开始/继续播放动画序列
func play() -> void:
	if current_animation == AnimationType.NONE and idx < animation_list.size():
		_play_next()


## 跳过并直接应用整组动画的最终状态
func skip_all() -> void:
	if animation_list.is_empty():
		return
	
	GalLogger.debug(LOG_TAG, "跳过整个动画组，瞬间应用最终状态")

	# 停止当前动画
	_stop_current_animation()

	# 当前动画应用最终状态
	_apply_final_state_of_current_animation()

	# 剩余步骤应用最终状态
	while idx < animation_list.size():
		var current_step = animation_list[idx]
		idx += 1

		if current_step.is_empty():
			continue
			
		var command = current_step[0]
		var args: Array = current_step.slice(1)

		# 不创建 Tween/Timer，也不发 animation_finished
		match command:
			AnimationType.SETUP:
				# 直接套用 setup 结果
				sprite2d.texture = args[0]
				if args[0]:
					sprite2d.offset = Vector2(-args[0].get_size().x / 2, -args[0].get_size().y)
				self.normalized_position = args[1]
			AnimationType.CHANGE_TEXTURE:
				# 直接套用 change_texture 结果
				var new_texture = args[0]
				if new_texture:
					sprite2d.texture = new_texture
					sprite2d.offset = Vector2(-new_texture.get_size().x / 2, -new_texture.get_size().y)
			AnimationType.SHOW_FADE:
				modulate.a = 1.0
				show()
			AnimationType.HIDE_FADE:
				modulate.a = 0.0
				hide()
			AnimationType.MOVE_TO:
				self.normalized_position = args[0]
			AnimationType.WAIT:
				pass
			_:
				GalLogger.error(LOG_TAG, "不支持的动画步类型: " + command)

	# 全部处理完，重置并发信号
	reset()
	sequence_finished.emit()


## 应用当前动画的最终状态
func _apply_final_state_of_current_animation() -> void:
	match current_animation:
		AnimationType.SHOW_FADE:
			modulate.a = 1.0
			show()
		AnimationType.HIDE_FADE:
			modulate.a = 0.0
			hide()
		AnimationType.MOVE_TO:
			if tween_property and tween_final_val:
				self.set_indexed(tween_property, tween_final_val)
		_: pass


## 重置状态，可选清空纹理
func reset(list: Array[Array] = [], clear_texture: bool = false) -> void:
	GalLogger.debug(LOG_TAG, "重置状态")
	_stop_current_animation()
	animation_list = list
	idx = 0
	current_animation = AnimationType.NONE
	if clear_texture:
		sprite2d.texture = null


func _start_tween(property: NodePath, final_val: Variant, duration: float, anim_type: AnimationType) -> void:
	_stop_current_animation()
	
	current_animation = anim_type
	tween_property = property
	tween_final_val = final_val
	
	tween = create_tween()
	tween.finished.connect(_on_tween_finished)
	tween.tween_property(self, property, final_val, duration)

func _stop_current_animation() -> void:
	if tween and tween.is_running():
		if tween.finished.is_connected(_on_tween_finished):
			tween.finished.disconnect(_on_tween_finished)
		tween.kill()
	if timer:
		timer.timeout.disconnect(_on_timer_finished)
		timer.queue_free()
		timer = null


func _on_animation_finished_internal() -> void:
	match current_animation:
		AnimationType.HIDE_FADE: hide()
		_: pass
	
	current_animation = AnimationType.NONE
	animation_finished.emit()
	_play_next()

func _on_tween_finished() -> void:
	_on_animation_finished_internal()

func _on_timer_finished() -> void:
	if timer:
		timer.timeout.disconnect(_on_timer_finished)
		timer.queue_free()
		timer = null
	_on_animation_finished_internal()


## 跳过当前动画
func skip_animation() -> void:
	if animation_list.is_empty():
		return
	
	GalLogger.debug(LOG_TAG, "跳过动画步: %s" % AnimationType.keys()[current_animation])
	
	match current_animation:
		AnimationType.WAIT:
			if not timer:
				current_animation = AnimationType.NONE
				_play_next()
				return
		AnimationType.HIDE_FADE:
			modulate.a = 0.0
			hide()
		AnimationType.NONE:
			_play_next()
			return
		_:
			if tween and tween_property and tween_final_val:
				self.set_indexed(tween_property, tween_final_val)
	
	_stop_current_animation()
	_on_animation_finished_internal()


func _play_next() -> void:
	if idx >= animation_list.size():
		GalLogger.info(LOG_TAG, "动画组播放完毕")
		reset()
		sequence_finished.emit()
		return
	
	var current_step = animation_list[idx]
	idx += 1
	
	if current_step.is_empty():
		_play_next()
		return
		
	var command = current_step[0]
	var args: Array = current_step.slice(1)
	
	GalLogger.debug(LOG_TAG, "播放动画步 " + str(idx) +
			"：" + AnimationType.keys()[command] + "，参数为：" + str(args))
	
	match command:
		AnimationType.SETUP:
			setup(args[0], args[1])
		AnimationType.WAIT:
			wait(args[0])
		AnimationType.SHOW_FADE: show_fade(args[0])
		AnimationType.HIDE_FADE: hide_fade(args[0])
		AnimationType.MOVE_TO: move_to(args[0], args[1])
		AnimationType.CHANGE_TEXTURE: change_texture(args[0])
		_: GalLogger.error(LOG_TAG, "不支持的动画步类型: " + command)


func _to_string() -> String:
	var header = "[%s:%d]" % [get_class(), get_instance_id()]
	var anim_name = "Idle"
	if current_animation != AnimationType.NONE:
		anim_name = AnimationType.keys()[current_animation]
	var progress = "(Step %d/%d)" % [idx, animation_list.size()]
	var texture_name = "null"
	if sprite2d and sprite2d.texture:
		texture_name = sprite2d.texture.resource_path.get_file()
	var pos_str = "(%.2f, %.2f)" % [normalized_position.x, normalized_position.y]
	var alpha_str = "%.2f" % modulate.a
	var output = "\n".join(PackedStringArray([
		header,
		"  State: %s %s" % [anim_name, progress],
		"  Texture: %s" % texture_name,
		"  Position(Normalized): %s" % pos_str,
		"  Alpha: %s" % alpha_str
	]))
	return output
