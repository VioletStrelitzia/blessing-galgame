extends Node
const LOG_TAG := "Sync"

## 剧情推进同步器：挂起注册表 + 优先级抢占 + 推进门闸 + 模式机。
## 本类不认识任何组件类型，只认挂起凭证（id）；挂起类别经 register_kind 注册（开放扩展）。
##
## 房规（行为与重构前现状一致，此处形式化）：
## - SKIP 中非免疫类别的挂起不产生（acquire 短路返回 INVALID）；
## - 玩家点击可打断一切可打断挂起（request_advance(true) 先 preempt(PRIO_CLICK)）；
## - 自动推进（AUTO/SKIP 计时）必须等门闸挂起清空。
##
## 依赖图预留：hold 带 deps（仅可引用更早的 id——id 单调递增，天然无环 DAG）。
## 挂起在「自身 resolved 且全部 deps 已清空」前视为未决；resolved 的挂起在 deps 清空时级联移除。

enum Mode { INTERACT, AUTO, SKIP, STOP }

## 处置方式：直达执行完毕态 / 凭证作废效果后台自然完成 / 直接终止。
## 「保持」不是处置——抢占事件优先级低于类别阈值即自然存活，无需枚举。
enum Disposition { FAST_FORWARD, RELEASE_ASYNC, KILL }

const INVALID := -1

# 抢占事件优先级（数值即权限；新事件选一个数即可，无需改本类）
const PRIO_CLICK := 10       ## 玩家点击打断回合内挂起
const PRIO_SKIP_ENTER := 20  ## 进入 SKIP
const PRIO_RESET := 100      ## 跳幕/读档/回主菜单

signal mode_changed(mode: Mode)
signal advance_requested()  ## 自动推进放行一次（StoryManager 接；点击路径不经此信号）
signal holds_cleared()      ## 门闸挂起从「有」到「无」的跃迁时发射一次

var mode: Mode = Mode.INTERACT:
	set(value):
		if mode == value:
			return
		mode = value
		# 模式切换作废旧预约计时（重布由 mode_changed 的监听方驱动）
		preempt_kind(&"schedule")
		mode_changed.emit(mode)

# kind -> {threshold, disposition, blocks_loop, blocks_gate, skip_immune}
var _kinds: Dictionary = {}
# id -> {kind, tag, on_fast_forward, on_kill, deps: Array[int], resolved: bool}
var _holds: Dictionary = {}
var _next_id := 0
var _gate_blocked := false  # holds_cleared 只在「被堵 → 清空」跃迁时发射


func _ready() -> void:
	# 内建挂起类别。threshold：被抢占的优先级门槛；blocks_loop：停解释器主循环；
	# blocks_gate：门闸自动推进；skip_immune：SKIP 中仍真实产生挂起。
	register_kind(&"wait", 0, Disposition.KILL)
	register_kind(&"char", PRIO_CLICK, Disposition.FAST_FORWARD)
	register_kind(&"trans", PRIO_CLICK, Disposition.RELEASE_ASYNC)
	register_kind(&"option", PRIO_RESET, Disposition.KILL, true, true, true)
	register_kind(&"voice", PRIO_CLICK, Disposition.KILL, false, true)
	# 内部：预约推进计时（任何抢占/模式切换都作废旧预约；不参与判停与门闸；SKIP 中仍要工作）
	register_kind(&"schedule", 0, Disposition.KILL, false, false, true)
	GalLogger.info(LOG_TAG, "加载完成")


## 注册挂起类别。新逻辑（如挂载玩法）只需 register_kind 一行，引擎零改动：
## register_kind(&"gameplay", PRIO_RESET, Disposition.KILL) —— 点击/SKIP 打不进，跳幕强杀。
func register_kind(kind: StringName, threshold: int, disposition: Disposition, blocks_loop := true, blocks_gate := true, skip_immune := false) -> void:
	_kinds[kind] = {
		"threshold": threshold, "disposition": disposition,
		"blocks_loop": blocks_loop, "blocks_gate": blocks_gate, "skip_immune": skip_immune,
	}


## 登记挂起，返回凭证 id；SKIP 中非免疫类别短路返回 INVALID（调用方按「未挂起」继续）。
## on_fast_forward/on_kill：抢占处置回调（只有持有方知道如何直达终态/终止）。
## deps：依赖图预留（如 barrier = acquire(..., deps=[a, b])，a、b 清空时 barrier 自动清空）。
func acquire(kind: StringName, tag: Variant = null, on_fast_forward := Callable(), on_kill := Callable(), deps: Array[int] = []) -> int:
	if not _kinds.has(kind):
		GalLogger.error(LOG_TAG, "未注册的挂起类别: " + kind)
		return INVALID
	var spec: Dictionary = _kinds[kind]
	if mode == Mode.SKIP and not spec["skip_immune"]:
		return INVALID
	# 已清空的依赖视为已满足（静默剔除）；从未存在的 id 记警告
	var live_deps: Array[int] = []
	for d in deps:
		if _holds.has(d):
			live_deps.append(d)
		elif d > _next_id or d <= 0:
			GalLogger.warn(LOG_TAG, "挂起 %s 依赖了不存在的 hold %d，忽略该依赖" % [kind, d])
	_next_id += 1
	var id := _next_id
	_holds[id] = {
		"kind": kind, "tag": tag,
		"on_fast_forward": on_fast_forward, "on_kill": on_kill,
		"deps": live_deps, "resolved": false,
	}
	_update_gate()
	return id


