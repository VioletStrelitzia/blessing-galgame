// BGalS 编辑器伴随服务：/api/* 数据桥（fixtures 离线 / live 经引擎 CLI），生产模式托管 dist。

import { serve } from "@hono/node-server";
import { serveStatic } from "@hono/node-server/serve-static";
import { Hono } from "hono";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { createFixturesSource, EDITOR_ROOT, type Source } from "./fixtures";
import { createLiveSource } from "./godot";

const PORT = 8787;
const SCRIPT_NAME = /^[\w-]+$/;

const fixturesMode = process.argv.includes("--fixtures") || process.env.BGALS_FIXTURES === "1";
const source: Source = fixturesMode ? createFixturesSource() : createLiveSource();

const app = new Hono();

app.onError((err, c) => {
  console.error(err);
  return c.json({ error: err.message }, 500);
});

app.get("/api/spec", async (c) => c.json(await source.spec()));
app.get("/api/graphs", async (c) => c.json(await source.listGraphs()));
app.get("/api/graph/:script", async (c) => {
  const script = c.req.param("script");
  if (!SCRIPT_NAME.test(script)) return c.json({ error: `非法剧本名: ${script}` }, 400);
  const graph = await source.graph(script);
  if (graph === null) return c.json({ error: `剧本不存在: ${script}` }, 404);
  return c.json(graph);
});
app.post("/api/check", async (c) => c.json(await source.check()));

// 生产模式：托管前端构建产物（SPA 回退 index.html）
const dist = path.join(EDITOR_ROOT, "dist");
const indexHtml = path.join(dist, "index.html");
if (!fixturesMode && existsSync(indexHtml)) {
  app.use("/*", serveStatic({ root: dist }));
  app.get("*", (c) => {
    if (c.req.path.startsWith("/api/")) return c.json({ error: "not found" }, 404);
    return c.html(readFileSync(indexHtml, "utf8"));
  });
}

serve({ fetch: app.fetch, port: PORT }, (info) => {
  console.log(`[bgals-editor] mode=${fixturesMode ? "fixtures" : "live"} port=${info.port}`);
});
