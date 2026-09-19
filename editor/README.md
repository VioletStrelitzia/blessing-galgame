# BGalS 可视化剧本编辑器（M2：编辑 UI）

面向编剧的 Web 可视化剧本编辑器。本目录为单包前端工程：Vite + React + TypeScript 前端、
Hono 本地伴随服务、以及 web/server 共用的纯 TS 层（`shared/`）。设计文档见
`docs/可视化编辑器与编译管线设计.md`。

## 目录结构

```
editor/
├── public/fixtures/        # 真实 CLI 产出的离线数据（spec / graphs / check / refs 样例）
├── shared/                 # 纯 TS，web 与 server 共用
│   ├── graph.ts            #   bgals-graph/1 图 JSON 类型 + STRUCTURAL_HEADS（结构头排除集）
│   ├── spec.ts             #   spec.json 类型
│   ├── check.ts            #   check 报告类型 + file→剧本名换算
│   ├── graph_ops.ts(+test) #   图编辑纯函数（插入/删除/槽编辑/分支编辑，唯一变更入口）
│   ├── graph_branch.ts     #   选项组/条件链操作与工厂
│   ├── graph_comment.ts    #   注释节点操作
│   ├── emit.ts(+test)      #   图 → BGalS 文本发射器（EmitResult{text, lineMap}）
│   ├── compare.ts(+test)   #   semanticEqual 语义对比（回环校验核心）
│   └── sidecar.ts(+test)   #   sidecar（布局+注释）buildSidecar/applySidecar/contentHash
├── server/                 # Hono 伴随服务（:8787）
│   ├── index.ts            #   /api/* 路由 + 生产模式托管 dist
│   ├── dev.ts              #   /api/dev/* 调试桥（--dev 或 BGALS_DEV=1）
│   ├── fixtures.ts         #   fixtures 模式数据源（只读）
│   └── godot.ts            #   live 模式：spawn 引擎 CLI，临时文件读回 JSON
└── src/                    # React 前端
    ├── state/              #   zustand store（mutateGraph 唯一变更入口）+ io（载入/保存/检查/校验）+ edit（编辑动作层）
    ├── graph/              #   collapse 聚合 / toFlow 投影 / dagre 布局补位 / kindColor 语义色 / 自定义节点与 seq 边 / FlowCanvas
    ├── panels/             #   剧本列表 / 可编辑 Inspector（含 InstParamsForm、SlotEditor、BranchEditors）/ 诊断
    ├── components/         #   工具栏 / 插入菜单 / 回环校验横幅 / 统一表单控件 / TailText 尾部截断
    └── dev/bridge.ts       #   调试桥客户端（SSE 收命令 → 注册表执行 → 回传结果）
```

## 启动

```bash
npm install

# 模式一：fixtures 离线开发（无需 Godot，数据来自 public/fixtures/，只读）
npm run dev:server -- --fixtures            # 伴随服务 :8787
npm run dev                                 # 前端 :5173（/api 代理到 8787）
npm run dev:server -- --fixtures --dev      # 附加 /api/dev/* 调试桥

# 模式二：live 连引擎（BGALS_GODOT 必填；BGALS_PROJECT 默认本目录上溯一级）
export BGALS_GODOT=/path/to/godot
npm run dev:server

# 生产：构建后由伴随服务直接托管（live 模式且 dist 存在时）
npm run build && npm run dev:server
```

## M2 编辑功能

- **载入流**：选剧本 → 并行 GET graph + sidecar（404 容忍）→ applySidecar 还原布局与注释节点
  → 有位置的直接用，缺位节点先挂前驱下方、孤立节点 dagre 补位 → 渲染。
