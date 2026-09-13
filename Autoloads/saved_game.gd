class_name SavedGame extends Resource

@export var vars: Dictionary[String, float] = {}  ## 剧本变量
@export var script_name: String = ""  ## 对应脚本名
@export var idx: int = 0  ## 当前执行到的行号
@export var execution_stack: Array[bool] = []  ## 逻辑流状态栈
@export var timestamp: String = ""  ## 时间戳（排序用）
@export var title: String = ""  ## 存档标题
@export var thumbnail_path: String = ""  ## 缩略图路径
