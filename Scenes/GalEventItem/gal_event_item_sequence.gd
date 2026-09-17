class_name GalEventItemSequence extends Resource

## BGalS 编译产物。compiler 为编译器版本标记（DialogueImporter.COMPILER_VERSION），
## 加载时校验，防止 scripts.check=false 的模组模式反序列化陈旧产物（枚举按整数存储会错位）。

@export var compiler: String = ""
@export var seq: Array[GalEventItem] = []

func len() -> int:
	return len(seq)
