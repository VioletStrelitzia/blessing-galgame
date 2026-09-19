// fixtures 模式数据源：直接读 public/fixtures/（真实 CLI 的离线产出），零 Godot 依赖。

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const EDITOR_ROOT = path.resolve(fileURLToPath(new URL(".", import.meta.url)), "..");
const FIXTURES = path.join(EDITOR_ROOT, "public", "fixtures");

/** server 两种模式共用的数据面 */
export interface Source {
  spec(): Promise<unknown>;
  listGraphs(): Promise<{ script: string }[]>;
  graph(script: string): Promise<unknown | null>;
  check(): Promise<unknown>;
}

async function readJson(file: string): Promise<unknown> {
  return JSON.parse(await readFile(file, "utf8"));
}

export function createFixturesSource(): Source {
  return {
    spec: () => readJson(path.join(FIXTURES, "spec.json")),
    async listGraphs() {
      const files = await readdir(path.join(FIXTURES, "graphs"));
      return files
        .filter((f) => f.endsWith(".json"))
        .sort()
        .map((f) => ({ script: f.replace(/\.json$/, "") }));
    },
    async graph(script) {
      try {
        return await readJson(path.join(FIXTURES, "graphs", `${script}.json`));
      } catch {
        return null;
      }
    },
    check: () => readJson(path.join(FIXTURES, "check.sample.json")),
  };
}
