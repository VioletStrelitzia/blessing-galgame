# Blessing Galgame Engine（布雷辛格）

基于 **Godot 4.5** 的混合视觉小说引擎。核心理念是**资源与引擎完全解耦**：编剧只需按照 BGalS 语法编写纯文本剧本、在索引文件里登记资源，无需改动任何引擎代码，即可运行一部视觉小说。

## 特性

- **BGalS 对话块 DSL**：行式剧本文本，`<` 前指令 / `>` 后指令 / 独立指令三时机以对话为中心组织演出；缩进块表达选项与条件分支，无收尾标记；支持 `{var}` 插值、文本内联锚点、条件选项、跨脚本跳转；编译期行号级诊断。完整规范见 [GalSGrammar.md](GalSGrammar.md)。
- **流式状态机解释器**：剧本编译为事件序列后由 `StoryManager` 流式执行，`IterateMode`（默认/后指令）× `ManagerMode`（交互/自动/跳过/停止）两维正交状态机管理推进节奏。
- **检查点 + 确定性重放式存档**：存档只记录脚本名、执行索引、变量与随机种子（`SavedGame` .tres 资源）；读档时复位种子、以 SKIP 模式重放到存档点，自动重建背景、立绘、音乐等现场且随机序列不漂移。存档自带截图缩略图与版本校验。
- **资源键名索引**：`index.json` 维护「引用名 → 路径」映射，剧本只写引用名，素材替换不改剧本。
- **模组 PCK 加载**：启动时扫描可执行文件旁 `mods/` 目录，按 `mod.json`（`name` / `pck_file` / `priority`）声明的优先级加载 Godot 资源包。
- **剧本热编译**：启动时按 SHA256 哈希 + 编译器版本盐增量编译 `scripts/` 中的文本剧本到 `GalSs/`，只重编译有改动的文件。
- **场景与转场指令**：`scene mount/unmount` 剧本直挂场景（淡入淡出 + 池复用），`trans in/out` 全屏转场可挂起剧情。
- **音频系统**：Master/Music/SFX/Voice 四总线；BGM 双播放器交叉淡变（时长可由剧本控制）；SFX 播放器池。
- **立绘动画序列**：`char <实例> setup/show/hide/move/texture/wait` 直挂实例、入队自动播放，跨实例连写天然并行，`wait:true` 可挂起剧情；底部中心锚点 + 归一化坐标，自动适配分辨率。
- **场景池化**：`SceneManager` 以 pool/mounted 双结构管理 UI 与世界场景，常驻场景卸载不释放，切换零磁盘 I/O。
- **游戏内 UI**：打字机对话框（支持 BBCode）、自动/跳过模式、存档/读档界面、设置界面（四路音量、文字速度、自动等待）、Toast 消息、启动画面与淡入淡出转场。
- **配置驱动**：`config.json` 控制起始幕、资源目录、主菜单素材、初始音量、角色实例上限、存档目录等。
- **可视化剧本编辑器**：`editor/` 内置 Web 端节点图编辑器（React Flow）：宏观剧本关系图 + 微观节点编辑、双击行内编辑、保存即编译、诊断定位到节点、图文回环校验；配套无头 CLI（`tool/bgals_cli.gd`，check/compile/dump/spec/overview 五子命令）供 CI 与编辑器复用。设计见 [docs/可视化编辑器与编译管线设计.md](docs/可视化编辑器与编译管线设计.md)。

## 运行要求

- **Godot 4.5 或更高版本**（开发验证版本：4.5.1；渲染：GL Compatibility）
- 仓库自带最小演示素材（占位立绘、自生成 BGM、演示背景），开箱即可运行。

## 快速开始

1. 克隆本仓库（`blessing-galgame`）。
2. 打开 Godot 项目管理器，导入仓库根目录的 `project.godot`。
3. 直接运行（F5）：启动画面 → 主菜单 → 点击「开始」进入演示剧本。
4. 演示剧本位于 `scripts/demo/scene1.txt`、`scripts/demo/scene2.txt`；启动时自动编译为 `GalSs/demo_scene1.tres` 等资源（`config.json` 中 `scripts.check = true` 时按哈希增量更新）。
5. 无头测试（编译产物结构断言 + 编译期诊断断言）：

   ```bash
   godot --headless --path . -s test/smoke_test.gd
   godot --headless --path . -s test/diagnostics_test.gd
   ```

想写自己的剧本：在 `scripts/` 下新建 `.txt`，按 [GalSGrammar.md](GalSGrammar.md) 的语法编写，在 `index.json` 登记素材引用名，再把 `config.json` 的 `begin_script` 指向你的剧本名（如 `scripts/demo/scene1.txt` 对应 `demo_scene1`）。

导出 Windows 构建：先运行一次编辑器生成 `GalSs/`，再 `godot --headless --path . --export-release "Windows Desktop"`，产物在 `build/`。存档/日志/配置的落点与降级规则见 [docs/路径策略设计.md](docs/路径策略设计.md)。

可视化编辑剧本：`cd editor && npm install && npm run dev:server`（离线 fixtures 模式），或设 `BGALS_GODOT`/`BGALS_PROJECT` 后 `npx tsx server/index.ts` 直连引擎（可写），浏览器打开 `http://localhost:8787`。命令行检查剧本：`godot --headless --path . -s tool/bgals_cli.gd -- check --src scripts --out report.json`。

## 目录结构

| 路径 | 说明 |
| --- | --- |
| `Autoloads/` | 全局服务（配置、资源、音频、场景、剧情、存档、消息） |
| `Scenes/` | 场景与 UI（主场景、主菜单、对话 UI、立绘世界层、存档/设置界面等） |
| `scripts/` | BGalS 文本剧本（源文件） |
| `GalSs/` | 剧本编译产物（`.tres`；已入 .gitignore，首次运行自动生成） |
| `Resources/` | 图片、音频等资源（当前为演示占位素材） |
| `docs/` | 设计与分析文档（索引见 `docs/README.md`） |
| `test/` | 冒烟测试脚本与模组元数据示例 |
| `tool/` | 无头 CLI（`bgals_cli.gd`：剧本检查/编译/图转储/指令规格/宏观关系） |
| `editor/` | Web 可视化剧本编辑器（独立工具链，Godot 经 `.gdignore` 跳过；用法见 `editor/README.md`） |
| `config.json` | 引擎配置 |
| `index.json` | 资源引用名 → 路径映射 |
| `GalSGrammar.md` | BGalS 剧本语言规范 |
| `ROADMAP.md` | 开发路线图 |

## 文档

- [GalSGrammar.md](GalSGrammar.md) —— 剧本语言规范（编剧向）
- [ROADMAP.md](ROADMAP.md) —— 路线图与待实现能力
- [CONTRIBUTING.md](CONTRIBUTING.md) —— 开发流程与规范（参与开发必读）
- [docs/README.md](docs/README.md) —— 文档索引（规范、设计、分析）

## License

[MIT](LICENSE) © Blessing Galgame Engine contributors
