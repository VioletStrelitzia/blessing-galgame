class_name SavedGame extends Resource

## 存档格式版本：1 = v1 旧档（无版本字段时按 1 处理）；2 = BGalS v2。
## 注意：默认值必须保持 1（旧档无此字段时取脚本默认值；ResourceSaver 只存非默认值），
## 新档在 save_manager.save_game 中显式赋值 CURRENT_VERSION。

const CURRENT_VERSION := 2

@export var version: int = 1  ## 存档格式版本
@export var vars: Dictionary[String, float] = {}  ## 剧本变量
@export var script_name: String = ""  ## 对应脚本名
@export var idx: int = 0  ## 当前执行到的行号
@export var rng_seed: int = 0  ## 存档时刻的随机种子（v2，读档重放前复位以保证确定性）
@export var timestamp: String = ""  ## 时间戳（排序用）
@export var title: String = ""  ## 存档标题
@export var thumbnail_path: String = ""  ## 缩略图路径
