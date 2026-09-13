class_name PrevInstruction extends Instruction


func _init(head_: Head = Head.BLANK, params_: Array[String] = []) -> void:
	super._init(head_, params_)


func _to_string() -> String:
	var parent_str := super._to_string()
	return parent_str.replace("[Instruction] ", "[PrevInstruction] ")
