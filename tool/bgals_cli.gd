extends SceneTree

## BGalS 编译 CLI。用法：
##   godot --headless --path . -s tool/bgals_cli.gd -- check   --src <文件|目录> --out report.json
##   godot --headless --path . -s tool/bgals_cli.gd -- compile [--report report.json]
##   godot --headless --path . -s tool/bgals_cli.gd -- dump    --src <tres 路径> --out graph.json
##   godot --headless --path . -s tool/bgals_cli.gd -- spec    --out spec.json
##   godot --headless --path . -s tool/bgals_cli.gd -- overview --out overview.json
## 退出码：0 成功；1 诊断含 error；2 用法/IO 错误；3 产物 compiler 版本不匹配。

const LOG_TAG := "BgalsCLI"

const USAGE := """BGalS 编译 CLI。用法：
  godot --headless --path . -s tool/bgals_cli.gd -- check   --src <文件|目录> --out report.json
  godot --headless --path . -s tool/bgals_cli.gd -- compile [--report report.json]
  godot --headless --path . -s tool/bgals_cli.gd -- dump    --src <tres 路径> --out graph.json
  godot --headless --path . -s tool/bgals_cli.gd -- spec    --out spec.json
  godot --headless --path . -s tool/bgals_cli.gd -- overview --out overview.json
退出码：0 成功；1 诊断含 error；2 用法/IO 错误；3 产物 compiler 版本不匹配。"""

var G   # Global（-s 模式下 autoload 标识符编译期不可见，Variant 动态访问）
var RM  # ResourceManager


func _initialize() -> void:
	G = root.get_node("Global")
	RM = root.get_node("ResourceManager")
	call_deferred("_run")


func _run() -> void:
	# 等 autoload _ready 全部跑完（Global.config 加载、ResourceManager 登记表就绪）
	await process_frame
	await process_frame

	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		_print_usage()
		quit(2)
		return
	var cmd := args[0]
	var opts := {}
	var i := 1
	while i < args.size():
		if args[i].begins_with("--") and i + 1 < args.size():
			opts[args[i].substr(2)] = args[i + 1]
			i += 2
		else:
			i += 1

	match cmd:
		"check":
			_cmd_check(opts)
		"compile":
			_cmd_compile(opts)
		"dump":
			_cmd_dump(opts)
		"spec":
			_cmd_spec(opts)
		"overview":
			_cmd_overview(opts)
		_:
			_print_usage()
			quit(2)


# --- 子命令 ---

## check：逐文件 parse_script（不写产物），汇总诊断写 --out
func _cmd_check(opts: Dictionary) -> void:
	var src: String = opts.get("src", "")
	var out: String = opts.get("out", "")
	if src.is_empty() or out.is_empty():
		_print_usage()
		quit(2)
		return
	src = _fs_path(src)

	var files: Array[String] = []
	if DirAccess.dir_exists_absolute(src):
		for f in Utils.get_file_list(src, true, true):
			if f.ends_with(".txt"):
				files.append(f)
	elif FileAccess.file_exists(src):
		files.append(src)
	else:
		GalLogger.error(LOG_TAG, "--src 不存在: " + src)
		_done(false, 1, 0, 2)
		return

	# 跨文件校验上下文始终为 read_dir 全量扫描（与编辑器内编译同口径）
	var known_scripts := DialogueImporter.scan_script_names(_read_dir())
	var char_max := _char_max()
	var known_refs: Dictionary = RM.get_known_refs()
	var report := {"ok": true, "files": [] as Array, "diags": [] as Array}
	for text_path in files:
		var file := Utils.open_file(text_path, FileAccess.READ)
		if not file:
			report["diags"].append({"file": text_path, "line": 0, "level": "error", "msg": "无法打开文件"})
			report["files"].append({"file": text_path, "status": "error"})
			continue
		var text := file.get_as_text()
		file.close()
		var diags: Array[Dictionary] = []
		DialogueImporter.parse_script(text.split("\n"), text_path, diags, known_scripts, char_max, known_refs)
		report["diags"].append_array(diags)
		report["files"].append({"file": text_path, "status": "error" if DialogueImporter._has_error(diags) else "ok"})

	var errors := _count_level(report["diags"], "error")
	var warnings := _count_level(report["diags"], "warning")
	report["ok"] = errors == 0
	if not _write_json(out, report):
		_done(false, errors, warnings, 2)
		return
	_done(report["ok"], errors, warnings)


