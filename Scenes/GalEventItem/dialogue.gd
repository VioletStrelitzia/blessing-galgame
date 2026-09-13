class_name DialogueItem extends GalEventItem

@export var character: String = ""
@export var dialogue: String = ""

func _init(character_: String = "", dialogue_: String = "") -> void:
	character = character_
	dialogue = dialogue_


func _to_string() -> String:
	if character.is_empty():
		return "[DialogueItem] " + dialogue
	else:
		return "[DialogueItem] " + character + ": " + dialogue
