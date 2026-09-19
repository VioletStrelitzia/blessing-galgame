// live 模式数据源：spawn 引擎无头 CLI（tool/bgals_cli.gd），JSON 一律走临时文件读回。
// BGALS_GODOT 必填（Godot 可执行文件）；BGALS_PROJECT 默认编辑器上溯一级（仓库根）。

import { execFile } from "node:child_process";
import { readdir, readFile, unlink } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { EDITOR_ROOT, type Source } from "./fixtures";

const execFileAsync = promisify(execFile);

export function createLiveSource(): Source {
  const godot = process.env.BGALS_GODOT;
  const project = path.resolve(process.env.BGALS_PROJECT ?? path.join(EDITOR_ROOT, ".."));

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

  async function runCli(args: string[]): Promise<unknown> {
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
      "--out",
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
  };
}