## compile：与编辑器内编译同一管线（compile_all 含增量与版本盐），report 可选
func _cmd_compile(opts: Dictionary) -> void:
	var report := DialogueImporter.compile_all(_read_dir(), _save_dir(), _char_max(), RM.get_known_refs())
	var errors := _count_level(report["diags"], "error")
	var warnings := _count_level(report["diags"], "warning")
	if opts.has("report"):
		if not _write_json(opts["report"], report):
			_done(false, errors, warnings, 2)
			return
	_done(report["ok"], errors, warnings)


## dump：产物 tres → 图 JSON。compiler 版本不符退 3（提示编辑器重新同步版本）
func _cmd_dump(opts: Dictionary) -> void:
	var src: String = opts.get("src", "")
	var out: String = opts.get("out", "")
	if src.is_empty() or out.is_empty():
		_print_usage()
		quit(2)
		return
	var path := _fs_path(src)
	if not ResourceLoader.exists(path):
		GalLogger.error(LOG_TAG, "产物不存在: " + path)
		_done(false, 1, 0, 2)
		return
	var res := ResourceLoader.load(path)
	if not (res is GalEventItemSequence):
		GalLogger.error(LOG_TAG, "不是 GalEventItemSequence 产物: " + path)
		_done(false, 1, 0, 2)
		return
	if res.compiler != DialogueImporter.COMPILER_VERSION:
		GalLogger.error(LOG_TAG, "产物 compiler 版本不符（%s，需要 %s），请重新 compile: %s" % [
			res.compiler, DialogueImporter.COMPILER_VERSION, path])
		_done(false, 1, 0, 3)
		return
	var graph := GraphDumper.build(res, path.get_file().get_basename())
	if not _write_json(out, graph):
		_done(false, 0, 0, 2)
		return
	_done(true, 0, 0)


## spec：指令名表与参数规格（前端零硬编码的数据源）
func _cmd_spec(opts: Dictionary) -> void:
	var out: String = opts.get("out", "")
	if out.is_empty():
		_print_usage()
		quit(2)
		return
	if not _write_json(out, GraphDumper.build_spec()):
		_done(false, 0, 0, 2)
		return
	_done(true, 0, 0)


## overview：扫描产物目录全部 tres，dump 成图后汇总剧本宏观关系（jump 连接 + 节点统计）。
## 陈旧产物（compiler 不符）跳过并计 warning，不阻塞整体输出。
func _cmd_overview(opts: Dictionary) -> void:
	var out: String = opts.get("out", "")
	if out.is_empty():
		_print_usage()
		quit(2)
		return
	var save_dir := _save_dir()
	var graphs: Array[Dictionary] = []
	var warnings := 0
	for file_name in Utils.get_file_list(save_dir, false, false):
		if not file_name.ends_with(".tres"):
			continue
		var path := save_dir.path_join(file_name)
		var res := ResourceLoader.load(path)
		if not (res is GalEventItemSequence):
			continue
		if res.compiler != DialogueImporter.COMPILER_VERSION:
			GalLogger.warn(LOG_TAG, "产物 compiler 不符，已跳过（请重新 compile）: " + path)
			warnings += 1
			continue
		graphs.append(GraphDumper.build(res, file_name.get_basename()))
	var begin: String = G.config.get("begin_script", "")
	if not _write_json(out, GraphDumper.build_overview(graphs, begin)):
		_done(false, 0, warnings, 2)
		return
	_done(true, 0, warnings)


# --- 装配与输出 ---

func _read_dir() -> String:
	return "res://".path_join(G.config["scripts"]["read_dir"])


func _save_dir() -> String:
	return "res://".path_join(G.config["scripts"]["save_dir"])


## char 实例上限（JSON 数值读入为 float，需转 int；缺省 -1 不校验）
func _char_max() -> int:
	return int(G.config.get("character", {}).get("max", -1))


## 路径归一：res://user:// 与系统绝对路径原样，其余按项目相对路径补 res:// 前缀
static func _fs_path(p: String) -> String:
	if p.is_absolute_path() or p.begins_with("/") or p.begins_with("\\"):
		return p
	return "res://" + p


static func _count_level(diags: Array, level: String) -> int:
	var n := 0
	for d in diags:
		if d["level"] == level:
			n += 1
	return n


static func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(_fs_path(path), FileAccess.WRITE)
	if file == null:
		GalLogger.error(LOG_TAG, "无法写入文件: " + path)
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return true


static func _print_usage() -> void:
	print(USAGE)


## stdout 只打一行状态（规避 Windows 控制台编码与大 JSON 截断）；code < 0 时按 ok 折算 0/1
func _done(ok: bool, errors: int, warnings: int, code := -1) -> void:
	if code < 0:
		code = 0 if ok else 1
	print("BGALS_CLI_DONE ok=%s errors=%d warnings=%d" % [ok, errors, warnings])
	quit(code)
