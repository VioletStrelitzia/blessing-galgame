# 开发流程与提交规范

Blessing Galgame Engine 的协作约定。所有贡献（包括维护者本人）都按此执行。

## 1. 分支模型

- `main`：主干，始终保持可运行状态（冒烟测试通过）；**禁止直接向 main 提交**；
- 工作分支命名：`<type>/<简短英文描述>`，如 `feat/web-editor`、`fix/save-replay`；`type` 与提交类型一致（见下）；
- 合并走 PR：即使是个人项目，也要求自己产出 PR 式 diff、自审（或请合作者审）通过后再合并；合并后删除分支。

## 2. Commit 规范

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

## 3. 文档同步义务

- 修改剧本指令：必须同步三处——`DialogueImporter.INSTRUCTION_MAP`、`Instruction.Head`、`StoryManager._instruction_handlers`，并更新 `GalSGrammar.md`（见 ROADMAP R1）；
- 修改架构或行为：同步 `docs/` 下对应文档；ROADMAP 条目的状态变化即时更新；
- 新增日志标签：先登记到日志规范注册表。

## 4. 验收与测试

合入 main 前必须通过（Godot 4.5.1+）：

```bash
godot --headless --path . --import            # 资源导入无错误
godot --headless --path . --quit-after 120    # 能启动到主菜单
godot --headless --path . -s test/smoke_test.gd   # 冒烟测试 ok=true
```

## 5. 发布

- 语义化版本 tag：`v<主>.<次>.<修订>`，功能集齐了打次版本，修复打修订号；
- 发布前更新 README 的特性清单与 ROADMAP 的状态列。