## 标记挂起的事由已发生；deps 未清空时保留凭证，deps 清空时级联移除
func release(id: int) -> void:
	if not _holds.has(id):
		return
	_holds[id]["resolved"] = true
	_cascade()


## 计时挂起：seconds 后自动 release（wait 指令与 AUTO/SKIP 预约共用）
func wait_seconds(seconds: float, kind := &"wait", tag: Variant = null) -> int:
	var id := acquire(kind, tag)
	if id == INVALID:
		return INVALID
	get_tree().create_timer(seconds, false).timeout.connect(
		func(): release(id), CONNECT_ONE_SHOT)
	return id


## 抢占：优先级数 >= 类别阈值的未决挂起按注册处置方式处理并释放；不足的自然存活
func preempt(priority: int) -> void:
	for id in _holds.keys():
		if not _holds.has(id):
			continue
		var hold: Dictionary = _holds[id]
		var spec: Dictionary = _kinds[hold["kind"]]
		if priority < spec["threshold"]:
			continue
		match spec["disposition"]:
			Disposition.FAST_FORWARD:
				if (hold["on_fast_forward"] as Callable).is_valid():
					(hold["on_fast_forward"] as Callable).call()
			Disposition.KILL:
				if (hold["on_kill"] as Callable).is_valid():
					(hold["on_kill"] as Callable).call()
			Disposition.RELEASE_ASYNC:
				pass
		hold["resolved"] = true
	_cascade()


## 按类别强制清空（模式切换作废旧预约计时用）
func preempt_kind(kind: StringName) -> void:
	for id in _holds.keys():
		if _holds[id]["kind"] == kind:
			_holds[id]["resolved"] = true
	_cascade()


## 跳幕/读档/回主菜单：全量抢占 + 回 INTERACT
func reset() -> void:
	preempt(PRIO_RESET)
	mode = Mode.INTERACT


## 推进门闸。from_input=true（点击）：抢占回合内挂起后放行；
## from_input=false（自动）：有门闸挂起则拒绝（调用方等 holds_cleared 重布）
func request_advance(from_input: bool) -> bool:
	if mode == Mode.STOP:
		return false
	if from_input:
		preempt(PRIO_CLICK)
		return true
	return _pending_gate_count() == 0


## 预约一次自动推进：delay 后门闸畅通则发射 advance_requested；被堵则由 holds_cleared 驱动重布
func schedule(delay: float) -> void:
	preempt_kind(&"schedule")
	var id := acquire(&"schedule")
	if id == INVALID:
		return
	get_tree().create_timer(delay, false).timeout.connect(func():
		if not _holds.has(id):
			return  # 已被抢占/复位
		release(id)
		if mode != Mode.STOP and _pending_gate_count() == 0:
			advance_requested.emit()
	, CONNECT_ONE_SHOT)


## 查询面（测试与调试）
func has_kind(kind: StringName) -> bool:
	for id in _holds:
		if _holds[id]["kind"] == kind:
			return true
	return false


## 存在停主循环的未决挂起
func has_blocking() -> bool:
	for id in _holds:
		if _kinds[_holds[id]["kind"]]["blocks_loop"]:
			return true
	return false


## 无门闸挂起
func is_clear() -> bool:
	return _pending_gate_count() == 0


func _pending_gate_count() -> int:
	var n := 0
	for id in _holds:
		if _kinds[_holds[id]["kind"]]["blocks_gate"]:
			n += 1
	return n


## 收敛：resolved 且 deps 全清空的挂起移除（可级联），随后维护门闸跃迁信号
func _cascade() -> void:
	var changed := true
	while changed:
		changed = false
		for id in _holds.keys():
			var hold: Dictionary = _holds[id]
			if not hold["resolved"]:
				continue
			var deps_done := true
			for d in hold["deps"]:
				if _holds.has(d):
					deps_done = false
					break
			if deps_done:
				_holds.erase(id)
				changed = true
	_update_gate()


func _update_gate() -> void:
	var blocked := _pending_gate_count() > 0
	if blocked:
		_gate_blocked = true
	elif _gate_blocked:
		_gate_blocked = false
		holds_cleared.emit()
