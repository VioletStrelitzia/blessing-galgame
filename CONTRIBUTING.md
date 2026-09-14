# 开发流程与提交规范

Blessing Galgame Engine 的协作约定。所有贡献（包括维护者本人）都按此执行。

## 1. Issue 先行与过程文档

仓库只保留**结论**：代码、正式文档（设计/规范/ROADMAP）。过程稿与讨论不进入 git 历史。

- 任何非琐碎改动（新能力、重构、规范变更）**先开 GitHub Issue**：写清问题、动机、期望结果；Issue 是决策记录与讨论的场所；
- 分析、调研、方案对比等**过程文档写在本地 `worknotes/` 文件夹**（已被 `.gitignore` 忽略），命名如 `worknotes/2026-09-14-日志系统重规范化.md`；过程稿不入库、不推送；
- 需要长期保存的结论，应沉淀为 `docs/` 下的正式文档（设计文档/规范/ROADMAP 条目），随 PR 入库——而不是把过程稿直接提交；
- 工作分支与 PR 必须关联 Issue：PR 描述首行写 `Closes #<编号>`，合并后 Issue 自动关闭；
- 琐碎修复（错别字、注释）可直接提 PR，不必开 Issue。

## 2. 分支模型（Trunk-Based Development）

本项目采用**主干开发（TBD）**：`main` 是唯一常驻分支，永远保持可运行。

- **main = 主干**：只接受 PR 合入；CI 绿灯（第 6 节冒烟三命令）是合并前提；
- **工作分支短命**（原则上不超过几天）：`<工作线>/<描述>`，如 `gals/web-editor`、`ui/theme-base`；从 main 切出、回合 main，合入即删；
- **工作线不是分支**：BGalS 脚本线、UI 线、scene 挂载线等长期工作线用 GitHub 标签（`line/gals`、`line/ui`、`line/scene-mount`）与 ROADMAP 条目跟踪，不开常驻分支；
- **暗着陆纪律**：未完成的功能允许合入 main，但不得接入演示路径（先例：`var`/`scene`/`trans` 指令已注册于解析器而未接运行时）；
- **hotfix**：从 main 切 `hotfix/xxx`，修好后 PR 回 main（CI 绿即可），打修订 tag；
- 明确取消：dev/test 常驻分支、回灌规则、验收批次制——验收职能由预发布 tag 承担（见第 7 节）。

## 3. Commit 规范

采用 Conventional Commits 的中文变体：

```
<type>(<scope>): <中文描述>

（可选）正文：动机、方案、影响面
```

- **type**（英文小写）：`feat`（新能力）/ `fix`（缺陷修复）/ `docs`（纯文档）/ `refactor`（不改变行为的重构）/ `test` / `chore`（构建、杂务）/ `perf`；
- **scope**（可选）：子系统名，取 [docs/日志规范.md](docs/日志规范.md) 第 7 节标签注册表中的值，如 `fix(ResourceManager): …`；
- **描述**：中文、动词开头、一句话说清"做了什么"，不超过 50 字；动机与取舍写在正文；
- **不兼容变更**：在 type 后加 `!` 并在正文说明迁移方式，如 `refactor(log)!: …`；
- 一个提交只做一件事；格式化改动与逻辑改动分开提交。

示例（取自本仓库实际历史风格）：

```
feat: 对角高斯分布式表征 GPT 与 Shakespeare 对照实验配置
fix: 修复 script 资源回退路径的配置键引用
docs(roadmap): 新增 R7 Web 可视化剧本编辑器与 R8 可挂载玩法场景
```

## 4. PR 描述模板

```
Closes #<issue 编号>

## 变更摘要
<做了什么，逐条>

## 验证证据
<第 5 节验收命令的输出/截图>

## 影响面
<不兼容点、需要同步的文档、对使用者的影响>
```

## 5. 文档同步义务

- 修改剧本指令：必须同步三处——`DialogueImporter.INSTRUCTION_MAP`、`Instruction.Head`、`StoryManager._instruction_handlers`，并更新 `GalSGrammar.md`（见 ROADMAP R1）；
- 修改架构或行为：同步 `docs/` 下对应文档；ROADMAP 条目的状态变化即时更新；
- 新增日志标签：先登记到日志规范注册表。

## 6. 验收与测试

合入 main 前必须通过（Godot 4.5.1+）：

```bash
godot --headless --path . --import            # 资源导入无错误
godot --headless --path . --quit-after 120    # 能启动到主菜单
godot --headless --path . -s test/smoke_test.gd   # 冒烟测试 ok=true
```

## 7. 发布

- 语义化版本 tag：`v<主>.<次>.<修订>`；
- 发布流：功能攒够一个可验收集合 → 打 `v0.x-rcN`（GitHub pre-release，供实机验收）→ 验收通过打 `v0.x.0`；不通过回 main 修复后再发下一个 rc；
- 发布前更新 README 的特性清单与 ROADMAP 的状态列。
