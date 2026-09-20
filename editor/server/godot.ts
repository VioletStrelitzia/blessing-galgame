// live 模式数据源：spawn 引擎无头 CLI（tool/bgals_cli.gd），JSON 一律走临时文件读回。
// BGALS_GODOT 必填（Godot 可执行文件）；BGALS_PROJECT 默认编辑器上溯一级（仓库根）。

import { execFile } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { mkdir, readdir, readFile, unlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { EDITOR_ROOT, HttpError, type Source } from "./fixtures";

const execFileAsync = promisify(execFile);

export function createLiveSource(): Source {
  const godot = process.env.BGALS_GODOT;
  const project = path.resolve(process.env.BGALS_PROJECT ?? path.join(EDITOR_ROOT, ".."));

  // overview 短时缓存（spawn CLI 开销大，5s 窗口内复用）
  let overviewCache: { at: number; data: unknown } | null = null;

  async function projectConfig(): Promise<{ readDir: string; saveDir: string }> {
    try {
      const cfg = JSON.parse(await readFile(path.join(project, "config.json"), "utf8")) as {
        scripts?: { read_dir?: string; save_dir?: string };
      };
      return {
        readDir: cfg.scripts?.read_dir ?? "scripts",
        saveDir: cfg.scripts?.save_dir ?? "GalSs",
      };
    } catch {
      return { readDir: "scripts", saveDir: "GalSs" };
    }
  }

  /** outFlag：报告文件参数名——check/dump/spec 为 --out，compile 为 --report（可选） */
  async function runCli(args: string[], outFlag = "--out"): Promise<unknown> {
    if (!godot) throw new Error("live 模式需要环境变量 BGALS_GODOT（Godot 可执行文件路径）");
    const out = path.join(
      os.tmpdir(),
      `bgals-cli-${process.pid}-${Date.now()}-${Math.random().toString(36).slice(2)}.json`,
    );
    const cliArgs = [
      "--headless",
      "--path",
      project,
      "-s",
      "tool/bgals_cli.gd",
      "--",
      ...args,
      outFlag,
      out,
    ];
    try {
      await execFileAsync(godot, cliArgs, { cwd: project, timeout: 120_000 });
    } catch (err) {
      // 退出码 1 = 诊断含 error：报告照常写盘，读回即可；其余为用法/IO/版本错误
      const code = (err as { code?: number | string }).code;
      if (code !== 1) {
        throw new Error(`bgals_cli 执行失败（退出码 ${String(code)}）: ${(err as Error).message}`, {
          cause: err,
        });
      }
    }
    try {
      return JSON.parse(await readFile(out, "utf8"));
    } finally {
      await unlink(out).catch(() => {});
    }
  }

  /** 引擎命名规则：相对路径去扩展名、分隔符换下划线（如 demo/scene1 → demo_scene1） */
  function scriptNameOfRel(rel: string): string {
    return rel.split(/[\\/]/).join("_");
  }

  /** 遍历 readDir 找「引擎名 = script」的 <name>.<ext> 文件（_ 与目录分级不可逆，只能扫目录匹配） */
  async function findByScriptName(
    root: string,
    script: string,
    ext: string,
  ): Promise<string | null> {
    let entries;
    try {
      entries = await readdir(root, { recursive: true, withFileTypes: true });
    } catch {
      return null;
    }
    for (const e of entries) {
      if (!e.isFile() || !e.name.endsWith(ext)) continue;
      const full = path.join(e.parentPath, e.name);
      const rel = path.relative(root, full);
      if (scriptNameOfRel(rel.slice(0, -ext.length)) === script) return full;
    }
    return null;
  }

  /** 剧本名 → 落盘相对路径：扁平文件已存在则沿用；否则按 _ 逐级匹配现有目录结构；匹配不到放平铺 */
  async function resolveScriptRel(root: string, script: string): Promise<string> {
    if (existsSync(path.join(root, `${script}.txt`))) return script;
    const segs = script.split("_");
    const dirs: string[] = [];
    let i = 0;
    while (i < segs.length - 1) {
      const next = path.join(root, ...dirs, segs[i]);
      if (!existsSync(next) || !statSync(next).isDirectory()) break;
      dirs.push(segs[i]);
      i++;
    }
    return [...dirs, segs.slice(i).join("_")].join("/");
  }

  return {
    spec: () => runCli(["spec"]),
    async listGraphs() {
      const { saveDir } = await projectConfig();
      try {
        const files = await readdir(path.join(project, saveDir));
        return files
          .filter((f) => f.endsWith(".tres"))
          .sort()
          .map((f) => ({ script: f.replace(/\.tres$/, "") }));
      } catch {
        return [];
      }
    },
    async graph(script) {
      const { saveDir } = await projectConfig();
      // 先增量编译（哈希保证廉价），保证外部改动 txt 后回读新鲜
      await runCli(["compile"], "--report");
      const tres = path.join(project, saveDir, `${script}.tres`);
      try {
        await readFile(tres);
      } catch {
        return null;
      }
      return runCli(["dump", "--src", `${saveDir}/${script}.tres`]);
    },
    async check() {
      const { readDir } = await projectConfig();
      return runCli(["check", "--src", readDir]);
    },
    async refs() {
      return JSON.parse(await readFile(path.join(project, "index.json"), "utf8"));
    },
    async overview() {
      if (overviewCache !== null && Date.now() - overviewCache.at < 5_000) {
        return overviewCache.data;
      }
      // 先增量编译（哈希保证廉价），与 /api/graph 同口径保鲜
      await runCli(["compile"], "--report");
      const data = await runCli(["overview"]);
      overviewCache = { at: Date.now(), data };
      return data;
    },
    async sidecar(script) {
      const { readDir } = await projectConfig();
      const found = await findByScriptName(path.join(project, readDir), script, ".graph.json");
      return found === null ? null : JSON.parse(await readFile(found, "utf8"));
    },
    async save(script, text, sidecar) {
      const { readDir } = await projectConfig();
      const root = path.join(project, readDir);
      const rel = await resolveScriptRel(root, script);
      const txtPath = path.join(root, `${rel}.txt`);
      await mkdir(path.dirname(txtPath), { recursive: true });
      await writeFile(txtPath, text, "utf8");
      if (sidecar !== undefined) {
        await writeFile(
          path.join(root, `${rel}.graph.json`),
          JSON.stringify(sidecar, null, 2) + "\n",
          "utf8",
        );
      }
      const compile = await runCli(["compile"], "--report");
      return { ok: true, script, path: rel, compile };
    },
    async createScript(name) {
      const { readDir } = await projectConfig();
      const txtPath = path.join(project, readDir, `${name}.txt`);
      if (existsSync(txtPath)) throw new HttpError(409, `剧本已存在: ${name}`);
      await mkdir(path.dirname(txtPath), { recursive: true });
      await writeFile(txtPath, "# 新剧本\n", "utf8");
      return { script: name };
    },
  };
}
