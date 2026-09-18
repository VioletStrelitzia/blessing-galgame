class_name PrevInstruction extends Instruction


func _init(head_: Head = Head.BLANK, typed: Array = []) -> void:
	super._init(head_, typed)


## 字符串参数构造（测试辅助路径）：按 spec 类型转型
static func from_strings(head_: Head, args: Array[String]) -> PrevInstruction:
	return _from_strings_into(PrevInstruction.new(), head_, args)


func _to_string() -> String:
	var parent_str := super._to_string()
	return parent_str.replace("[Instruction] ", "[PrevInstruction] ")