- **编辑交互**：
  - seq 边 hover 显示「+」→ 弹出插入菜单（对话/指令/选项组/条件；指令需二级选 head，
    候选为 spec.heads 排除 `STRUCTURAL_HEADS`）→ `insertOnEdge`。
  - 工具栏（画布上方）：末尾追加（追加跳转等终端节点走这里）、新建剧本（fixtures 禁用）、
    注释（有选中节点时 `addComment(before=选中节点)`，否则 `before=null` 文件头）、
    保存（Ctrl+S）、撤销/重做（Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y）、检查、回环校验；dirty 指示点。
  - Delete/Backspace 或 Inspector 按钮删除节点（组/条件自动收子图，start/end 除外）。
  - 拖动节点实时更新位置（位置独立存放，不进撤销栈，但参与 dirty 判定）。
  - **双击行内编辑**（dialogue 角色+台词 / comment 文本，共用 `components/inlineEdit.ts` 的
    `useInlineEdit`）：Enter 提交、Shift+Enter 换行、Esc 取消还原、失焦提交；
    提交走 `patchDialogue`/`patchComment`（与 Inspector 同一 store action，撤销/dirty 链路一致）；
    编辑态 nodrag、画布 `zoomOnDoubleClick` 已关闭；聚合组摘要不可行内编辑（点击仍展开）。
- **视口**：剧本载入/切换后等全部节点测量完成（rAF 轮询）再 `fitView(padding 0.2)`；
  插入/追加的新节点、诊断定位、select_node 均经 focusReq → setCenter 滚入视野。
- **聚合视图**（纯视图层，不动领域图）：同 kind（dialogue/inst）连续 seq 链长度 ≥ 4 折叠为
  group 节点（胶囊标签 `DIALOGUE ×12` + 首 2 尾 1 摘要 + 「展开其余 N 条」）；带诊断/选中节点
  强制可见；展开链首节点左上角有「收起」按钮；触及组的合成边不显示「+」。expandedGroups 随剧本切换清空。
  展开时成员从组当前位置垂直堆叠（间距 130，`stackPositions`），收起回到堆叠起点，几何稳定。

## 快捷键

| 键                             | 行为                                                                            |
| ------------------------------ | ------------------------------------------------------------------------------- |
| Ctrl+S                         | 保存                                                                            |
| Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y | 撤销 / 重做                                                                     |
| Delete / Backspace             | 删除选中节点                                                                    |
| ArrowDown / ArrowUp            | 选中节点的下游/上游导航（`flowNeighbor`，命中即选中并居中；折叠内目标自动显形） |
| 双击 dialogue / comment 节点   | 行内编辑（Enter 提交、Shift+Enter 换行、Esc 取消、失焦提交）                    |

## 视觉（Archify「midnight console」词汇）

画布 `#020617` / 面板 `#0F172A` / 点格 `#1E293B`；文字三级 `#FFFFFF`/`#94A3B8`/`#475569`；
kind 语义色（青 dialogue / 紫 inst / 琥珀 option·cond / 玫瑰 jump / 灰 comment·end / 绿 start）；
节点公式 = 不透明底色（`color-mix(语义色 10%, #0F172A)`）+ 1.5px 全饱和描边 + 6px 圆角，Flat-at-Rest；
连线为正交折线（smoothstep，8px 圆角）1.5px `#64748B` + 闭合小三角；标签药丸底色块（panel，rx 3）。
全局面等宽（@fontsource/jetbrains-mono 400/600/700），CJK 走系统回退；单行截断一律尾部保留（TailText）。

- **Inspector（spec 驱动）**：dialogue 角色/台词/锚点 chips/prev/post 槽编辑器；
  inst 参数表单（STR→text、FLOAT/INT→number、BOOL→开关；role=audio/texture→refs datalist、
  role=script→剧本 datalist、scene_type→select、res_path→text）；
  option_group 选项行（text/cond/↑↓/删除/添加）；cond 分支行（else 锁定/添加 elif）；
  jump 目标（剧本 + main_menu datalist）；comment 多行文本。
- **保存流**：`emitGraph` → POST save（text + `buildSidecar`）→ 自动 POST check →
  diags 经 lineMap 映射到节点（行落区间即归属）→ 节点红/黄角标 + 诊断面板点击 setCenter 定位。
  fixtures 模式 save 返回 403「只读」。
- **回环校验**（fixtures 禁用）：GET 服务端新鲜 dump → `semanticEqual`（剥 comment）→
  顶栏下方横幅：绿「图文一致」/ 红 diffs 列表。
