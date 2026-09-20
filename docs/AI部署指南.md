# AI 部署指南（交给 AI 助手执行的部署剧本）

> **用法**：把本文件交给任意 AI 编码助手（Kimi Code / Claude Code / Cursor 等），让它按步骤执行并逐项验证。
> 目标环境：Windows 10+。**核心原则：全部自包含在项目文件夹内，不写用户主目录、不动系统环境**（除非用户另有要求）。

## 上下文

- 仓库根目录 = 本文件上两级目录（含 `project.godot` 的就是）。下文称 `$ROOT`。
- 项目 = Godot 4.5 引擎项目 + `editor/`（Node.js Web 剧本编辑器）。
- 需要两个便携运行时：Godot 4.5.1、Node.js ≥ 20（建议 24.x）。便携 = zip 解压即用，无安装器、不写注册表。
- 约定安装到 `$ROOT/tools/`（`tools/godot/`、`tools/node/`），该目录已入 .gitignore。

## 执行步骤

### 0. 环境探针

```bash
node --version        # 有 ≥20 的 Node 可跳过第 2 节（用户已有的可用，不算污染）
```
检查 `$ROOT/tools/` 下是否已有便携运行时，有则复用。

### 1. Godot 便携安装

```bash
mkdir -p "$ROOT/tools/godot"
curl -L -o "$ROOT/tools/godot.zip" "https://github.com/godotengine/godot/releases/download/4.5.1-stable/Godot_v4.5.1-stable_win64.exe.zip"
tar -xf "$ROOT/tools/godot.zip" -C "$ROOT/tools/godot"
"$ROOT/tools/godot/Godot_v4.5.1-stable_win64_console.exe" --version   # 期望输出 4.5.1.stable…
rm "$ROOT/tools/godot.zip"
```

（`tar` 在 Win10+ 原生支持 zip；不行就用 `powershell Expand-Archive`。）

### 2. Node.js 便携安装（若第 0 步没有可用 Node）

```bash
curl -L -o "$ROOT/tools/node.zip" "https://nodejs.org/dist/v24.15.0/node-v24.15.0-win-x64.zip"
mkdir -p "$ROOT/tools/node" && cd "$ROOT/tools" && tar -xf node.zip -C node --strip-components=1
"$ROOT/tools/node/node.exe" --version    # 期望 v24.x
rm "$ROOT/tools/node.zip"
```

下文 `npm` 指 `"$ROOT/tools/node/npm.cmd"`（Git Bash 下可用 `node npm-cli.js` 形式：`"$ROOT/tools/node/node.exe" "$ROOT/tools/node/node_modules/npm/bin/npm-cli.js"`）。

### 3. 引擎侧验证（无编辑器也能跑）

```bash
cd "$ROOT"
"$ROOT/tools/godot/Godot_v4.5.1-stable_win64_console.exe" --headless --path . --import
"$ROOT/tools/godot/Godot_v4.5.1-stable_win64_console.exe" --headless --path . --quit-after 120   # 无 SCRIPT ERROR
for t in smoke diagnostics executor cli; do
  "$ROOT/tools/godot/Godot_v4.5.1-stable_win64_console.exe" --headless --path . -s test/${t}_test.gd   # 各套件应输出 *_TEST_DONE ok=true
done
```

### 4. 编辑器安装与启动

```bash
cd "$ROOT/editor"
export npm_config_cache="$ROOT/tools/.npm-cache"   # npm 缓存也留在项目内
npm install          # 依赖只进 editor/node_modules/
npm run build        # 期望 ✓ built
```

启动（二选一）：

```bash
# A. 离线 fixtures 模式（无需 Godot，只读演示）
npm run dev:server

# B. live 模式（连真引擎，可编辑保存）
BGALS_GODOT="$ROOT/tools/godot/Godot_v4.5.1-stable_win64_console.exe" BGALS_PROJECT="$ROOT" npx tsx server/index.ts --dev
```

验证：`curl http://localhost:8787/api/mode` 返回 JSON；浏览器打开 `http://localhost:8787`。

### 5. 验收清单

| 项 | 通过标准 |
|---|---|
| Godot | `--version` 输出 4.5.1 |
| 引擎测试 | 四套件均 `ok=true` |
| 编辑器构建 | `npm run build` 成功 |
| 服务 | `/api/mode` 返回 `{"mode":…}` |
| 自包含 | 主目录无新增 `.npm`/运行时残留（npm cache 已重定向） |

## 常见问题

- **端口 8787 被占**：`netstat -ano | grep :8787` 找 PID 后 `taskkill //F //PID <pid>`；或设 `BGALS_PORT=8790` 换端口。
- **npm 网络失败**：重试；仍失败可换镜像 `npm config --registry=https://registry.npmmirror.com install`（注意这会写项目内 cache，不写主目录——前提仍是 `npm_config_cache` 已设）。
- **路径含空格/中文**：所有命令的路径参数加双引号。
- **Godot 版本不是 4.5.x**：下载链接写错了版本，回第 1 节核对。

## 给 AI 的注意事项

1. 每一步执行后**先验证再进下一步**；失败时读错误原文，不要盲改。
2. 不写用户主目录：npm cache 用 `npm_config_cache` 重定向；不要执行安装器（.msi/.exe 安装包）；不要改 PATH 等系统设置（用全路径或会话内变量）。
3. 若用户明确说「我已有 Godot/Node 并希望复用」，跳过对应安装节，但验证步骤照跑。
4. 完成后向用户汇报：两个运行时的绝对路径、服务地址、如何停止（Ctrl+C）。
