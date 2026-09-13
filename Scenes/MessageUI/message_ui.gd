extends Control

const NOTIFICATION_ITEM = preload("res://Scenes/MessageUI/message_item.tscn")

@onready var container = $VBoxContainer

func _ready():
	MessageManager.toast_requested.connect(_on_toast_requested)


func _on_toast_requested(text: String, type: String):
	var item = NOTIFICATION_ITEM.instantiate()
	container.add_child(item)
	item.setup(text, type)
	