- **撤销**：图 JSON 深拷贝快照，cap 100；同 tag 连续输入 800ms 内合并为一个撤销步。

## 调试桥（--dev）

服务端 `--dev`（或 `BGALS_DEV=1`）注册 `/api/dev/*`；前端启动时 GET `/api/dev/enabled`，
为 true 则 `EventSource("/api/dev/events")` 接命令，执行后 POST `/api/dev/result` 回传。
外部脚本经 `/api/dev/command` 驱动浏览器内编辑器（无浏览器连接时 10s 超时 504）：

```bash
# ping
curl -X POST localhost:8787/api/dev/command -H 'Content-Type: application/json' -d '{"action":"ping"}'
# → {"id":"…","ok":true,"data":"pong"}

# 自描述：全部 action 名与参数签名
curl -X POST localhost:8787/api/dev/command -d '{"action":"list_commands"}'
# → {…"data":[{"action":"ping","params":"{}"},{"action":"fill","params":"{selector,value}"},…]}

# 编辑器状态（含节点清单，命令行定位节点的关键）
curl -X POST localhost:8787/api/dev/command -d '{"action":"state"}'
# → {…"data":{"script","nodeCount","edgeCount","selectedId","dirty","diagCounts",
#     "nodes":[{"id","kind","label"}]}}   label：dialogue 文本前 20 字 / inst head / jump target / 选项组首选项文本

# 切剧本 / 选节点 / 追加节点 / 保存 / 检查 / 回环校验 / 撤销重做
curl -X POST localhost:8787/api/dev/command -d '{"action":"select_script","args":{"script":"demo_scene2"}}'
curl -X POST localhost:8787/api/dev/command -d '{"action":"select_node","args":{"id":"n3"}}'
curl -X POST localhost:8787/api/dev/command -d '{"action":"add_node","args":{"kind":"inst","head":"WAIT"}}'
curl -X POST localhost:8787/api/dev/command -d '{"action":"save"}'

# DOM 直控：click{selector} / fill{selector,value} / key{key,ctrl?,shift?} / delete_selected
curl -X POST localhost:8787/api/dev/command -d '{"action":"key","args":{"key":"s","ctrl":true}}'
```

## fixtures 再生成

引擎仓库根目录下（产物变更后重跑）：

```bash
godot --headless --path . -s tool/bgals_cli.gd -- spec --out editor/public/fixtures/spec.json
godot --headless --path . -s tool/bgals_cli.gd -- dump --src GalSs/<脚本名>.tres --out editor/public/fixtures/graphs/<脚本名>.json
godot --headless --path . -s tool/bgals_cli.gd -- check --src scripts --out editor/public/fixtures/check.sample.json
```

## 与引擎的契约

- spec / graph / check 三种 JSON 全部由引擎无头 CLI（`tool/bgals_cli.gd`）产出，前端零硬编码指令集。
- 图格式版本 `bgals-graph/1`；spec/graph 均带 `compiler` 字段，不匹配时以引擎为准重新 dump。
- 职责单向：GDScript 只解析不发射，TS 只发射不解析；图文互译以编译产物为桥。
- `GET /api/mode` 返回 `{mode: "fixtures"|"live", dev: boolean}`，前端据此禁用 fixtures 下的写操作入口。

## 编码规范

- TypeScript strict；组件 `PascalCase.tsx`，工具 `camelCase.ts`；单文件超 ~250 行考虑拆分。
- 门禁：`npm run lint`（ESLint 9 flat）+ `npm run test`（vitest）+ `npm run build`（tsc + vite）。
- 提交前 `npm run format`（Prettier）。

## 已知边界（M2）

- 撤销栈只含图快照：节点位置（sidecar 布局）随拖动实时更新但不进撤销栈，撤销不还原布局。
- jump 为终端节点：不能插在 seq 边中间（插入菜单中禁用），仅可末尾追加。
- 诊断定位依赖 emit lineMap（当前内存图口径）；未保存就「检查」时，行号按内存图尽力映射。
- dialogue 内锚点只读，修改台词后由引擎下次 dump 重建。
