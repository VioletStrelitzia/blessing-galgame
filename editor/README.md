# BGalS 可视化剧本编辑器（M1：只读查看器）

面向编剧的 Web 可视化剧本编辑器。本目录为单包前端工程：Vite + React + TypeScript 前端、
Hono 本地伴随服务、以及 web/server 共用的纯 TS 层（`shared/`）。设计文档见
`docs/可视化编辑器与编译管线设计.md`。

## 目录结构

```
editor/
├── public/fixtures/        # 真实 CLI 产出的离线数据（spec / graphs / check 样例）
├── shared/                 # 纯 TS，web 与 server 共用
│   ├── graph.ts            #   bgals-graph/1 图 JSON 类型
│   ├── spec.ts             #   spec.json 类型
│   ├── check.ts            #   check 报告类型 + file→剧本名换算
│   └── emit.ts(+test)      #   图 → BGalS 文本发射器（纯函数，M2 导出核心）
├── server/                 # Hono 伴随服务（:8787）
│   ├── index.ts            #   /api/* 路由 + 生产模式托管 dist
│   ├── fixtures.ts         #   fixtures 模式数据源
│   └── godot.ts            #   live 模式：spawn 引擎 CLI，临时文件读回 JSON
└── src/                    # React 前端
    ├── graph/              #   toFlow / dagre 布局 / 自定义节点
    └── panels/             #   剧本列表 / 属性 Inspector / 诊断
```

## 启动

```bash
npm install

# 模式一：fixtures 离线开发（无需 Godot，数据来自 public/fixtures/）
npm run dev:server -- --fixtures     # 伴随服务 :8787
npm run dev                          # 前端 :5173（/api 代理到 8787）

# 模式二：live 连引擎（BGALS_GODOT 必填；BGALS_PROJECT 默认本目录上溯一级）
export BGALS_GODOT=/path/to/godot
npm run dev:server

# 生产：构建后由伴随服务直接托管（live 模式且 dist 存在时）
npm run build && npm run dev:server
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

## 编码规范

- TypeScript strict；组件 `PascalCase.tsx`，工具 `camelCase.ts`；单文件超 ~200 行考虑拆分。
- 门禁：`npm run lint`（ESLint 9 flat）+ `npm run test`（vitest）+ `npm run build`（tsc + vite）。
- 提交前 `npm run format`（Prettier）。

## 已知边界（M1）

- 只读：画布不可拖拽编辑；M2 引入编辑、sidecar 与导出。
- 诊断定位：`bgals-graph/1` 节点尚无行号字段，诊断面板点击仅在节点携带行号信息时定位（M3 随 dump 补齐行号后生效）；当前按 `file` 匹配当前剧本。
